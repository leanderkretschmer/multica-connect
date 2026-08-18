import Foundation
import MulticaKit

/// The workspace operations the voice assistant can perform, each returning a
/// sentence that is already fit to be spoken.
///
/// Keeping them here rather than inside the tool types means the behaviour is
/// plain main-actor code — testable, and free of any Foundation Models
/// isolation questions. The tools are one `await` each.
extension WorkspaceStore {
    /// Reads the board, optionally narrowed to one lane and one project.
    func describeTasks(lane laneName: String?, project projectName: String?) -> String {
        var project: Project?
        if let projectName, !projectName.isEmpty {
            guard let match = findProject(named: projectName) else {
                return unknownProjectMessage(projectName)
            }
            project = match
        }
        let scoped = board(forProject: project?.id)
        let scope = project.map { " in \($0.title)" } ?? ""

        guard let laneName, !laneName.isEmpty else {
            return "Tasks\(scope):\n" + scoped.digest(projectsByID: projectsByID)
        }
        guard let lane = BoardLane(spoken: laneName) else {
            return unknownLaneMessage(laneName)
        }
        let tasks = scoped[lane]
        guard !tasks.isEmpty else {
            return "Nothing is \(lane.title.lowercased())\(scope)."
        }
        let lines = tasks.prefix(10).map { issue in
            "\(issue.identifier): \(issue.title)\(issue.needsAttention ? " (blocked)" : "")"
        }
        let more = tasks.count > 10 ? "\n…and \(tasks.count - 10) more" : ""
        return "\(lane.title)\(scope) (\(tasks.count)):\n" + lines.joined(separator: "\n") + more
    }

    func describeProjects() -> String {
        guard !projects.isEmpty else { return "There are no projects yet." }
        return projects.map { project in
            let progress = project.completion.map { " — \(Int($0 * 100))% done" } ?? ""
            return "\(project.title) (\(project.issueCount) tasks\(progress))"
        }
        .joined(separator: "\n")
    }

    /// Creates a task, resolving the project by name first.
    func createTask(
        title rawTitle: String,
        notes: String?,
        project projectName: String?,
        lane laneName: String?,
        priority priorityName: String?
    ) async -> String {
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return "A task needs a title. Ask what it should be called." }

        var project: Project?
        if let projectName, !projectName.isEmpty {
            guard let match = findProject(named: projectName) else {
                return unknownProjectMessage(projectName) + " Ask which one to use, or create it first."
            }
            project = match
        }

        let lane = laneName.flatMap { BoardLane(spoken: $0) } ?? .planned
        let priority = priorityName.flatMap { IssuePriority(spoken: $0) }

        do {
            let issue = try await createIssue(
                IssueDraft(
                    title: title,
                    description: notes,
                    projectID: project?.id,
                    status: lane.canonicalStatus,
                    priority: priority
                )
            )
            let scope = project.map { " in \($0.title)" } ?? ""
            return "Created \(issue.identifier): \(issue.title)\(scope), filed as \(lane.title.lowercased())."
        } catch let error as MulticaError {
            return "The task was not created. \(error.userMessage)"
        } catch {
            return "The task was not created. \(error.localizedDescription)"
        }
    }

    /// Moves a task between lanes, resolving it by identifier or title.
    func moveTask(matching text: String, toLane laneName: String) async -> String {
        guard let issue = findIssue(matching: text) else {
            return "No task matches \(text). Ask which one they mean."
        }
        guard let lane = BoardLane(spoken: laneName) else {
            return unknownLaneMessage(laneName)
        }
        guard issue.lane != lane else {
            return "\(issue.identifier) is already \(lane.title.lowercased())."
        }
        do {
            let updated = try await move(issueID: issue.id, to: lane)
            return "Moved \(updated.identifier) to \(lane.title.lowercased())."
        } catch let error as MulticaError {
            return "\(issue.identifier) was not moved. \(error.userMessage)"
        } catch {
            return "\(issue.identifier) was not moved. \(error.localizedDescription)"
        }
    }

    func createProjectNamed(_ rawTitle: String, summary: String?, icon: String?) async -> String {
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return "A project needs a name." }
        if let existing = findProject(named: title) {
            return "\(existing.title) already exists — use that one."
        }
        do {
            let project = try await createProject(
                ProjectDraft(
                    title: title,
                    description: summary,
                    // Keep only a real single-character emoji; the model
                    // sometimes offers a word here.
                    icon: icon.flatMap { $0.count == 1 ? $0 : nil }
                )
            )
            return "Created the project \(project.title)."
        } catch let error as MulticaError {
            return "The project was not created. \(error.userMessage)"
        } catch {
            return "The project was not created. \(error.localizedDescription)"
        }
    }

    private func unknownProjectMessage(_ requested: String) -> String {
        guard !projects.isEmpty else { return "There is no project called \(requested), and none exist yet." }
        return "There is no project called \(requested). Projects: \(projects.map(\.title).joined(separator: ", "))."
    }

    private func unknownLaneMessage(_ requested: String) -> String {
        "Unknown lane \(requested). Use planned, ongoing, staged, or finished."
    }
}
