import Foundation
import Security

/// Keeps the Multica access token in the keychain and the rest of the
/// connection in user defaults.
///
/// The token never touches `UserDefaults`, never appears in a log line, and is
/// not compiled into the binary — it arrives when someone signs in.
///
/// Deliberately not `Sendable`: `UserDefaults` is not, and this store is only
/// ever reached from ``AppSession``, which is main-actor isolated. Leaving the
/// conformance off means the compiler says so if that ever stops being true,
/// rather than a `nonisolated(unsafe)` quietly waving the check through.
struct KeychainTokenStore {
    private let service: String
    private let account = "multica-access-token"
    private let defaults: UserDefaults

    private enum DefaultsKey {
        static let serverURL = "connection.serverURL"
        static let workspaceID = "connection.workspaceID"
    }

    init(service: String = "stream.multica.connect", defaults: UserDefaults = .standard) {
        self.service = service
        self.defaults = defaults
    }

    /// The stored connection, or `nil` when no one has signed in on this device.
    func load() -> MulticaConnection? {
        guard let urlString = defaults.string(forKey: DefaultsKey.serverURL),
              let url = URL(string: urlString),
              let workspaceID = defaults.string(forKey: DefaultsKey.workspaceID),
              let token = readToken()
        else { return nil }
        return MulticaConnection(serverURL: url, token: token, workspaceID: workspaceID)
    }

    func save(_ connection: MulticaConnection) throws {
        try writeToken(connection.token)
        defaults.set(connection.serverURL.absoluteString, forKey: DefaultsKey.serverURL)
        defaults.set(connection.workspaceID, forKey: DefaultsKey.workspaceID)
    }

    func clear() {
        SecItemDelete(baseQuery() as CFDictionary)
        defaults.removeObject(forKey: DefaultsKey.serverURL)
        defaults.removeObject(forKey: DefaultsKey.workspaceID)
    }

    // MARK: - Keychain

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private func readToken() -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func writeToken(_ token: String) throws {
        let data = Data(token.utf8)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            // The token is only useful while the device is unlocked, and it must
            // not travel to a restored backup on another device.
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]

        let status = SecItemUpdate(baseQuery() as CFDictionary, attributes as CFDictionary)
        switch status {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var insert = baseQuery()
            insert.merge(attributes) { _, new in new }
            let addStatus = SecItemAdd(insert as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError(status: addStatus) }
        default:
            throw KeychainError(status: status)
        }
    }
}

struct KeychainError: LocalizedError {
    let status: OSStatus

    var errorDescription: String? {
        let detail = SecCopyErrorMessageString(status, nil) as String? ?? "code \(status)"
        return "The keychain refused to store the token (\(detail))."
    }
}

/// A connection to one workspace on one server, as the app stores it.
struct MulticaConnection: Sendable, Hashable {
    var serverURL: URL
    var token: String
    var workspaceID: String
}
