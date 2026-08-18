import MulticaKit
import SwiftUI

/// The task board: four lanes, everything the workspace has, filterable by
/// project.
struct BoardView: View {
    let store: WorkspaceStore

    @State private var selectedProjectID: String?
    @State private var searchText = ""
    @State private var isComposing = false

    private var board: IssueBoard {
        let base = store.board(forProject: selectedProjectID)
        guard !searchText.isEmpty else { return base }
        let needle = searchText
        let filtered = base.sections.flatMap(\.issues).filter {
            $0.title.localizedCaseInsensitiveContains(needle)
                || $0.identifier.localizedCaseInsensitiveContains(needle)
        }
        return IssueBoard(issues: filtered)
    }

    var body: some View {
        NavigationStack {
            LoadStateView(
                isLoading: store.isLoading,
                error: store.loadError,
                isEmpty: board.totalCount == 0,
                emptyTitle: searchText.isEmpty ? "No tasks yet" : "Nothing matches",
                emptyMessage: searchText.isEmpty
                    ? "Create one here, or start a call and just say what needs doing."
                    : "Try a different word, or clear the search.",
                emptySymbol: searchText.isEmpty ? "checklist" : "magnifyingglass",
                retry: { Task { await store.refresh() } }
            ) {
                List {
                    ForEach(board.sections) { section in
                        if !section.isEmpty {
                            Section {
                                ForEach(section.issues) { issue in
                                    NavigationLink(value: issue) {
                                        IssueRow(issue: issue, project: store.project(id: issue.projectID))
                                    }
                                }
                            } header: {
                                LaneHeader(lane: section.lane, count: section.count)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
            .navigationTitle("Tasks")
            .navigationDestination(for: Issue.self) { issue in
                IssueDetailView(issueID: issue.id, store: store)
            }
            .searchable(text: $searchText, prompt: "Search tasks")
            .refreshable { await store.refresh() }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    ProjectFilterMenu(store: store, selection: $selectedProjectID)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isComposing = true
                    } label: {
                        Label("New task", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $isComposing) {
                ComposeIssueView(store: store, initialProjectID: selectedProjectID)
            }
        }
    }
}

private struct LaneHeader: View {
    let lane: BoardLane
    let count: Int

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: lane.symbolName)
            Text(lane.title)
            Spacer()
            Text("\(count)")
                .monospacedDigit()
        }
        .foregroundStyle(lane.tint)
        .font(.footnote.weight(.semibold))
        .textCase(nil)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(lane.title), \(count) tasks")
    }
}

private struct ProjectFilterMenu: View {
    let store: WorkspaceStore
    @Binding var selection: String?

    var body: some View {
        Menu {
            Picker("Project", selection: $selection) {
                Text("All projects").tag(String?.none)
                ForEach(store.projects) { project in
                    Text(project.icon.map { "\($0)  \(project.title)" } ?? project.title)
                        .tag(String?.some(project.id))
                }
            }
        } label: {
            Label(
                store.project(id: selection)?.title ?? "All projects",
                systemImage: selection == nil ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill"
            )
        }
    }
}

/// One task in a list.
struct IssueRow: View {
    let issue: Issue
    let project: Project?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(issue.title)
                .font(.body)
                .lineLimit(2)

            HStack(spacing: 6) {
                Text(issue.identifier)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)

                if issue.needsAttention {
                    Pill(text: "Blocked", symbolName: "exclamationmark.octagon", tint: .red)
                }
                if let symbol = issue.priority.symbolName {
                    Pill(text: issue.priority.displayName, symbolName: symbol, tint: issue.priority.tint)
                }
                if let project {
                    Pill(text: project.title, symbolName: "folder", tint: .secondary)
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}
