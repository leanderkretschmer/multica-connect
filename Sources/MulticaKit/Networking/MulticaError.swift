import Foundation

/// Every way a Multica call can fail, in terms the UI can act on.
public enum MulticaError: Error, Sendable, Equatable {
    /// The server URL could not be composed into a request.
    case invalidURL
    /// 401/403 — the token is missing, wrong, or lacks access.
    case unauthorized
    /// 404 on a resource the caller named.
    case notFound(String)
    /// Any other non-2xx, carrying the server's message when it sent one.
    case server(status: Int, message: String?)
    /// The transport failed before a response arrived.
    case transport(String)
    /// A 2xx body that did not match the expected shape.
    case decoding(String)

    /// Short sentence to put in front of a person.
    public var userMessage: String {
        switch self {
        case .invalidURL:
            "That server address could not be used."
        case .unauthorized:
            "This token is not accepted by the server. Sign in again."
        case .notFound(let what):
            "\(what) no longer exists on the server."
        case .server(let status, let message):
            message.map { "Server error \(status): \($0)" } ?? "The server returned an error (\(status))."
        case .transport(let detail):
            "Could not reach the server. \(detail)"
        case .decoding:
            "The server sent a response this version of the app cannot read."
        }
    }

    /// Whether retrying the same call could plausibly succeed.
    public var isRetryable: Bool {
        switch self {
        case .transport: true
        case .server(let status, _): status >= 500 || status == 429
        default: false
        }
    }
}
