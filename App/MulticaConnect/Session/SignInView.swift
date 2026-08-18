import SwiftUI

/// Step one of signing in: which server, and which token.
///
/// Nothing is prefilled and nothing is shipped in the binary. The workspace is
/// not asked for here — the server is asked instead, on the next screen.
struct SignInView: View {
    @Environment(AppSession.self) private var session

    @State private var serverURL = ""
    @State private var token = ""
    @FocusState private var focus: Field?

    private enum Field: Hashable {
        case server, token
    }

    private var canSubmit: Bool {
        !serverURL.trimmingCharacters(in: .whitespaces).isEmpty
            && !token.trimmingCharacters(in: .whitespaces).isEmpty
            && !session.isSigningIn
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("agents.example.com", text: $serverURL)
                        .textContentType(.URL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focus, equals: .server)
                        .submitLabel(.next)
                        .onSubmit { focus = .token }
                } header: {
                    Text("Server")
                } footer: {
                    Text("The Multica server this workspace lives on.")
                }

                Section {
                    SecureField("mul_…", text: $token)
                        .textContentType(.password)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focus, equals: .token)
                        .submitLabel(.go)
                        .onSubmit { submit() }
                } header: {
                    Text("Access token")
                } footer: {
                    Text("Create one in Multica under your account settings. It is kept in the keychain on this device only.")
                }

                if let error = session.signInError {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                            .font(.callout)
                    }
                }

                Section {
                    Button(action: submit) {
                        if session.isSigningIn {
                            HStack(spacing: 8) {
                                ProgressView()
                                Text("Checking…")
                            }
                            .frame(maxWidth: .infinity)
                        } else {
                            Text("Continue").frame(maxWidth: .infinity)
                        }
                    }
                    .disabled(!canSubmit)
                }
            }
            .navigationTitle("Multica Connect")
            .safeAreaInset(edge: .top) {
                VStack(spacing: 6) {
                    Image(systemName: "waveform.circle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.tint)
                    Text("Talk to your workspace.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(.bar)
            }
        }
    }

    private func submit() {
        guard canSubmit else { return }
        focus = nil
        Task { await session.signIn(serverURL: serverURL, token: token) }
    }
}

/// Step two: which of the token's workspaces to open.
///
/// Falls back to typing an id only when the server would not list them, which
/// happens for a token scoped to a single workspace.
struct WorkspacePickerView: View {
    let choice: AppSession.WorkspaceChoice

    @Environment(AppSession.self) private var session
    @State private var manualID = ""

    var body: some View {
        NavigationStack {
            Form {
                if choice.needsManualEntry {
                    Section {
                        TextField("Workspace ID", text: $manualID)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.go)
                            .onSubmit { Task { await session.selectWorkspace(id: manualID) } }
                    } header: {
                        Text("Workspace")
                    } footer: {
                        Text("This server did not list the workspaces for your token, so the ID has to be entered by hand. You can copy it from the workspace URL in Multica.")
                    }

                    Section {
                        Button("Open workspace") {
                            Task { await session.selectWorkspace(id: manualID) }
                        }
                        .disabled(manualID.trimmingCharacters(in: .whitespaces).isEmpty || session.isSigningIn)
                    }
                } else {
                    Section {
                        ForEach(choice.workspaces) { workspace in
                            Button {
                                Task { await session.selectWorkspace(workspace) }
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(workspace.name)
                                            .foregroundStyle(.primary)
                                        if let slug = workspace.slug, !slug.isEmpty {
                                            Text(slug)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                            .disabled(session.isSigningIn)
                        }
                    } header: {
                        Text("Workspace")
                    } footer: {
                        Text("Signed in as \(choice.user.displayName).")
                    }
                }

                if let error = session.signInError {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                            .font(.callout)
                    }
                }
            }
            .navigationTitle("Choose a workspace")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Back") { session.cancelWorkspaceChoice() }
                }
            }
            .overlay {
                if session.isSigningIn {
                    ProgressView().controlSize(.large)
                }
            }
        }
    }
}
