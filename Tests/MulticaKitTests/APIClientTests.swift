import Foundation
import Testing
@testable import MulticaKit

@Suite("Requests the client puts on the wire")
struct APIClientTests {
    private func makeClient(_ transport: StubTransport) -> MulticaAPIClient {
        MulticaAPIClient(credentials: .test, transport: transport)
    }

    @Test("Every request carries bearer auth and the workspace header")
    func authHeaders() async throws {
        let transport = StubTransport()
        transport.routes["GET /api/issues"] = { _ in (200, #"{"issues":[],"has_more":false}"#) }
        _ = try await makeClient(transport).issues()

        let request = try #require(transport.requests(matching: "GET /api/issues").first)
        #expect(request.header("Authorization") == "Bearer mat_test_token")
        #expect(request.header("X-Workspace-ID") == "ws-1")
        #expect(request.header("Accept") == "application/json")
    }

    @Test("Issue filters land in the query string")
    func issueFilters() async throws {
        let transport = StubTransport()
        transport.routes["GET /api/issues"] = { _ in (200, #"{"issues":[],"has_more":false}"#) }
        _ = try await makeClient(transport).issues(
            projectID: "p-1",
            status: .inProgress,
            priority: .high,
            limit: 25,
            offset: 50,
            sort: .createdAt,
            direction: .descending
        )

        let request = try #require(transport.requests(matching: "GET /api/issues").first)
        #expect(request.query["project_id"] == "p-1")
        #expect(request.query["status"] == "in_progress")
        #expect(request.query["priority"] == "high")
        #expect(request.query["limit"] == "25")
        #expect(request.query["offset"] == "50")
        #expect(request.query["sort"] == "created_at")
        #expect(request.query["direction"] == "desc")
    }

    @Test("Creating an issue posts snake_case keys and omits unset fields")
    func createIssueBody() async throws {
        let transport = StubTransport()
        transport.routes["POST /api/issues"] = { _ in (200, Fixtures.issue(id: "i-9")) }
        _ = try await makeClient(transport).createIssue(
            IssueDraft(
                title: "Draft the onboarding flow",
                description: "From a voice call",
                projectID: "p-1",
                status: .todo,
                priority: .high
            )
        )

        let body = try #require(transport.requests(matching: "POST /api/issues").first).bodyObject()
        #expect(body["title"] as? String == "Draft the onboarding flow")
        #expect(body["project_id"] as? String == "p-1")
        #expect(body["status"] as? String == "todo")
        #expect(body["priority"] as? String == "high")
        #expect(body["assignee_id"] == nil)
        #expect(body["due_date"] == nil)
    }

    @Test("Moving a task's lane patches only the status")
    func setStatusPatches() async throws {
        let transport = StubTransport()
        transport.routes["PATCH /api/issues/i-1"] = { _ in (200, Fixtures.issue(id: "i-1", status: "in_review")) }
        let issue = try await makeClient(transport).setStatus(.inReview, on: "i-1")

        let request = try #require(transport.requests(matching: "PATCH /api/issues/i-1").first)
        let body = request.bodyObject()
        #expect(body.count == 1)
        #expect(body["status"] as? String == "in_review")
        #expect(issue.status == .inReview)
    }

    @Test("Comment reads pass the thread-scoping flags through")
    func commentQuery() async throws {
        let transport = StubTransport()
        transport.routes["GET /api/issues/i-1/comments"] = { _ in (200, "[]") }
        _ = try await makeClient(transport).comments(
            issueID: "i-1",
            rootsOnly: true,
            summary: true,
            thread: "c-1",
            tail: 30
        )

        let request = try #require(transport.requests(matching: "GET /api/issues/i-1/comments").first)
        #expect(request.query["roots_only"] == "true")
        #expect(request.query["summary"] == "true")
        #expect(request.query["thread"] == "c-1")
        #expect(request.query["tail"] == "30")
    }

    @Test("A reply posts its parent id")
    func replyCarriesParent() async throws {
        let transport = StubTransport()
        transport.routes["POST /api/issues/i-1/comments"] = { _ in (200, Fixtures.comment(id: "c-2")) }
        _ = try await makeClient(transport).addComment(issueID: "i-1", content: "and then?", parentID: "c-1")

        let body = try #require(transport.requests(matching: "POST /api/issues/i-1/comments").first).bodyObject()
        #expect(body["content"] as? String == "and then?")
        #expect(body["parent_id"] as? String == "c-1")
    }

    @Test("Archived agents never reach the picker")
    func archivedAgentsFiltered() async throws {
        let transport = StubTransport()
        transport.routes["GET /api/agents"] = { _ in
            (200, """
            [
              {"id":"a-1","name":"Live","avatar_url":null,"archived_at":null},
              {"id":"a-2","name":"Retired","avatar_url":null,"archived_at":"2026-01-01T00:00:00Z"}
            ]
            """)
        }
        let agents = try await makeClient(transport).agents()
        #expect(agents.map(\.name) == ["Live"])
    }

    @Test("Pagination stops as soon as the server says there is no more")
    func paginationStops() async throws {
        let transport = StubTransport()
        transport.routes["GET /api/issues"] = { request in
            let offset = Int(request.query["offset"] ?? "0") ?? 0
            let more = offset == 0 ? "true" : "false"
            let issue = Fixtures.issue(id: "i-\(offset)")
            return (200, "{\"issues\":[\(issue)],\"has_more\":\(more)}")
        }
        let issues = try await makeClient(transport).allIssues(pageSize: 1)
        #expect(issues.count == 2)
        #expect(transport.requests(matching: "GET /api/issues").count == 2)
    }

    @Test("401 becomes an unauthorized error, not a decoding failure")
    func unauthorizedMapping() async throws {
        let transport = StubTransport()
        transport.routes["GET /api/me"] = { _ in (401, #"{"error":"token revoked"}"#) }
        await #expect(throws: MulticaError.unauthorized) {
            _ = try await makeClient(transport).currentUser()
        }
    }

    @Test("A server error keeps the message the server sent")
    func serverErrorMessage() async throws {
        let transport = StubTransport()
        transport.routes["POST /api/issues"] = { _ in (422, #"{"message":"title is required"}"#) }
        await #expect(throws: MulticaError.server(status: 422, message: "title is required")) {
            _ = try await makeClient(transport).createIssue(IssueDraft(title: ""))
        }
    }

    @Test("A 500 is retryable, a 422 is not")
    func retryClassification() {
        #expect(MulticaError.server(status: 503, message: nil).isRetryable)
        #expect(MulticaError.transport("offline").isRetryable)
        #expect(MulticaError.server(status: 422, message: nil).isRetryable == false)
        #expect(MulticaError.unauthorized.isRetryable == false)
    }
}

@Suite("Server URL normalisation")
struct CredentialTests {
    @Test("A bare host gets HTTPS and loses its trailing slash")
    func normalizes() {
        #expect(MulticaCredentials.normalizedServerURL(from: "agents.crat.ch")?.absoluteString == "https://agents.crat.ch")
        #expect(MulticaCredentials.normalizedServerURL(from: " https://agents.crat.ch/ ")?.absoluteString == "https://agents.crat.ch")
        #expect(MulticaCredentials.normalizedServerURL(from: "http://localhost:8080")?.absoluteString == "http://localhost:8080")
    }

    @Test("Input that cannot address a server is rejected")
    func rejectsGarbage() {
        #expect(MulticaCredentials.normalizedServerURL(from: "") == nil)
        #expect(MulticaCredentials.normalizedServerURL(from: "   ") == nil)
        #expect(MulticaCredentials.normalizedServerURL(from: "ftp://agents.crat.ch") == nil)
    }
}
