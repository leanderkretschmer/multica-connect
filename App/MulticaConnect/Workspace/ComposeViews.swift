import MulticaKit
import SwiftUI

/// Creates a task by hand — the counterpart to saying it during a call.
struct ComposeIssueView: View {
    let store: WorkspaceStore
    var initialProjectID: String?

    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var notes = ""
    @State private var projectID: String?
    @State private var lane: BoardLane = .planned
    @State private var priority: IssuePriority = .none
    @State private var isSaving = false
    @State private var error: String?

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSaving
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Task") {
                    TextField("What needs doing?", text: $title, axis: .vertical)
                        .lineLimit(1...3)
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3...10)
                }

                Section {
                    Picker("Project", selection: $projectID) {
                        Text("None").tag(String?.none)
                        ForEach(store.projects) { project in
                            Text(project.title).tag(String?.some(project.id))
                        }
                    }
                    Picker("Lane", selection: $lane) {
                        ForEach(BoardLane.allCases) { lane in
                            Text(lane.title).tag(lane)
                        }
                    }
                    Picker("Priority", selection: $priority) {
                        ForEach(IssuePriority.allCases, id: \.self) { priority in
                            Text(priority.displayName).tag(priority)
                        }
                    }
                }

                if let error {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                            .font(.callout)
                    }
                }
            }
            .navigationTitle("New task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { Task { await save() } }
                        .disabled(!canSave)
                }
            }
            .overlay {
                if isSaving {
                    ProgressView().controlSize(.large)
                }
            }
            .onAppear { projectID = initialProjectID }
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            _ = try await store.createIssue(
                IssueDraft(
                    title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                    description: notes.isEmpty ? nil : notes,
                    projectID: projectID,
                    status: lane.canonicalStatus,
                    priority: priority == .none ? nil : priority
                )
            )
            dismiss()
        } catch let error as MulticaError {
            self.error = error.userMessage
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct ComposeProjectView: View {
    let store: WorkspaceStore

    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var summary = ""
    @State private var icon = ""
    @State private var isSaving = false
    @State private var error: String?

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSaving
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Project") {
                    TextField("Name", text: $title)
                    TextField("What is it for?", text: $summary, axis: .vertical)
                        .lineLimit(2...6)
                    TextField("Icon (one emoji)", text: $icon)
                        .onChange(of: icon) { _, new in
                            // One character keeps the row from breaking its layout.
                            if new.count > 1 { icon = String(new.suffix(1)) }
                        }
                }

                if let error {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                            .font(.callout)
                    }
                }
            }
            .navigationTitle("New project")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { Task { await save() } }
                        .disabled(!canSave)
                }
            }
            .overlay {
                if isSaving {
                    ProgressView().controlSize(.large)
                }
            }
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        do {
            _ = try await store.createProject(
                ProjectDraft(
                    title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                    description: summary.isEmpty ? nil : summary,
                    icon: icon.isEmpty ? nil : icon
                )
            )
            dismiss()
        } catch let error as MulticaError {
            self.error = error.userMessage
        } catch {
            self.error = error.localizedDescription
        }
    }
}
