import Foundation
import MulticaKit
import Observation

/// Who is signed in, and the client everything else talks through.
///
/// Signing in has two steps, because a workspace id is not something anyone
/// should have to type: server plus token first, then pick a workspace from what
/// the token can actually reach.
@MainActor
@Observable
final class AppSession {
    enum State {
        case signedOut
        case restoring
        /// Token verified; waiting for someone to say which workspace.
        case choosingWorkspace(WorkspaceChoice)
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

    /// What the picker needs: the verified token and the choices for it.
    struct WorkspaceChoice {
        let serverURL: URL
        let token: String
        let user: CurrentUser
        let workspaces: [Workspace]

        /// `true` when the server would not list them, so the id has to be typed.
        var needsManualEntry: Bool { workspaces.isEmpty }
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

    // MARK: - Step one: server and token

    /// Verifies the token, then either goes straight in or asks which workspace.
    func signIn(serverURL: String, token: String) async {
        signInError = nil
        guard let url = MulticaCredentials.normalizedServerURL(from: serverURL) else {
            signInError = "That does not look like a server address."
            return
        }
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedToken.isEmpty else {
            signInError = "An access token is required."
            return
        }

        isSigningIn = true
        defer { isSigningIn = false }

        do {
            let result = try await MulticaAPIClient.signIn(serverURL: url, token: trimmedToken)
            let choice = WorkspaceChoice(
                serverURL: url,
                token: trimmedToken,
                user: result.user,
                workspaces: result.workspaces
            )
            // One workspace is not a choice worth showing.
            if result.workspaces.count == 1, let only = result.workspaces.first {
                await finish(choice: choice, workspaceID: only.id, workspaceName: only.name)
            } else {
                state = .choosingWorkspace(choice)
            }
        } catch let error as MulticaError {
            signInError = error.userMessage
        } catch {
            signInError = error.localizedDescription
        }
    }

    // MARK: - Step two: the workspace

    func selectWorkspace(_ workspace: Workspace) async {
        guard case .choosingWorkspace(let choice) = state else { return }
        await finish(choice: choice, workspaceID: workspace.id, workspaceName: workspace.name)
    }

    /// Used when the server would not list workspaces and the id was typed.
    func selectWorkspace(id: String) async {
        guard case .choosingWorkspace(let choice) = state else { return }
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            signInError = "A workspace ID is required."
            return
        }
        await finish(choice: choice, workspaceID: trimmed, workspaceName: "Workspace")
    }

    /// Back to step one, keeping nothing.
    func cancelWorkspaceChoice() {
        state = .signedOut
        signInError = nil
    }

    private func finish(choice: WorkspaceChoice, workspaceID: String, workspaceName: String) async {
        signInError = nil
        isSigningIn = true
        defer { isSigningIn = false }

        let connection = MulticaConnection(
            serverURL: choice.serverURL,
            token: choice.token,
            workspaceID: workspaceID
        )
        do {
            let verified = try await verify(connection, fallbackName: workspaceName)
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
    private func verify(
        _ connection: MulticaConnection,
        fallbackName: String = "Workspace"
    ) async throws -> Connection {
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
            workspaceName: name ?? fallbackName
        )
    }
}
