import Foundation

/// Everything needed to talk to one workspace on one Multica server.
///
/// Nothing here is ever compiled into the binary — the app collects all three
/// values at sign-in and stores the token in the keychain.
public struct MulticaCredentials: Sendable, Hashable {
    public let serverURL: URL
    public let token: String
    public let workspaceID: String

    public init(serverURL: URL, token: String, workspaceID: String) {
        self.serverURL = serverURL
        self.token = token
        self.workspaceID = workspaceID
    }

    /// Trims a user-typed host into a usable base URL, defaulting to HTTPS.
    ///
    /// Returns `nil` for input that cannot address a server, so the sign-in
    /// screen can reject it before a request is ever attempted.
    public static func normalizedServerURL(from input: String) -> URL? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.contains("://") { text = "https://" + text }
        while text.hasSuffix("/") { text.removeLast() }
        guard let url = URL(string: text), let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http", url.host?.isEmpty == false
        else { return nil }
        return url
    }
}
