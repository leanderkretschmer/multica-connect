import MulticaKit
import SwiftUI

/// Who is connected, what the app can reach, and the way out.
struct AccountView: View {
    let connection: AppSession.Connection
    let store: WorkspaceStore

    @Environment(AppSession.self) private var session
    @State private var isConfirmingSignOut = false

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

                Section("Agents") {
                    if store.agents.isEmpty {
                        Text("No agents in this workspace.")
                            .foregroundStyle(.secondary)
                    } else {
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
