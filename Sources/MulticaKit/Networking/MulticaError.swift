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
        case .decoding(let detail):
            // The detail is the whole point: a bare "cannot read" leaves nobody
            // — user or developer — anything to act on.
            "The server sent something this version of the app could not read.\n\n\(detail)"
        }
    }

    /// Boils a `DecodingError` down to the field that actually broke.
    ///
    /// `JSONDecoder`'s own description is several lines of nested context; what
    /// is needed to fix a mismatch is the key path, what was expected, and what
    /// arrived.
    public static func describe(_ error: any Error, path: String) -> String {
        guard let decoding = error as? DecodingError else {
            return "\(path): \(error.localizedDescription)"
        }
        switch decoding {
        case .keyNotFound(let key, let context):
            return "\(path): missing field '\(key.stringValue)' at \(keyPath(context))"
        case .typeMismatch(let type, let context):
            return "\(path): field \(keyPath(context)) is not a \(type) — \(context.debugDescription)"
        case .valueNotFound(let type, let context):
            return "\(path): field \(keyPath(context)) was null but a \(type) is required"
        case .dataCorrupted(let context):
            return "\(path): \(keyPath(context)) — \(context.debugDescription)"
        @unknown default:
            return "\(path): \(decoding)"
        }
    }

    /// Renders a coding path the way someone reading JSON would write it.
    private static func keyPath(_ context: DecodingError.Context) -> String {
        let rendered = context.codingPath.map { key in
            key.intValue.map { "[\($0)]" } ?? ".\(key.stringValue)"
        }
        .joined()
        return rendered.isEmpty ? "the response root" : String(rendered.dropFirst(rendered.hasPrefix(".") ? 1 : 0))
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
