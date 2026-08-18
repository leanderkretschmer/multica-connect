import Foundation
import MulticaKit

/// Hands work to a server agent without making the call wait for it.
///
/// A Multica agent answers by commenting on an issue, which takes a minute or
/// two — far too long to hold a conversation open. So the tool returns
/// immediately with a sentence the assistant can say, and the reply is
/// announced through ``onReply`` whenever it lands.
@MainActor
final class DelegationCoordinator: AgentDelegation {
    /// Called with the agent's name and its answer once it arrives.
    var onReply: ((String, String) -> Void)?

    private let store: WorkspaceStore
    private var conversations: [String: AgentConversation] = [:]
    private var watchers: [String: Task<Void, Never>] = [:]

    /// The issue backing the most recent hand-off, for the "open in Multica" link.
    private(set) var currentIssueID: String?

    init(store: WorkspaceStore) {
        self.store = store
    }

    nonisolated func handOff(question: String, to agentName: String?) async -> String {
        await start(question: question, agentName: agentName)
    }

    private func start(question: String, agentName: String?) async -> String {
        guard let agent = resolveAgent(named: agentName) else {
            guard !store.agents.isEmpty else {
                return "There are no agents in this workspace to hand that to."
            }
            let names = store.agents.map(\.name).joined(separator: ", ")
            return "I could not find that agent. Available: \(names). Ask which one to use."
        }

        let conversation = conversations[agent.id] ?? AgentConversation(
            client: store.client,
            agent: agent,
            projectID: nil
        )
        conversations[agent.id] = conversation

        // The watcher owns the wait, so this returns in a beat.
        watchers[agent.id]?.cancel()
        watchers[agent.id] = Task { [weak self] in
            guard let self else { return }
            do {
                let turn = try await conversation.ask(question, context: store.digest())
                guard !Task.isCancelled else { return }
                currentIssueID = await conversation.issueID
                onReply?(agent.name, turn.text)
            } catch let failure as AgentConversation.Failure {
                guard !Task.isCancelled else { return }
                if case .timedOut(let issueID) = failure {
                    currentIssueID = issueID
                    onReply?(
                        agent.name,
                        "still working on it. The answer will land on the issue when it is ready."
                    )
                }
            } catch {
                guard !Task.isCancelled else { return }
                onReply?(agent.name, "could not be reached. \(error.localizedDescription)")
            }
            await store.refresh()
        }

        return "Handed that to \(agent.name). I will tell you when it answers."
    }

    /// Falls back to the workspace's default agent when the model did not name one.
    private func resolveAgent(named name: String?) -> Agent? {
        guard let name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return store.agents.first
        }
        return store.agent(named: name)
    }

    func cancelAll() {
        for watcher in watchers.values { watcher.cancel() }
        watchers.removeAll()
    }
}
