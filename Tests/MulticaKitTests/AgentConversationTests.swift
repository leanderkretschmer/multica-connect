import Foundation
import Testing
@testable import MulticaKit

@Suite("Escalating a voice question to a server agent")
struct AgentConversationTests {
    private let agent = Agent(id: "agent-1", name: "Connect")

    private func makeConversation(
        _ transport: StubTransport,
        projectID: String? = nil,
        timeout: Duration = .seconds(30)
    ) -> AgentConversation {
        AgentConversation(
            client: MulticaAPIClient(credentials: .test, transport: transport),
            agent: agent,
            projectID: projectID,
            pollInterval: .milliseconds(1),
            timeout: timeout,
            sleep: { _ in }
        )
    }

    @Test("The first question opens an issue assigned to the agent")
    func firstQuestionOpensIssue() async throws {
        let transport = StubTransport()
        transport.routes["POST /api/issues"] = { _ in (200, Fixtures.issue(id: "issue-1")) }
        transport.routes["GET /api/issues/issue-1/comments"] = { _ in
            (200, "[\(Fixtures.comment(id: "c-1", content: "On it — drafted a plan."))]")
        }

        let turn = try await makeConversation(transport, projectID: "p-1")
            .ask("Draft a plan for the onboarding flow", context: "Ongoing (1): I1: Ship the board")

        #expect(turn.speaker == .agent)
        #expect(turn.text == "On it — drafted a plan.")

        let body = try #require(transport.requests(matching: "POST /api/issues").first).bodyObject()
        #expect(body["assignee_id"] as? String == "agent-1")
        #expect(body["project_id"] as? String == "p-1")
        #expect(body["status"] as? String == "todo")
        #expect(body["title"] as? String == "Draft a plan for the onboarding flow")
        let description = try #require(body["description"] as? String)
        #expect(description.contains("Draft a plan for the onboarding flow"))
        #expect(description.contains("Ongoing (1): I1: Ship the board"))
    }

    @Test("A follow-up replies in the same thread instead of opening a second issue")
    func followUpRepliesInThread() async throws {
        let transport = StubTransport()
        let poll = Poll()
        transport.routes["POST /api/issues"] = { _ in (200, Fixtures.issue(id: "issue-1")) }
        transport.routes["POST /api/issues/issue-1/comments"] = { _ in
            (200, Fixtures.comment(id: "c-user", content: "and the timeline?", authorType: "member", parentID: "c-1"))
        }
        transport.routes["GET /api/issues/issue-1/comments"] = { _ in
            let round = poll.next()
            var comments = [Fixtures.comment(id: "c-1", content: "First answer.")]
            if round >= 2 {
                comments.append(Fixtures.comment(id: "c-user", content: "and the timeline?", authorType: "member", parentID: "c-1"))
                comments.append(Fixtures.comment(id: "c-2", content: "Two weeks.", parentID: "c-1", createdAt: "2026-08-18T15:05:00Z"))
            }
            return (200, "[\(comments.joined(separator: ","))]")
        }

        let conversation = makeConversation(transport)
        let first = try await conversation.ask("What should we build first?")
        #expect(first.text == "First answer.")

        let second = try await conversation.ask("and the timeline?")
        #expect(second.text == "Two weeks.")

        #expect(transport.requests(matching: "POST /api/issues").count == 1)
        let reply = try #require(transport.requests(matching: "POST /api/issues/issue-1/comments").first)
        #expect(reply.bodyObject()["parent_id"] as? String == "c-1")
    }

    @Test("A comment the user wrote is never mistaken for the agent's answer")
    func ignoresOwnComments() async throws {
        let transport = StubTransport()
        let poll = Poll()
        transport.routes["POST /api/issues"] = { _ in (200, Fixtures.issue(id: "issue-1")) }
        transport.routes["GET /api/issues/issue-1/comments"] = { _ in
            let round = poll.next()
            var comments = [Fixtures.comment(id: "c-me", content: "echo of my ask", authorType: "member")]
            if round >= 2 {
                comments.append(Fixtures.comment(id: "c-agent", content: "Real answer.", createdAt: "2026-08-18T15:10:00Z"))
            }
            return (200, "[\(comments.joined(separator: ","))]")
        }

        let turn = try await makeConversation(transport).ask("anything there?")
        #expect(turn.text == "Real answer.")
    }

    @Test("A silent agent times out but keeps the issue id so the answer is findable")
    func timesOutWithIssueID() async throws {
        let transport = StubTransport()
        transport.routes["POST /api/issues"] = { _ in (200, Fixtures.issue(id: "issue-1")) }
        transport.routes["GET /api/issues/issue-1/comments"] = { _ in (200, "[]") }

        await #expect(throws: AgentConversation.Failure.timedOut(issueID: "issue-1")) {
            _ = try await makeConversation(transport, timeout: .milliseconds(10)).ask("hello?")
        }
    }

    @Test("A long question becomes a readable title, cut on a word boundary")
    func titleClipping() {
        #expect(AgentConversation.title(from: "  Ship it  ") == "Ship it")
        #expect(AgentConversation.title(from: "line one\nline two") == "line one line two")
        #expect(AgentConversation.title(from: "") == "Voice request")

        let long = "Draft a complete plan for the onboarding flow including the sign in screen and the permission prompts"
        let title = AgentConversation.title(from: long)
        #expect(title.count <= 73)
        #expect(title.hasSuffix("…"))
        #expect(title.contains(" …") == false)
    }
}

/// Counts polls so a stubbed route can change its answer over time.
private final class Poll: @unchecked Sendable {
    private var count = 0
    private let lock = NSLock()

    func next() -> Int {
        lock.lock()
        defer { lock.unlock() }
        count += 1
        return count
    }
}
