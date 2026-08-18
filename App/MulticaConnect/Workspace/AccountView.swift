import MulticaKit
import SwiftUI

/// Who is connected, what the app can reach, and the way out.
struct AccountView: View {
    let connection: AppSession.Connection
    let store: WorkspaceStore

    @Environment(AppSession.self) private var session
    @State private var isConfirmingSignOut = false

    /// Writes straight through to the store, which persists the choice.
    private var handOffBinding: Binding<String> {
        Binding(
            get: { store.preferredAgent?.id ?? "" },
            set: { store.preferredAgentID = $0 }
        )
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Signed in as", value: connection.user.displayName)
                    LabeledContent("Workspace", value: connection.workspaceName)
                    LabeledContent("Server", value: connection.credentials.serverURL.host() ?? "—")
                }

                Section("Workspace") {
                    LabeledContent("Projects", value: "\(store.projects.count)")
                    LabeledContent("Tasks", value: "\(store.issues.count)")
                    LabeledContent("Open", value: "\(store.board.openCount)")
                    if let refreshed = store.lastRefreshed {
                        LabeledContent("Last refreshed") {
                            Text(refreshed, format: .relative(presentation: .named))
                        }
                    }
                }

                Section {
                    if store.agents.isEmpty {
                        Text("No agents in this workspace.")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Hand work to", selection: handOffBinding) {
                            ForEach(store.agents) { agent in
                                Text(agent.name).tag(agent.id)
                            }
                        }
                        ForEach(store.agents) { agent in
                            HStack(spacing: 10) {
                                Text(agent.avatarEmoji ?? "🤖")
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(agent.name)
                                    if let description = agent.description, !description.isEmpty {
                                        Text(description)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }
                                }
                            }
                        }
                    }
                } header: {
                    Text("Agents")
                } footer: {
                    Text("Anything the on-device model can't do during a call is handed to this agent, which answers on an issue.")
                }

                Section {
                    Button("Sign out", role: .destructive) {
                        isConfirmingSignOut = true
                    }
                } footer: {
                    Text("Signing out removes the token from this device's keychain.")
                }
            }
            .navigationTitle("Account")
            .refreshable { await store.refresh() }
            .confirmationDialog(
                "Sign out of \(connection.workspaceName)?",
                isPresented: $isConfirmingSignOut,
                titleVisibility: .visible
            ) {
                Button("Sign out", role: .destructive) { session.signOut() }
                Button("Cancel", role: .cancel) {}
            }
        }
    }
}
