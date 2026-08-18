import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Reads and writes Multica projects, issues, comments, and agents.
///
/// One instance is bound to one set of ``MulticaCredentials``. Everything is
/// `async`; nothing here touches the main actor, so view models can call it
/// straight from a task.
public actor MulticaAPIClient {
    public let credentials: MulticaCredentials
    private let transport: any HTTPTransport
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    public init(credentials: MulticaCredentials, transport: any HTTPTransport = URLSessionTransport(timeout: 30)) {
        self.credentials = credentials
        self.transport = transport
        self.decoder = MulticaAPIClient.makeDecoder()
        self.encoder = MulticaAPIClient.makeEncoder()
    }

    // MARK: - Identity

    /// Confirms the token works and reports who it belongs to.
    public func currentUser() async throws -> CurrentUser {
        try await get(MulticaRoutes.me)
    }

    public func workspaces() async throws -> [Workspace] {
        try await get(MulticaRoutes.workspaces)
    }

    // MARK: - Projects

    public func projects(status: ProjectStatus? = nil) async throws -> [Project] {
        var query: [URLQueryItem] = []
        if let status { query.append(URLQueryItem(name: "status", value: status.rawValue)) }
        return try await get(MulticaRoutes.projects, query: query)
    }

    public func project(id: String) async throws -> Project {
        try await get(MulticaRoutes.project(id))
    }

    public func createProject(_ draft: ProjectDraft) async throws -> Project {
        try await send(.post, MulticaRoutes.projects, body: draft)
    }

    // MARK: - Issues

    /// One page of issues, newest board order first.
    ///
    /// - Parameter limit: the server defaults to 50; the board asks for more so
    ///   a normal workspace arrives in a single round trip.
    public func issues(
        projectID: String? = nil,
        status: IssueStatus? = nil,
        priority: IssuePriority? = nil,
        assigneeID: String? = nil,
        limit: Int = 100,
        offset: Int = 0,
        sort: IssueSort? = nil,
        direction: SortDirection? = nil
    ) async throws -> IssuePage {
        var query: [URLQueryItem] = [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "offset", value: String(offset)),
        ]
        if let projectID { query.append(URLQueryItem(name: "project_id", value: projectID)) }
        if let status { query.append(URLQueryItem(name: "status", value: status.rawValue)) }
        if let priority { query.append(URLQueryItem(name: "priority", value: priority.rawValue)) }
        if let assigneeID { query.append(URLQueryItem(name: "assignee_id", value: assigneeID)) }
        if let sort { query.append(URLQueryItem(name: "sort", value: sort.rawValue)) }
        if let direction { query.append(URLQueryItem(name: "direction", value: direction.rawValue)) }
        return try await get(MulticaRoutes.issues, query: query)
    }

    /// Walks `offset` until the server stops reporting more, capped so a huge
    /// workspace cannot spin forever.
    public func allIssues(
        projectID: String? = nil,
        pageSize: Int = 100,
        maxPages: Int = 10
    ) async throws -> [Issue] {
        var collected: [Issue] = []
        for page in 0..<maxPages {
            let result = try await issues(
                projectID: projectID,
                limit: pageSize,
                offset: page * pageSize
            )
            collected.append(contentsOf: result.issues)
            if !result.hasMore || result.issues.isEmpty { break }
        }
        return collected
    }

    public func issue(id: String) async throws -> Issue {
        try await get(MulticaRoutes.issue(id))
    }

    public func children(of issueID: String) async throws -> [Issue] {
        try await get(MulticaRoutes.issueChildren(issueID))
    }

    public func searchIssues(_ query: String, limit: Int = 25) async throws -> [Issue] {
        let page: IssuePage = try await get(
            MulticaRoutes.issueSearch,
            query: [
                URLQueryItem(name: "q", value: query),
                URLQueryItem(name: "limit", value: String(limit)),
            ]
        )
        return page.issues
    }

    public func createIssue(_ draft: IssueDraft) async throws -> Issue {
        try await send(.post, MulticaRoutes.issues, body: draft)
    }

    public func updateIssue(id: String, _ change: IssueUpdate) async throws -> Issue {
        try await send(.patch, MulticaRoutes.issue(id), body: change)
    }

    /// Convenience for the single most common write: moving a task's lane.
    public func setStatus(_ status: IssueStatus, on issueID: String) async throws -> Issue {
        try await updateIssue(id: issueID, IssueUpdate(status: status))
    }

    // MARK: - Comments

    /// Comments on an issue. `rootsOnly` + `summary` is the cheap board read;
    /// omitting both returns the full thread.
    public func comments(
        issueID: String,
        rootsOnly: Bool = false,
        summary: Bool = false,
        thread: String? = nil,
        tail: Int? = nil,
        since: Date? = nil
    ) async throws -> [IssueComment] {
        var query: [URLQueryItem] = []
        if rootsOnly { query.append(URLQueryItem(name: "roots_only", value: "true")) }
        if summary { query.append(URLQueryItem(name: "summary", value: "true")) }
        if let thread { query.append(URLQueryItem(name: "thread", value: thread)) }
        if let tail { query.append(URLQueryItem(name: "tail", value: String(tail))) }
        if let since {
            query.append(URLQueryItem(name: "since", value: MulticaAPIClient.timestamp(since)))
        }
        return try await get(MulticaRoutes.issueComments(issueID), query: query)
    }

    @discardableResult
    public func addComment(
        issueID: String,
        content: String,
        parentID: String? = nil
    ) async throws -> IssueComment {
        try await send(
            .post,
            MulticaRoutes.issueComments(issueID),
            body: CommentDraft(content: content, parentID: parentID)
        )
    }

    // MARK: - Agents

    public func agents() async throws -> [Agent] {
        let all: [Agent] = try await get(MulticaRoutes.agents)
        return all.filter { !$0.isArchived }
    }

    // MARK: - Request plumbing

    private enum Method: String {
        case get = "GET"
        case post = "POST"
        case patch = "PATCH"
        case delete = "DELETE"
    }

    private func get<Response: Decodable>(
        _ path: String,
        query: [URLQueryItem] = []
    ) async throws -> Response {
        let request = try makeRequest(.get, path, query: query, body: Optional<Never>.none)
        return try await perform(request, describing: path)
    }

    private func send<Body: Encodable, Response: Decodable>(
        _ method: Method,
        _ path: String,
        body: Body
    ) async throws -> Response {
        let request = try makeRequest(method, path, query: [], body: body)
        return try await perform(request, describing: path)
    }

    private func makeRequest<Body: Encodable>(
        _ method: Method,
        _ path: String,
        query: [URLQueryItem],
        body: Body?
    ) throws -> URLRequest {
        guard var components = URLComponents(
            url: credentials.serverURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        ) else { throw MulticaError.invalidURL }
        if !query.isEmpty { components.queryItems = query }
        guard let url = components.url else { throw MulticaError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.setValue("Bearer \(credentials.token)", forHTTPHeaderField: MulticaRoutes.Header.authorization)
        request.setValue(credentials.workspaceID, forHTTPHeaderField: MulticaRoutes.Header.workspace)
        request.setValue("application/json", forHTTPHeaderField: MulticaRoutes.Header.accept)
        if let body {
            request.setValue("application/json", forHTTPHeaderField: MulticaRoutes.Header.contentType)
            do {
                request.httpBody = try encoder.encode(body)
            } catch {
                throw MulticaError.decoding("Could not encode the request body.")
            }
        }
        return request
    }

    private func perform<Response: Decodable>(
        _ request: URLRequest,
        describing path: String
    ) async throws -> Response {
        let (data, http) = try await transport.send(request)
        switch http.statusCode {
        case 200..<300:
            if Response.self == EmptyResponse.self, let empty = EmptyResponse() as? Response {
                return empty
            }
            do {
                return try decoder.decode(Response.self, from: data)
            } catch {
                throw MulticaError.decoding("\(path): \(error)")
            }
        case 401, 403:
            throw MulticaError.unauthorized
        case 404:
            throw MulticaError.notFound(path)
        default:
            throw MulticaError.server(
                status: http.statusCode,
                message: MulticaAPIClient.errorMessage(from: data)
            )
        }
    }

    /// Pulls the human-readable part out of an error body, whatever shape it took.
    private static func errorMessage(from data: Data) -> String? {
        guard !data.isEmpty else { return nil }
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for key in ["error", "message", "error_message", "detail"] {
                if let text = object[key] as? String, !text.isEmpty { return text }
                if let nested = object[key] as? [String: Any],
                   let text = nested["message"] as? String, !text.isEmpty { return text }
            }
        }
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : String(text.prefix(300))
    }

    /// An endpoint that answers 2xx with no body worth reading.
    public struct EmptyResponse: Decodable, Sendable {
        public init() {}
    }

    // MARK: - Coding

    /// Multica timestamps are RFC 3339; some carry fractional seconds and some
    /// do not, so both are parsed. `ISO8601FormatStyle` is a value type, which
    /// keeps these usable from any isolation domain.
    nonisolated static let rfc3339 = Date.ISO8601FormatStyle(includingFractionalSeconds: false)
    nonisolated static let rfc3339Fractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)

    /// Formats a date the way the API's `since` filters expect it.
    public nonisolated static func timestamp(_ date: Date) -> String {
        rfc3339.format(date)
    }

    /// Shared decoder so tests parse payloads exactly the way the client does.
    public nonisolated static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            if let date = try? rfc3339Fractional.parse(text) { return date }
            if let date = try? rfc3339.parse(text) { return date }
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Not an RFC 3339 date: \(text)")
            )
        }
        return decoder
    }

    public nonisolated static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(timestamp(date))
        }
        return encoder
    }
}

public enum IssueSort: String, Sendable {
    case position
    case title
    case createdAt = "created_at"
    case startDate = "start_date"
    case dueDate = "due_date"
    case priority
}

public enum SortDirection: String, Sendable {
    case ascending = "asc"
    case descending = "desc"
}
