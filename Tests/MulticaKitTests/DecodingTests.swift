import Foundation
import Testing
@testable import MulticaKit

@Suite("Decoding real Multica payloads")
struct DecodingTests {
    let decoder = MulticaAPIClient.makeDecoder()

    @Test("An issue payload decodes every field the board needs")
    func issueDecodes() throws {
        let issue = try decoder.decode(
            Issue.self,
            from: Data(Fixtures.issue(id: "i-1", identifier: "CRATCH-4", status: "in_progress", priority: "high", projectID: "p-1").utf8)
        )
        #expect(issue.id == "i-1")
        #expect(issue.identifier == "CRATCH-4")
        #expect(issue.status == .inProgress)
        #expect(issue.priority == .high)
        #expect(issue.projectID == "p-1")
        #expect(issue.lane == .ongoing)
    }

    @Test("An unknown status decodes as other instead of failing the page")
    func unknownStatusSurvives() throws {
        let issue = try decoder.decode(
            Issue.self,
            from: Data(Fixtures.issue(id: "i-2", status: "awaiting_launch").utf8)
        )
        #expect(issue.status == .other("awaiting_launch"))
        #expect(issue.status.displayName == "Awaiting Launch")
        #expect(issue.lane == .planned)
    }

    @Test("An unknown priority falls back to none rather than throwing")
    func unknownPriorityFallsBack() throws {
        let issue = try decoder.decode(
            Issue.self,
            from: Data(Fixtures.issue(id: "i-3", priority: "critical").utf8)
        )
        #expect(issue.priority == .none)
    }

    @Test("The wrapped list shape and a bare array both decode")
    func issuePageAcceptsBothShapes() throws {
        let wrapped = """
        {"has_more": true, "issues": [\(Fixtures.issue(id: "i-1"))]}
        """
        let page = try decoder.decode(IssuePage.self, from: Data(wrapped.utf8))
        #expect(page.issues.count == 1)
        #expect(page.hasMore)

        let bare = "[\(Fixtures.issue(id: "i-2"))]"
        let barePage = try decoder.decode(IssuePage.self, from: Data(bare.utf8))
        #expect(barePage.issues.count == 1)
        #expect(barePage.hasMore == false)
    }

    @Test("Timestamps decode with and without fractional seconds")
    func timestampsDecode() throws {
        let plain = try decoder.decode(
            Issue.self,
            from: Data(Fixtures.issue(id: "i-1", updatedAt: "2026-08-18T14:40:57Z").utf8)
        )
        let fractional = try decoder.decode(
            Issue.self,
            from: Data(Fixtures.issue(id: "i-2", updatedAt: "2026-08-18T14:40:57.482Z").utf8)
        )
        #expect(plain.updatedAt < fractional.updatedAt)
    }

    @Test("A project payload carries progress counts")
    func projectDecodes() throws {
        let json = """
        {
          "id": "p-1", "title": "multica-connect",
          "description": "voice gateway", "icon": "🎤",
          "status": "in_progress", "priority": "medium",
          "lead_id": null, "lead_type": null,
          "issue_count": 4, "done_count": 1, "resource_count": 1,
          "start_date": null, "due_date": null,
          "created_at": "2026-08-18T14:34:24Z", "updated_at": "2026-08-18T14:34:24Z",
          "workspace_id": "ws-1"
        }
        """
        let project = try decoder.decode(Project.self, from: Data(json.utf8))
        #expect(project.icon == "🎤")
        #expect(project.status == .inProgress)
        #expect(project.completion == 0.25)
    }

    @Test("A comment payload keeps thread and truncation state")
    func commentDecodes() throws {
        let comment = try decoder.decode(
            IssueComment.self,
            from: Data(Fixtures.comment(id: "c-1", parentID: "c-0").utf8)
        )
        #expect(comment.parentID == "c-0")
        #expect(comment.isRoot == false)
        #expect(comment.authorType == .agent)
        #expect(comment.isResolved == false)
    }

    @Test("An agent avatar written as emoji: is unwrapped")
    func agentEmojiAvatar() throws {
        let json = """
        {"id":"a-1","name":"Mika","description":null,"avatar_url":"emoji:🦄","status":"idle","model":"claude-sonnet-5","archived_at":null}
        """
        let agent = try decoder.decode(Agent.self, from: Data(json.utf8))
        #expect(agent.avatarEmoji == "🦄")
        #expect(agent.isArchived == false)
    }

    @Test("/api/me decodes flat and nested shapes")
    func currentUserDecodes() throws {
        let flat = try decoder.decode(
            CurrentUser.self,
            from: Data(#"{"id":"u-1","name":"Leander","email":"lk@example.test"}"#.utf8)
        )
        #expect(flat.displayName == "Leander")

        let nested = try decoder.decode(
            CurrentUser.self,
            from: Data(#"{"user":{"id":"u-2","email":"other@example.test"}}"#.utf8)
        )
        #expect(nested.id == "u-2")
        #expect(nested.displayName == "other@example.test")
    }
}
