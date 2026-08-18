import Foundation
import Testing
@testable import MulticaKit

@Suite("Lists arrive bare or wrapped, and both must work")
struct EnvelopeTests {
    private func makeClient(_ transport: StubTransport) -> MulticaAPIClient {
        MulticaAPIClient(credentials: .test, transport: transport)
    }

    private let project = """
    {"id":"p-1","title":"Connect","status":"in_progress","priority":"medium",
     "issue_count":2,"done_count":1,"resource_count":0,
     "created_at":"2026-08-18T14:34:24Z","updated_at":"2026-08-18T14:34:24Z"}
    """

    @Test("A bare array decodes")
    func bareArray() throws {
        let payload = try MulticaAPIClient.makeDecoder()
            .decode(ListPayload<Project>.self, from: Data("[\(project)]".utf8))
        #expect(payload.items.count == 1)
    }

    @Test("An array wrapped under its own name decodes")
    func namedEnvelope() throws {
        let payload = try MulticaAPIClient.makeDecoder()
            .decode(ListPayload<Project>.self, from: Data(#"{"projects":[\#(project)]}"#.utf8))
        #expect(payload.items.first?.title == "Connect")
    }

    @Test("An array wrapped under a key this version has never seen still decodes")
    func unknownEnvelopeKey() throws {
        let json = #"{"whatever_they_rename_it_to":[\#(project)],"total":1}"#
        let payload = try MulticaAPIClient.makeDecoder()
            .decode(ListPayload<Project>.self, from: Data(json.utf8))
        #expect(payload.items.count == 1)
    }

    @Test("The conventional data key wins over other arrays in the object")
    func prefersDataKey() throws {
        let json = #"{"warnings":[],"data":[\#(project)]}"#
        let payload = try MulticaAPIClient.makeDecoder()
            .decode(ListPayload<Project>.self, from: Data(json.utf8))
        #expect(payload.items.count == 1)
    }

    @Test("An object with no array in it fails with the keys it did find")
    func noArrayAtAll() {
        #expect(throws: (any Error).self) {
            try MulticaAPIClient.makeDecoder()
                .decode(ListPayload<Project>.self, from: Data(#"{"error":"nope"}"#.utf8))
        }
    }

    @Test("Agents decode whether the server wraps them or not")
    func agentsBothShapes() async throws {
        let agent = #"{"id":"a-1","name":"Connect","avatar_url":null,"archived_at":null}"#

        for body in ["[\(agent)]", #"{"agents":[\#(agent)]}"#] {
            let transport = StubTransport()
            transport.routes["GET /api/agents"] = { _ in (200, body) }
            let agents = try await makeClient(transport).agents()
            #expect(agents.map(\.name) == ["Connect"], "failed for body: \(body)")
        }
    }

    @Test("Workspaces decode whether the server wraps them or not")
    func workspacesBothShapes() async throws {
        let workspace = #"{"id":"ws-1","name":"crat.ch","slug":"crat-ch"}"#

        for body in ["[\(workspace)]", #"{"workspaces":[\#(workspace)]}"#] {
            let transport = StubTransport()
            transport.routes["GET /api/workspaces"] = { _ in (200, body) }
            let workspaces = try await makeClient(transport).workspaces()
            #expect(workspaces.map(\.name) == ["crat.ch"], "failed for body: \(body)")
        }
    }

    @Test("Projects and comments decode whether wrapped or not")
    func projectsAndCommentsBothShapes() async throws {
        for body in ["[\(project)]", #"{"projects":[\#(project)]}"#] {
            let transport = StubTransport()
            transport.routes["GET /api/projects"] = { _ in (200, body) }
            #expect(try await makeClient(transport).projects().count == 1, "failed for body: \(body)")
        }

        let comment = Fixtures.comment(id: "c-1")
        for body in ["[\(comment)]", #"{"comments":[\#(comment)]}"#] {
            let transport = StubTransport()
            transport.routes["GET /api/issues/i-1/comments"] = { _ in (200, body) }
            let comments = try await makeClient(transport).comments(issueID: "i-1")
            #expect(comments.count == 1, "failed for body: \(body)")
        }
    }

    @Test("The issue page reads its own envelope, a bare array, and a renamed envelope")
    func issuePageShapes() async throws {
        let issue = Fixtures.issue(id: "i-1")

        let wrapped = #"{"issues":[\#(issue)],"has_more":true,"total":9}"#
        let page = try MulticaAPIClient.makeDecoder().decode(IssuePage.self, from: Data(wrapped.utf8))
        #expect(page.issues.count == 1)
        #expect(page.hasMore)

        let bare = try MulticaAPIClient.makeDecoder()
            .decode(IssuePage.self, from: Data("[\(issue)]".utf8))
        #expect(bare.issues.count == 1)
        #expect(bare.hasMore == false)

        let renamed = try MulticaAPIClient.makeDecoder()
            .decode(IssuePage.self, from: Data(#"{"data":[\#(issue)],"has_more":false}"#.utf8))
        #expect(renamed.issues.count == 1)
    }
}

@Suite("Labels, whose element shape the API never showed us")
struct LabelTests {
    private let decoder = MulticaAPIClient.makeDecoder()

    private func issue(labels: String) -> String {
        Fixtures.issue(id: "i-1").replacingOccurrences(of: #""labels": [],"#, with: #""labels": \#(labels),"#)
    }

    @Test("An object label decodes with its colour")
    func objectLabel() throws {
        let decoded = try decoder.decode(
            MulticaKit.Issue.self,
            from: Data(issue(labels: ##"[{"id":"l-1","name":"bug","color":"#6b7280"}]"##).utf8)
        )
        #expect(decoded.labels.map(\.name) == ["bug"])
        #expect(decoded.labels.first?.color == "#6b7280")
    }

    @Test("A bare string label decodes as a name")
    func stringLabel() throws {
        let decoded = try decoder.decode(MulticaKit.Issue.self, from: Data(issue(labels: #"["urgent"]"#).utf8))
        #expect(decoded.labels.map(\.name) == ["urgent"])
        #expect(decoded.labels.first?.id == "urgent")
    }

    @Test("A label with only a name still renders")
    func nameOnlyLabel() throws {
        let decoded = try decoder.decode(MulticaKit.Issue.self, from: Data(issue(labels: #"[{"name":"chore"}]"#).utf8))
        #expect(decoded.labels.map(\.name) == ["chore"])
    }

    @Test("A label shape nobody predicted costs the labels, never the task")
    func unexpectedLabelShapeDoesNotLoseTheIssue() throws {
        let decoded = try decoder.decode(MulticaKit.Issue.self, from: Data(issue(labels: "[42, 43]").utf8))
        #expect(decoded.labels.isEmpty)
        #expect(decoded.title == "A task", "the issue itself must survive")
        #expect(decoded.identifier == "TEST-1")
    }
}

@Suite("Timestamps as Go actually emits them")
struct TimestampTests {
    private let decoder = MulticaAPIClient.makeDecoder()

    /// Go's RFC3339Nano trims trailing zeros, so the number of fractional
    /// digits varies by row; Postgres commonly yields six.
    @Test(
        "Every fractional precision and offset the server can produce parses",
        arguments: [
            "2026-08-18T14:40:48Z",
            "2026-08-18T14:40:48.4Z",
            "2026-08-18T14:40:48.48Z",
            "2026-08-18T14:40:48.482Z",
            "2026-08-18T14:40:48.482123Z",
            "2026-08-18T14:40:48.482123456Z",
            "2026-08-18T14:40:48+00:00",
            "2026-08-18T14:40:48.482+00:00",
            "2026-08-18T16:40:48+02:00",
            "2026-08-18T16:40:48.482+02:00",
        ]
    )
    func timestampParses(_ stamp: String) throws {
        let decoded = try decoder.decode(
            MulticaKit.Issue.self,
            from: Data(Fixtures.issue(id: "i-1", updatedAt: stamp).utf8)
        )
        #expect(decoded.updatedAt != .distantPast, "\(stamp) did not parse")
    }

    @Test("A timestamp that is not a date at all is reported, not silently zeroed")
    func rubbishTimestamp() {
        #expect(throws: (any Error).self) {
            try decoder.decode(MulticaKit.Issue.self, from: Data(Fixtures.issue(id: "i-1", updatedAt: "yesterday").utf8))
        }
    }
}

@Suite("A decoding failure has to say what broke")
struct ErrorDetailTests {
    @Test("The message names the endpoint and the field")
    func namesFieldAndPath() async throws {
        let transport = StubTransport()
        // `title` is required; sending a number for it is a type mismatch.
        transport.routes["GET /api/issues/i-1"] = { _ in
            (200, #"{"id":"i-1","identifier":"X-1","title":42}"#)
        }
        let client = MulticaAPIClient(credentials: .test, transport: transport)

        do {
            _ = try await client.issue(id: "i-1")
            Testing.Issue.record("expected a decoding failure")
        } catch let error as MulticaError {
            guard case .decoding(let detail) = error else {
                Testing.Issue.record("expected .decoding, got \(error)")
                return
            }
            #expect(detail.contains("/api/issues/i-1"), "detail should name the endpoint: \(detail)")
            #expect(detail.contains("title"), "detail should name the field: \(detail)")
            #expect(error.userMessage.contains("title"), "the message shown to a person must carry it too")
        }
    }

    @Test("A missing required field is reported by name")
    func namesMissingField() {
        let error = MulticaError.describe(
            DecodingError.keyNotFound(
                AnyCodingKey(stringValue: "identifier")!,
                .init(codingPath: [], debugDescription: "")
            ),
            path: "/api/issues"
        )
        #expect(error.contains("missing field 'identifier'"))
        #expect(error.contains("/api/issues"))
    }
}

@Suite("Signing in before a workspace is known")
struct SignInBootstrapTests {
    private let me = #"{"id":"u-1","name":"lk","email":"lk@example.test"}"#
    private let workspace = #"{"id":"ws-1","name":"crat.ch","slug":"crat-ch"}"#

    @Test("No workspace header is sent while none has been chosen")
    func omitsWorkspaceHeader() async throws {
        let transport = StubTransport()
        transport.routes["GET /api/me"] = { _ in (200, self.me) }
        transport.routes["GET /api/workspaces"] = { _ in (200, #"{"workspaces":[\#(self.workspace)]}"#) }

        let result = try await MulticaAPIClient.signIn(
            serverURL: URL(string: "https://agents.example.test")!,
            token: "mul_test",
            transport: transport
        )
        #expect(result.user.displayName == "lk")
        #expect(result.workspaces.map(\.name) == ["crat.ch"])

        let request = try #require(transport.requests(matching: "GET /api/me").first)
        #expect(request.header("Authorization") == "Bearer mul_test")
        #expect(request.header("X-Workspace-ID") == nil, "no workspace is known yet")
    }

    @Test("A token that may not list workspaces still signs in")
    func workspaceListIsBestEffort() async throws {
        let transport = StubTransport()
        transport.routes["GET /api/me"] = { _ in (200, self.me) }
        transport.routes["GET /api/workspaces"] = { _ in (403, #"{"error":"forbidden"}"#) }

        let result = try await MulticaAPIClient.signIn(
            serverURL: URL(string: "https://agents.example.test")!,
            token: "mul_test",
            transport: transport
        )
        #expect(result.user.id == "u-1")
        #expect(result.workspaces.isEmpty, "the app falls back to asking for the id by hand")
    }

    @Test("A bad token fails sign-in rather than reaching the picker")
    func badTokenFails() async {
        let transport = StubTransport()
        transport.routes["GET /api/me"] = { _ in (401, #"{"error":"invalid token"}"#) }

        await #expect(throws: MulticaError.unauthorized) {
            _ = try await MulticaAPIClient.signIn(
                serverURL: URL(string: "https://agents.example.test")!,
                token: "nope",
                transport: transport
            )
        }
    }

    @Test("Once a workspace is chosen every request carries it")
    func headerReturnsAfterChoice() async throws {
        let transport = StubTransport()
        transport.routes["GET /api/projects"] = { _ in (200, "[]") }
        let client = MulticaAPIClient(
            credentials: MulticaCredentials(
                serverURL: URL(string: "https://agents.example.test")!,
                token: "mul_test",
                workspaceID: "ws-1"
            ),
            transport: transport
        )
        _ = try await client.projects()
        let request = try #require(transport.requests(matching: "GET /api/projects").first)
        #expect(request.header("X-Workspace-ID") == "ws-1")
    }
}
