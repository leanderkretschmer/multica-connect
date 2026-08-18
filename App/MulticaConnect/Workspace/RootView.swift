import SwiftUI

/// Chooses between sign-in and the workspace, and owns the store once there is
/// a connection to build it from.
struct RootView: View {
    @Environment(AppSession.self) private var session

    var body: some View {
        switch session.state {
        case .restoring:
            ProgressView()
                .controlSize(.large)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .signedOut:
            SignInView()
        case .choosingWorkspace(let choice):
            WorkspacePickerView(choice: choice)
        case .signedIn(let connection):
            // Keyed on the workspace so switching accounts rebuilds the store
            // rather than showing the previous workspace's tasks.
            WorkspaceTabs(connection: connection)
                .id(connection.credentials.workspaceID)
        }
    }
}

private struct WorkspaceTabs: View {
    let connection: AppSession.Connection

    @State private var store: WorkspaceStore
    @State private var call: VoiceCallModel

    init(connection: AppSession.Connection) {
        self.connection = connection
        let store = WorkspaceStore(client: connection.client)
        _store = State(initialValue: store)
        _call = State(initialValue: VoiceCallModel(store: store))
    }

    var body: some View {
        TabView {
            Tab("Call", systemImage: "waveform") {
                VoiceCallView(call: call, store: store)
            }
            Tab("Tasks", systemImage: "checklist") {
                BoardView(store: store)
            }
            Tab("Projects", systemImage: "folder") {
                ProjectsView(store: store)
            }
            Tab("Account", systemImage: "person.crop.circle") {
                AccountView(connection: connection, store: store)
            }
        }
        .environment(store)
        .task { await store.refresh() }
    }
}
