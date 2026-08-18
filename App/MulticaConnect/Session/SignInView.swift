import SwiftUI

/// Collects the three things a connection needs. Nothing is prefilled and
/// nothing is shipped in the binary.
struct SignInView: View {
    @Environment(AppSession.self) private var session

    @State private var serverURL = ""
    @State private var token = ""
    @State private var workspaceID = ""
    @FocusState private var focus: Field?

    private enum Field: Hashable {
        case server, token, workspace
    }

    private var canSubmit: Bool {
        !serverURL.trimmingCharacters(in: .whitespaces).isEmpty
            && !token.trimmingCharacters(in: .whitespaces).isEmpty
            && !workspaceID.trimmingCharacters(in: .whitespaces).isEmpty
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
                    SecureField("mat_…", text: $token)
                        .textContentType(.password)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focus, equals: .token)
                        .submitLabel(.next)
                        .onSubmit { focus = .workspace }
                } header: {
                    Text("Access token")
                } footer: {
                    Text("Stored in the keychain on this device only. Create one in Multica under your account settings.")
                }

                Section {
                    TextField("Workspace ID", text: $workspaceID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focus, equals: .workspace)
                        .submitLabel(.go)
                        .onSubmit { submit() }
                } header: {
                    Text("Workspace")
                } footer: {
                    Text("The UUID of the workspace to open.")
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
                                Text("Connecting…")
                            }
                            .frame(maxWidth: .infinity)
                        } else {
                            Text("Connect").frame(maxWidth: .infinity)
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
        Task {
            await session.signIn(serverURL: serverURL, token: token, workspaceID: workspaceID)
        }
    }
}
