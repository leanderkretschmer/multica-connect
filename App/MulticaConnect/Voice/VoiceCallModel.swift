import Foundation
import MulticaKit
import Observation
import SwiftUI

/// Drives the call screen: microphone in, on-device model in the middle, voice
/// out, with an escape hatch to a server agent.
@MainActor
@Observable
final class VoiceCallModel {
    /// What the call is doing right now. The UI reads only this.
    enum Phase: Equatable {
        case idle
        /// Starting up, carrying which step is under way.
        ///
        /// The step is on screen the whole time it runs, so if the app dies
        /// during start-up the last label names the step that killed it. That
        /// is the only diagnosis available when a framework traps instead of
        /// throwing, because a trap leaves no error to catch and report.
        case preparing(Step)
        case listening
        case thinking
        case speaking
        case failed(String)

        enum Step: String, Equatable {
            case microphone
            case speechModel
            case assistant
            case audio

            var label: String {
                switch self {
                case .microphone: "Asking for the microphone…"
                case .speechModel: "Preparing the speech model…"
                case .assistant: "Waking the assistant…"
                case .audio: "Opening the microphone…"
                }
            }
        }

        var isActive: Bool {
            switch self {
            case .idle, .failed: false
            case .preparing, .listening, .thinking, .speaking: true
            }
        }

        var label: String {
            switch self {
            case .idle: "Tap to talk"
            case .preparing(let step): step.label
            case .listening: "Listening"
            case .thinking: "Thinking…"
            case .speaking: "Speaking"
            case .failed: "Something went wrong"
            }
        }

        /// Extra line under the status, where waiting needs explaining.
        var hint: String? {
            switch self {
            case .listening: "Pause when you are done and it will answer."
            default: nil
            }
        }
    }

    /// One line in the call transcript.
    struct Line: Identifiable, Equatable {
        enum Speaker: Equatable {
            case you
            case assistant
            case agent(String)
        }

        let id = UUID()
        let speaker: Speaker
        var text: String
        var isPending: Bool = false
    }

    private(set) var phase: Phase = .idle
    private(set) var lines: [Line] = []
    /// Words heard since the person started their current sentence.
    private(set) var liveTranscript = ""
    /// The locale actually being used, which may differ from the device's.
    private(set) var activeLocale = Locale.current

    /// Typed input, for when speaking is not an option.
    var typedMessage = ""

    /// 0…1 while the system installs a speech model, `nil` when nothing is
    /// downloading — which is the normal case after the first run.
    private(set) var modelDownloadProgress: Double?

    /// Where a previous attempt stopped without finishing, if there was one.
    ///
    /// Read once at launch: a crash during start-up leaves no other trace, and
    /// the person holding the phone is the only one who can report it.
    private(set) var lastUnfinishedStep: Phase.Step?

    private let store: WorkspaceStore
    private let assistant: Assistant
    private let transcription = SpeechTranscription()
    private let narrator = SpeechNarrator()
    private let delegationCoordinator: DelegationCoordinator

    /// How long a pause ends the person's turn.
    private let endpointDelay: Duration = .milliseconds(1_100)

    private var updatesTask: Task<Void, Never>?
    private var endpointTask: Task<Void, Never>?
    private var respondTask: Task<Void, Never>?

    /// Privacy keys this build is missing. Non-empty means a call cannot even
    /// be attempted without iOS killing the app, so it is shown up front rather
    /// than discovered by trying.
    var missingPrivacyKeys: [String] { SpeechTranscription.missingUsageDescriptionKeys }

    var isAssistantAvailable: Bool { assistant.isAvailable }
    var assistantUnavailable: Assistant.Unavailable? { assistant.unavailable }

    init(store: WorkspaceStore) {
        self.lastUnfinishedStep = StartupBreadcrumb.unfinishedStep
        self.store = store
        let coordinator = DelegationCoordinator(store: store)
        self.delegationCoordinator = coordinator
        self.assistant = Assistant(store: store, delegation: coordinator)
        coordinator.onReply = { [weak self] agentName, reply in
            self?.receiveAgentReply(from: agentName, text: reply)
        }
    }

    // MARK: - Call lifecycle

    func startCall() async {
        guard !phase.isActive else { return }
        assistant.refreshAvailability()
        guard assistant.isAvailable else {
            phase = .failed(assistant.unavailable?.message ?? "The on-device model is unavailable.")
            return
        }

        // Anything reported from a previous attempt is answered by this one.
        lastUnfinishedStep = nil

        let missing = SpeechTranscription.missingUsageDescriptionKeys
        guard missing.isEmpty else {
            phase = .failed(
                "This build is missing \(missing.joined(separator: " and ")) in its Info.plist. "
                    + "iOS terminates an app that touches the microphone or speech without them."
            )
            return
        }

        do {
            // The microphone is asked for first, before any download: it is the
            // one step that can be refused, and making someone wait through a
            // model download only to be asked and say no is the wrong order.
            begin(.microphone)
            guard try await SpeechTranscription.requestMicrophoneAccess() else {
                throw SpeechTranscription.Failure.microphoneDenied
            }

            begin(.speechModel)
            let locale = try await transcription.prepare(locale: Locale.current) { [weak self] fraction in
                self?.modelDownloadProgress = fraction
            }
            modelDownloadProgress = nil
            activeLocale = locale

            begin(.assistant)
            assistant.startConversation()

            begin(.audio)
            listen(to: try await transcription.start(locale: locale))

            StartupBreadcrumb.clear()
            phase = .listening
        } catch {
            StartupBreadcrumb.clear()
            modelDownloadProgress = nil
            phase = .failed(error.localizedDescription)
            await teardown()
        }
    }

