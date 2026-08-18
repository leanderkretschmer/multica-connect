import MulticaKit
import SwiftUI

/// One task: what it is, where it sits, and the conversation on it.
struct IssueDetailView: View {
    let issueID: String
    let store: WorkspaceStore

    @State private var comments: [IssueComment] = []
    @State private var isLoadingComments = false
    @State private var commentError: String?
    @State private var newComment = ""
    @State private var isPosting = false
    @State private var moveError: String?

    private var issue: Issue? {
        store.issues.first { $0.id == issueID }
    }

    var body: some View {
        Group {
            if let issue {
                content(for: issue)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(issue?.identifier ?? "Task")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await store.reload(issueID: issueID)
            await loadComments()
        }
    }

    @ViewBuilder
    private func content(for issue: Issue) -> some View {
        List {
            Section {
                Text(issue.title)
                    .font(.title3.weight(.semibold))

                HStack(spacing: 6) {
                    Pill(
                        text: issue.status.displayName,
                        symbolName: issue.lane.symbolName,
                        tint: issue.status.tint
                    )
                    if let symbol = issue.priority.symbolName {
                        Pill(text: issue.priority.displayName, symbolName: symbol, tint: issue.priority.tint)
                    }
                    if let project = store.project(id: issue.projectID) {
                        Pill(text: project.title, symbolName: "folder")
                    }
                }

                if let description = issue.description, !description.isEmpty {
                    Text(description)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            Section("Move to") {
                Picker("Lane", selection: laneBinding(for: issue)) {
                    ForEach(BoardLane.allCases) { lane in
                        Label(lane.title, systemImage: lane.symbolName).tag(lane)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                if let moveError {
                    Text(moveError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

            Section("Conversation") {
                if isLoadingComments && comments.isEmpty {
                    HStack {
                        ProgressView()
                        Text("Loading…").foregroundStyle(.secondary)
                    }
                } else if let commentError {
                    Label(commentError, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.red)
                } else if comments.isEmpty {
                    Text("No comments yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(comments) { comment in
                        CommentRow(comment: comment, store: store)
                    }
                }
            }

            Section {
                TextField("Add a comment", text: $newComment, axis: .vertical)
                    .lineLimit(1...6)
                Button {
                    Task { await post() }
                } label: {
                    if isPosting {
                        HStack { ProgressView(); Text("Posting…") }
                    } else {
                        Text("Post comment")
                    }
                }
                .disabled(newComment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isPosting)
            }
        }
        .refreshable {
            await store.reload(issueID: issueID)
            await loadComments()
        }
    }

    private func laneBinding(for issue: Issue) -> Binding<BoardLane> {
        Binding(
            get: { issue.lane },
            set: { lane in
                guard lane != issue.lane else { return }
                Task {
                    moveError = nil
                    do {
                        _ = try await store.move(issueID: issue.id, to: lane)
                    } catch let error as MulticaError {
                        moveError = error.userMessage
                    } catch {
                        moveError = error.localizedDescription
                    }
                }
            }
        )
    }

    private func loadComments() async {
        isLoadingComments = true
        defer { isLoadingComments = false }
        do {
            comments = try await store.client
                .comments(issueID: issueID)
                .sorted { $0.createdAt < $1.createdAt }
            commentError = nil
        } catch let error as MulticaError {
            commentError = error.userMessage
        } catch {
            commentError = error.localizedDescription
        }
    }

    private func post() async {
        let text = newComment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isPosting = true
        defer { isPosting = false }
        do {
            _ = try await store.client.addComment(issueID: issueID, content: text)
            newComment = ""
            await loadComments()
        } catch let error as MulticaError {
            commentError = error.userMessage
        } catch {
            commentError = error.localizedDescription
        }
    }
}

private struct CommentRow: View {
    let comment: IssueComment
    let store: WorkspaceStore

    private var author: String {
        switch comment.authorType {
        case .agent:
            store.agents.first { $0.id == comment.authorID }?.name ?? "Agent"
        case .squad:
            "Squad"
        case .member, .none:
            "You"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(author)
                    .font(.caption.weight(.semibold))
                Spacer()
                Text(comment.createdAt, format: .relative(presentation: .named))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(comment.content)
                .font(.callout)
                .textSelection(.enabled)
            if comment.contentTruncated {
                Text("Shortened by the server.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
