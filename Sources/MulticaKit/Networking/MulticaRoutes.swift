import Foundation

/// Every path and header name the app sends to a Multica server, in one place.
///
/// The contract is the one the official `multica` CLI speaks: `Authorization:
/// Bearer <token>` plus an `X-Workspace-ID` header for workspace scoping, and
/// REST resources under `/api`. Keeping the strings here means a server-side
/// rename is a one-file change instead of a hunt through call sites.
public enum MulticaRoutes {
    public static let me = "/api/me"
    public static let workspaces = "/api/workspaces"
    public static let projects = "/api/projects"
    public static let issues = "/api/issues"
    public static let issueSearch = "/api/issues/search"
    public static let agents = "/api/agents"

    public static func project(_ id: String) -> String { "\(projects)/\(id)" }
    public static func issue(_ id: String) -> String { "\(issues)/\(id)" }
    public static func issueChildren(_ id: String) -> String { "\(issue(id))/children" }
    public static func issueComments(_ id: String) -> String { "\(issue(id))/comments" }
    public static func issueMetadata(_ id: String) -> String { "\(issue(id))/metadata" }

    public enum Header {
        public static let authorization = "Authorization"
        public static let workspace = "X-Workspace-ID"
        public static let contentType = "Content-Type"
        public static let accept = "Accept"
        /// Paging cursors the comment endpoints return.
        public static let nextBefore = "X-Multica-Next-Before"
        public static let nextBeforeID = "X-Multica-Next-Before-Id"
        /// Set by the server when a failed call is worth retrying.
        public static let retryable = "X-Multica-Retryable"
    }
}
