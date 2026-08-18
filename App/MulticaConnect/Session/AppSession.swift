import Foundation
import MulticaKit
import Observation

/// Who is signed in, and the client everything else talks through.
///
/// The app has exactly three states: nobody signed in, a sign-in being checked,
/// and a live connection. Views switch on ``state`` rather than juggling
/// separate flags.
@MainActor
@Observable
final class AppSession {
    enum State {
        case signedOut
        case restoring
        case signedIn(Connection)

        var connection: Connection? {
            if case .signedIn(let connection) = self { return connection }
            return nil
        }
    }

    /// A verified connection plus everything built on top of it.
    struct Connection {
        let credentials: MulticaCredentials
        let client: MulticaAPIClient
        let user: CurrentUser
        let workspaceName: String
    }

    private(set) var state: State = .restoring
    /// Set when a sign-in attempt failed, cleared when the next one starts.
    private(set) var signInError: String?
    private(set) var isSigningIn = false

    private let store: KeychainTokenStore

    init(store: KeychainTokenStore = KeychainTokenStore()) {
        self.store = store
    }

    /// Brings back the stored connection at launch, if the token still works.
    func restore() async {
        guard case .restoring = state else { return }
        guard let stored = store.load() else {
            state = .signedOut
            return
        }
        do {
            state = .signedIn(try await verify(stored))
        } catch {
            // A revoked token should not trap someone on a spinner — drop it
            // and show the sign-in screen.
            store.clear()
            state = .signedOut
            if case MulticaError.unauthorized = error {
                signInError = "The stored token is no longer valid. Sign in again."
            }
        }
    }

    /// Verifies a typed-in connection and, if it works, keeps it.
    func signIn(serverURL: String, token: String, workspaceID: String) async {
        signInError = nil
        guard let url = MulticaCredentials.normalizedServerURL(from: serverURL) else {
            signInError = "That does not look like a server address."
            return
        }
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedWorkspace = workspaceID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedToken.isEmpty else {
            signInError = "An access token is required."
            return
        }
        guard !trimmedWorkspace.isEmpty else {
            signInError = "A workspace ID is required."
            return
        }

        isSigningIn = true
        defer { isSigningIn = false }

        let connection = MulticaConnection(
            serverURL: url,
            token: trimmedToken,
            workspaceID: trimmedWorkspace
        )
        do {
            let verified = try await verify(connection)
            try store.save(connection)
            state = .signedIn(verified)
        } catch let error as MulticaError {
            signInError = error.userMessage
        } catch {
            signInError = error.localizedDescription
        }
    }

    func signOut() {
        store.clear()
        state = .signedOut
        signInError = nil
    }

    /// Calls `/api/me` to prove the token works before anything is stored.
    private func verify(_ connection: MulticaConnection) async throws -> Connection {
        let credentials = MulticaCredentials(
            serverURL: connection.serverURL,
            token: connection.token,
            workspaceID: connection.workspaceID
        )
        let client = MulticaAPIClient(credentials: credentials)
        let user = try await client.currentUser()
        // The workspace name is a nicety; a server that hides the list should
        // not block sign-in.
        let name = (try? await client.workspaces())?
            .first { $0.id == connection.workspaceID }?
            .name
        return Connection(
            credentials: credentials,
            client: client,
            user: user,
            workspaceName: name ?? "Workspace"
        )
    }
}
