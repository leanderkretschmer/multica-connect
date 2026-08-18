import Foundation
@testable import MulticaKit
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Answers requests from a canned routing table and records what was asked.
final class StubTransport: HTTPTransport, @unchecked Sendable {
    struct Recorded: Sendable {
        let method: String
        let path: String
        let query: [String: String]
        let headers: [String: String]
        let body: Data?

        /// HTTP header names are case-insensitive, and the Linux and Darwin
        /// Foundations disagree on how they capitalise them.
        func header(_ name: String) -> String? {
            headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
        }

        func bodyObject() -> [String: Any] {
            guard let body, let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any]
            else { return [:] }
            return object
        }
    }

    /// `"GET /api/issues"` -> handler. Query strings are not part of the key.
    var routes: [String: @Sendable (Recorded) -> (Int, String)] = [:]
    private(set) var recorded: [Recorded] = []
    private let lock = NSLock()

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        guard let url = request.url,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { throw MulticaError.invalidURL }

        var query: [String: String] = [:]
        for item in components.queryItems ?? [] { query[item.name] = item.value ?? "" }

        let entry = Recorded(
            method: request.httpMethod ?? "GET",
            path: components.path,
            query: query,
            headers: request.allHTTPHeaderFields ?? [:],
            body: request.httpBody
        )
        let handler = lock.withLock { () -> (@Sendable (Recorded) -> (Int, String))? in
            recorded.append(entry)
            return routes["\(entry.method) \(entry.path)"]
        }

        guard let handler else {
            return (Data(), HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil)!)
        }
        let (status, json) = handler(entry)
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
        return (Data(json.utf8), response)
    }

    func requests(matching key: String) -> [Recorded] {
        lock.withLock { recorded.filter { "\($0.method) \($0.path)" == key } }
    }
}

extension MulticaCredentials {
    static let test = MulticaCredentials(
        serverURL: URL(string: "https://agents.example.test")!,
        token: "mat_test_token",
        workspaceID: "ws-1"
    )
}

enum Fixtures {
    static func issue(
        id: String,
        identifier: String = "TEST-1",
        title: String = "A task",
        status: String = "todo",
        priority: String = "none",
        projectID: String? = nil,
        updatedAt: String = "2026-08-18T14:40:57Z"
    ) -> String {
        """
        {
          "id": "\(id)",
          "identifier": "\(identifier)",
          "number": 1,
          "title": "\(title)",
          "description": null,
          "status": "\(status)",
          "status_category": "\(status)",
          "priority": "\(priority)",
          "project_id": \(projectID.map { "\"\($0)\"" } ?? "null"),
          "parent_issue_id": null,
          "assignee_id": null,
          "assignee_type": null,
          "creator_id": "u-1",
          "creator_type": "member",
          "stage": null,
          "position": -1,
          "start_date": null,
          "due_date": null,
          "labels": [],
          "created_at": "2026-08-18T14:40:48Z",
          "updated_at": "\(updatedAt)",
          "workspace_id": "ws-1"
        }
        """
    }

    static func comment(
        id: String,
        issueID: String = "issue-1",
        content: String = "hello",
        authorType: String = "agent",
        parentID: String? = nil,
        createdAt: String = "2026-08-18T15:00:00Z"
    ) -> String {
        """
        {
          "id": "\(id)",
          "issue_id": "\(issueID)",
          "content": "\(content)",
          "content_truncated": false,
          "author_id": "a-1",
          "author_type": "\(authorType)",
          "parent_id": \(parentID.map { "\"\($0)\"" } ?? "null"),
          "reply_count": 0,
          "reactions": [],
          "attachments": [],
          "resolved_at": null,
          "created_at": "\(createdAt)",
          "updated_at": "\(createdAt)",
          "last_activity_at": "\(createdAt)",
          "type": "comment"
        }
        """
    }
}
