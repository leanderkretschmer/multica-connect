import Foundation

/// A back-and-forth with a Multica server agent, carried on an issue.
///
/// Multica has no synchronous "ask an agent" endpoint: work reaches an agent by
/// landing on an issue it owns, and the answer comes back as a comment. This
/// type hides that round trip behind one `await` — open an issue on the first
/// question, reply into the same thread afterwards, and poll until the agent
/// has spoken.
///
/// The on-device model handles everything it can by itself; this is the
/// escalation path for questions that need a real agent with tools and a repo.
public actor AgentConversation {
    /// One turn of the conversation as the UI shows it.
    public struct Turn: Sendable, Hashable, Identifiable {
        public enum Speaker: Sendable, Hashable {
            case you
            case agent
        }

        public let id: String
        public let speaker: Speaker
        public let text: String
        public let at: Date

        public init(id: String, speaker: Speaker, text: String, at: Date) {
            self.id = id
            self.speaker = speaker
            self.text = text
            self.at = at
        }
    }

    public enum Failure: Error, Sendable, Equatable {
        /// The agent did not comment within the allotted window. The issue is
        /// still open and the answer will land there.
        case timedOut(issueID: String)
    }

    private let client: MulticaAPIClient
    private let agent: Agent
    private let projectID: String?
    private let pollInterval: Duration
    private let timeout: Duration
    private let sleep: @Sendable (Duration) async throws -> Void

    /// The issue backing this conversation, once one exists.
    public private(set) var issueID: String?
    /// The root comment every follow-up replies under.
    private var threadRootID: String?
    private var seenCommentIDs: Set<String> = []

    public init(
        client: MulticaAPIClient,
        agent: Agent,
        projectID: String? = nil,
        pollInterval: Duration = .seconds(3),
        timeout: Duration = .seconds(180),
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.client = client
        self.agent = agent
        self.projectID = projectID
        self.pollInterval = pollInterval
        self.timeout = timeout
        self.sleep = sleep
    }

    /// Sends `question` to the agent and waits for its reply.
    ///
    /// - Parameter context: what the on-device model already knows, folded into
    ///   the issue description so the agent does not start cold.
    public func ask(_ question: String, context: String? = nil) async throws -> Turn {
        let issueID: String
        if let existing = self.issueID {
            issueID = existing
            let comment = try await client.addComment(
                issueID: existing,
                content: question,
                parentID: threadRootID
            )
            seenCommentIDs.insert(comment.id)
            if threadRootID == nil { threadRootID = comment.id }
        } else {
            let issue = try await client.createIssue(
                IssueDraft(
                    title: AgentConversation.title(from: question),
                    description: AgentConversation.description(question: question, context: context),
                    projectID: projectID,
                    status: .todo,
                    assigneeID: agent.id
                )
            )
            issueID = issue.id
            self.issueID = issue.id
            // A just-created issue has no comments, so every comment from here
            // on is new by construction — no seeding read needed.
        }

        return try await waitForReply(on: issueID)
    }

    /// Polls the issue until a comment the agent wrote shows up.
    private func waitForReply(on issueID: String) async throws -> Turn {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            try await sleep(pollInterval)
            let comments = try await client.comments(issueID: issueID)
            let fresh = comments
                .filter { !seenCommentIDs.contains($0.id) }
                .sorted { $0.createdAt < $1.createdAt }
            seenCommentIDs.formUnion(comments.map(\.id))

            if threadRootID == nil, let root = comments.first(where: \.isRoot) {
                threadRootID = root.id
            }
            if let reply = fresh.first(where: { $0.authorType == .agent }) {
                if threadRootID == nil { threadRootID = reply.parentID ?? reply.id }
                return Turn(
                    id: reply.id,
                    speaker: .agent,
                    text: reply.content,
                    at: reply.createdAt
                )
            }
        }
        throw Failure.timedOut(issueID: issueID)
    }

    /// A title short enough to read on a board, derived from the question.
    static func title(from question: String) -> String {
        let cleaned = question
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
        guard !cleaned.isEmpty else { return "Voice request" }
        guard cleaned.count > 72 else { return cleaned }
        // Cut on the last word boundary inside the limit so titles never end mid-word.
        let clipped = cleaned.prefix(72)
        if let space = clipped.lastIndex(of: " "), space > clipped.startIndex {
            return String(clipped[clipped.startIndex..<space]) + "…"
        }
        return String(clipped) + "…"
    }

    static func description(question: String, context: String?) -> String {
        var body = "Asked by voice from Multica Connect.\n\n\(question)"
        if let context, !context.isEmpty {
            body += "\n\n## Context from the conversation so far\n\n\(context)"
        }
        return body
    }
}
