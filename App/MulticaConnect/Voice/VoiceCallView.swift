import MulticaKit
import SwiftUI

/// The call screen — the reason the app exists.
///
/// One control starts and ends the call, the transcript fills in as the
/// conversation goes, and a text field is always there for when speaking is not
/// an option.
struct VoiceCallView: View {
    @Bindable var call: VoiceCallModel
    let store: WorkspaceStore

    @Environment(\.scenePhase) private var scenePhase
    @FocusState private var isTypingFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                transcript
                composer
            }
            .navigationTitle("Multica")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        call.clearTranscript()
                    } label: {
                        Label("Clear", systemImage: "trash")
                    }
                    .disabled(call.lines.isEmpty)
                }
            }
            .safeAreaInset(edge: .bottom) {
                callControls
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // A call cannot survive going to the background: the mic session
            // ends, so end it cleanly instead of leaving a dead spinner.
            if phase != .active, call.phase.isActive {
                Task { await call.endCall() }
            }
        }
    }

    // MARK: - Transcript

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if let unavailable = call.assistantUnavailable {
                        UnavailableCard(unavailable: unavailable)
                    } else if call.lines.isEmpty {
                        StarterCard(taskCount: store.board.openCount)
                    }

                    ForEach(call.lines) { line in
                        TranscriptBubble(line: line)
                            .id(line.id)
                    }

                    if !call.liveTranscript.isEmpty {
                        TranscriptBubble(
                            line: VoiceCallModel.Line(
                                speaker: .you,
                                text: call.liveTranscript,
                                isPending: true
                            )
                        )
                        .id(liveBubbleID)
                    }
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: call.lines.count) { _, _ in
                withAnimation { proxy.scrollTo(call.lines.last?.id, anchor: .bottom) }
            }
            .onChange(of: call.liveTranscript) { _, text in
                guard !text.isEmpty else { return }
                withAnimation { proxy.scrollTo(liveBubbleID, anchor: .bottom) }
            }
        }
    }

    private var liveBubbleID: String { "live-transcript" }

    // MARK: - Controls

    private var composer: some View {
        HStack(spacing: 8) {
            TextField("Type instead", text: $call.typedMessage, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 18))
                .focused($isTypingFocused)
                .submitLabel(.send)
                .onSubmit(send)

            Button(action: send) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
            }
            .disabled(call.typedMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityLabel("Send message")
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private var callControls: some View {
        VStack(spacing: 10) {
            if case .failed(let message) = call.phase {
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            CallButton(isActive: call.phase.isActive) {
                Task {
                    if call.phase.isActive {
                        await call.endCall()
                    } else {
                        await call.startCall()
                    }
                }
            }
            .disabled(!call.isAssistantAvailable)

            VStack(spacing: 2) {
                Text(call.phase.label)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(call.phase.isActive ? .primary : .secondary)
                if let hint = call.phase.hint {
                    Text(hint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal)
            .contentTransition(.opacity)
            .animation(.default, value: call.phase)
        }
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    private func send() {
        isTypingFocused = false
        call.sendTypedMessage()
    }
}

// MARK: - Pieces

private struct TranscriptBubble: View {
    let line: VoiceCallModel.Line

    private var isFromPerson: Bool {
        if case .you = line.speaker { return true }
        return false
    }

    private var speakerLabel: String {
        switch line.speaker {
        case .you: "You"
        case .assistant: "Multica"
        case .agent(let name): name
        }
    }

    private var background: some ShapeStyle {
        isFromPerson ? AnyShapeStyle(.tint.opacity(0.15)) : AnyShapeStyle(.quaternary.opacity(0.4))
    }

    var body: some View {
        VStack(alignment: isFromPerson ? .trailing : .leading, spacing: 4) {
            Text(speakerLabel)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            Group {
                if line.text.isEmpty && line.isPending {
                    ProgressView().controlSize(.small)
                } else {
                    Text(line.text)
                        .font(.body)
                        .textSelection(.enabled)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(background, in: .rect(cornerRadius: Theme.cardRadius))
            .opacity(line.isPending && !line.text.isEmpty ? 0.7 : 1)
        }
        .frame(maxWidth: .infinity, alignment: isFromPerson ? .trailing : .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(speakerLabel) said: \(line.text)")
    }
}

private struct StarterCard: View {
    let taskCount: Int

    private let examples = [
        "What's ongoing right now?",
        "Add a task: draft the onboarding copy.",
        "Move CRATCH-4 to finished.",
        "Draft a plan for the voice gateway and put it in Connect.",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("\(taskCount) open tasks", systemImage: "checklist")
                .font(.headline)

            Text("Start a call and talk, or type below. Everything you say is transcribed on this device.")
                .font(.callout)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(examples, id: \.self) { example in
                    Text("“\(example)”")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.quaternary.opacity(0.3), in: .rect(cornerRadius: Theme.cardRadius))
    }
}

private struct UnavailableCard: View {
    let unavailable: Assistant.Unavailable

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(unavailable.title, systemImage: "sparkles")
                .font(.headline)
            Text(unavailable.message)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.quaternary.opacity(0.3), in: .rect(cornerRadius: Theme.cardRadius))
    }
}
