import MulticaKit
import SwiftUI

struct ProjectsView: View {
    let store: WorkspaceStore

    @State private var isComposing = false

    var body: some View {
        NavigationStack {
            LoadStateView(
                isLoading: store.isLoading,
                error: store.loadError,
                isEmpty: store.projects.isEmpty,
                emptyTitle: "No projects yet",
                emptyMessage: "Projects group tasks around one outcome. Create one here, or ask for it during a call.",
                emptySymbol: "folder",
                retry: { Task { await store.refresh() } }
            ) {
                List {
                    ForEach(store.projects) { project in
                        NavigationLink(value: project) {
                            ProjectRow(project: project)
                        }
                    }
                }
            }
            .navigationTitle("Projects")
            .navigationDestination(for: Project.self) { project in
                ProjectDetailView(projectID: project.id, store: store)
            }
            .refreshable { await store.refresh() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { isComposing = true } label: {
                        Label("New project", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $isComposing) {
                ComposeProjectView(store: store)
            }
        }
    }
}

private struct ProjectRow: View {
    let project: Project

    var body: some View {
        HStack(spacing: 12) {
            Text(project.icon ?? "📁")
                .font(.title2)
                .frame(width: 36)

            VStack(alignment: .leading, spacing: 4) {
                Text(project.title)
                    .font(.body)
                HStack(spacing: 6) {
                    Pill(text: project.status.displayName, tint: .secondary)
                    Text("\(project.doneCount)/\(project.issueCount) done")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                if let completion = project.completion {
                    ProgressView(value: completion)
                        .tint(.accentColor)
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

/// A project's own board, so "what's ongoing in Connect?" has a screen too.
struct ProjectDetailView: View {
    let projectID: String
    let store: WorkspaceStore

    @State private var isComposing = false

    private var project: Project? { store.project(id: projectID) }

    var body: some View {
        let board = store.board(forProject: projectID)

        List {
            if let description = project?.description, !description.isEmpty {
                Section {
                    Text(description)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            if board.totalCount == 0 {
                Section {
                    ContentUnavailableView(
                        "No tasks in this project",
                        systemImage: "checklist",
                        description: Text("Add the first one, or say it during a call.")
                    )
                }
            } else {
                ForEach(board.sections) { section in
                    if !section.isEmpty {
                        Section {
                            ForEach(section.issues) { issue in
                                NavigationLink(value: issue) {
                                    IssueRow(issue: issue, project: nil)
                                }
                            }
                        } header: {
                            HStack {
                                Image(systemName: section.lane.symbolName)
                                Text(section.lane.title)
                                Spacer()
                                Text("\(section.count)").monospacedDigit()
                            }
                            .foregroundStyle(section.lane.tint)
                            .font(.footnote.weight(.semibold))
                            .textCase(nil)
                        }
                    }
                }
            }
        }
        .navigationTitle(project?.title ?? "Project")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: Issue.self) { issue in
            IssueDetailView(issueID: issue.id, store: store)
        }
        .refreshable { await store.refresh() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { isComposing = true } label: {
                    Label("New task", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $isComposing) {
            ComposeIssueView(store: store, initialProjectID: projectID)
        }
    }
}
