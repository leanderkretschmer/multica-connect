import Foundation
import FoundationModels
import MulticaKit
import Observation

/// The on-device model, wired to the workspace tools.
///
/// Everything the assistant can do by itself happens here; anything heavier is
/// handed to a server agent through ``DelegateToAgentTool``.
@MainActor
@Observable
final class Assistant {
    /// Why the assistant cannot run, phrased for the person in front of it.
    enum Unavailable: Equatable {
        case appleIntelligenceOff
        case deviceNotEligible
        case modelNotReady
        case unknown

        var title: String {
            switch self {
            case .appleIntelligenceOff: "Apple Intelligence is off"
            case .deviceNotEligible: "This device can't run the on-device model"
            case .modelNotReady: "The model is still downloading"
            case .unknown: "The on-device model isn't available"
            }
        }

        var message: String {
            switch self {
            case .appleIntelligenceOff:
                "Turn on Apple Intelligence in Settings to talk to Multica on device. You can still browse and edit tasks."
            case .deviceNotEligible:
                "Voice control needs a device with Apple Intelligence. The board, projects and task editing all still work."
            case .modelNotReady:
                "iOS is still preparing the model. Try again in a few minutes."
            case .unknown:
                "The system model reported no reason. The board and task editing still work."
            }
        }
    }

    private(set) var unavailable: Unavailable?
    /// `true` while the model is producing a reply.
    private(set) var isThinking = false

    private var session: LanguageModelSession?
    private let store: WorkspaceStore
    private let delegation: any AgentDelegation

    init(store: WorkspaceStore, delegation: any AgentDelegation) {
        self.store = store
        self.delegation = delegation
        self.unavailable = Assistant.checkAvailability()
    }

    var isAvailable: Bool { unavailable == nil }

    private static func checkAvailability() -> Unavailable? {
        switch SystemLanguageModel.default.availability {
        case .available:
            nil
        case .unavailable(.appleIntelligenceNotEnabled):
            .appleIntelligenceOff
        case .unavailable(.deviceNotEligible):
            .deviceNotEligible
        case .unavailable(.modelNotReady):
            .modelNotReady
        case .unavailable:
            .unknown
        }
    }

    /// Re-checks availability — Apple Intelligence can be switched on while the
    /// app is in the background.
    func refreshAvailability() {
        unavailable = Assistant.checkAvailability()
        if unavailable != nil { session = nil }
    }

    /// Starts a fresh conversation, seeded with what the workspace looks like
    /// right now so the first question does not need a tool call.
    func startConversation() {
        guard isAvailable else { return }
        let digest = store.digest()
        session = LanguageModelSession(
            tools: WorkspaceTools.all(store: store, delegation: delegation)
        ) {
            Assistant.instructions
            """
            The workspace looks like this right now. Use it for quick answers; \
            call listTasks when you need anything more current or more detailed.

            \(digest)
            """
        }
        session?.prewarm()
    }

    func endConversation() {
        session = nil
        isThinking = false
    }

    /// Asks the model and streams the reply back as it is written.
    ///
    /// - Parameter onPartial: called on the main actor with the answer so far,
    ///   so the transcript can fill in while the model is still writing.
    func respond(to prompt: String, onPartial: @MainActor (String) -> Void) async throws -> String {
        guard let session else { throw AssistantError.notStarted }
        guard !session.isResponding else { throw AssistantError.busy }

        isThinking = true
        defer { isThinking = false }

        var latest = ""
        let stream = session.streamResponse(to: prompt)
        for try await snapshot in stream {
            latest = snapshot.content
            onPartial(latest)
        }
        return latest
    }

    enum AssistantError: LocalizedError {
        case notStarted
        case busy

        var errorDescription: String? {
            switch self {
            case .notStarted: "The conversation has not started yet."
            case .busy: "Still answering the last thing — give it a moment."
            }
        }
    }

    /// The assistant's brief. It is written for speech: this text is the
    /// difference between a useful call and a paragraph nobody wants read out.
    private static let instructions = """
        You are Multica Connect, a voice assistant for a Multica workspace. \
        The person is talking to you, usually hands-free, so every reply is \
        read aloud.

        How to talk:
        - Answer in one or two sentences. Never read out a long list unless \
          asked for one, and cap it at five items.
        - No Markdown, no bullet characters, no emoji, no URLs, no raw UUIDs. \
          Task identifiers like CRATCH-4 are fine to say.
        - Reply in the language the person is speaking.

        How to act:
        - Use the tools rather than guessing. listTasks and listProjects before \
          answering anything factual about the workspace.
        - When someone describes work to be done, create the task. Do not ask \
          for permission first; say what you created afterwards so it can be \
          corrected.
        - Tasks live in four lanes: planned, ongoing, staged (waiting for \
          review), finished.
        - When you need a project and the person did not name one, ask which \
          project — do not invent one.
        - Hand anything to askMulticaAgent that needs the codebase, the web, or \
          real research, then tell the person it has been handed over and that \
          the answer will come back shortly.
        - If a tool reports a failure, say so plainly. Never claim something was \
          created or moved when it was not.
        """
}