    /// Enters a start-up step and records it somewhere a crash cannot erase.
    private func begin(_ step: Phase.Step) {
        StartupBreadcrumb.begin(step)
        phase = .preparing(step)
    }

    func endCall() async {
        await teardown()
        phase = .idle
    }

    /// Dismisses the report from a previous attempt.
    func acknowledgeLastFailure() {
        lastUnfinishedStep = nil
        StartupBreadcrumb.clear()
    }

    private func teardown() async {
        StartupBreadcrumb.clear()
        endpointTask?.cancel()
        endpointTask = nil
        respondTask?.cancel()
        respondTask = nil
        updatesTask?.cancel()
        updatesTask = nil
        narrator.stop()
        await transcription.stop()
        assistant.endConversation()
        liveTranscript = ""
    }

    func clearTranscript() {
        lines.removeAll()
    }

    // MARK: - Hearing

    private func listen(to updates: AsyncStream<SpeechTranscription.Update>) {
        updatesTask?.cancel()
        updatesTask = Task { [weak self] in
            for await update in updates {
                guard !Task.isCancelled, let self else { return }
                receive(update)
            }
        }
    }

    private func receive(_ update: SpeechTranscription.Update) {
        // Anything heard while the assistant is talking or working is echo or
        // an interruption we are not ready to act on.
        guard phase == .listening else { return }
        liveTranscript = update.text
        scheduleEndpoint()
    }

    /// Treats a pause as the end of the person's turn.
    private func scheduleEndpoint() {
        endpointTask?.cancel()
        let text = liveTranscript
        let delay = endpointDelay
        endpointTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            // Anything new arrived in the meantime, so the turn is not over.
            guard liveTranscript == text else { return }
            submitHeardUtterance()
        }
    }

    private func submitHeardUtterance() {
        let spoken = liveTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        liveTranscript = ""
        transcription.resetUtterance()
        guard spoken.count > 1 else { return }
        send(spoken)
    }

    // MARK: - Typing

    func sendTypedMessage() {
        let text = typedMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        typedMessage = ""
        if !phase.isActive {
            assistant.refreshAvailability()
            guard assistant.isAvailable else {
                phase = .failed(assistant.unavailable?.message ?? "The on-device model is unavailable.")
                return
            }
            assistant.startConversation()
        }
        send(text, speakReply: false)
    }

    // MARK: - Answering

    private func send(_ text: String, speakReply: Bool = true) {
        lines.append(Line(speaker: .you, text: text))
        phase = .thinking
        transcription.isMuted = true

        respondTask?.cancel()
        respondTask = Task { [weak self] in
            guard let self else { return }
            let pending = Line(speaker: .assistant, text: "", isPending: true)
            lines.append(pending)
            let index = lines.count - 1

            do {
                let answer = try await assistant.respond(to: text) { [weak self] partial in
                    guard let self, lines.indices.contains(index) else { return }
                    lines[index].text = partial
                }
                guard !Task.isCancelled else { return }
                if lines.indices.contains(index) {
                    lines[index].text = answer
                    lines[index].isPending = false
                }
                if speakReply {
                    await speakThenListen(answer)
                } else {
                    resumeListeningIfActive()
                }
            } catch is CancellationError {
                if lines.indices.contains(index) { lines.remove(at: index) }
            } catch {
                if lines.indices.contains(index) {
                    lines[index].text = error.localizedDescription
                    lines[index].isPending = false
                }
                resumeListeningIfActive()
            }
        }
    }

    private func speakThenListen(_ text: String) async {
        phase = .speaking
        await withCheckedContinuation { continuation in
            narrator.speak(text, locale: activeLocale) {
                continuation.resume()
            }
        }
        resumeListeningIfActive()
    }

    private func resumeListeningIfActive() {
        transcription.isMuted = false
        transcription.resetUtterance()
        liveTranscript = ""
        if transcription.isRunning {
            phase = .listening
        } else if case .failed = phase {
            // Keep the failure on screen.
        } else {
            phase = .idle
        }
    }

    // MARK: - Server agent replies

    private func receiveAgentReply(from agentName: String, text: String) {
        lines.append(Line(speaker: .agent(agentName), text: text))
        // The agent may have created or moved things; pull the board back in line.
        Task { await store.refresh() }

        // Only read it out if the call is still up and nothing else is talking.
        guard phase == .listening else { return }
        Task { [weak self] in
            guard let self else { return }
            transcription.isMuted = true
            await speakThenListen("\(agentName) answered. \(text)")
        }
    }

    /// The issue a hand-off is riding on, so the UI can link to it.
    var delegatedIssueID: String? { delegationCoordinator.currentIssueID }
}
