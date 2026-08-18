import Foundation
import MulticaKit
import Observation

/// Everything the app knows about the workspace, and the only place that
/// changes it.
///
/// Both the board UI and the voice assistant's tools go through this object, so
/// a task created by speaking shows up on the board without a manual refresh.
@MainActor
@Observable
final class WorkspaceStore {
    private(set) var issues: [Issue] = []
    private(set) var projects: [Project] = []
    private(set) var agents: [Agent] = []

    private(set) var isLoading = false
    private(set) var loadError: String?
    private(set) var lastRefreshed: Date?

    let client: MulticaAPIClient

    init(client: MulticaAPIClient) {
        self.client = client
    }

    // MARK: - Derived state

    var board: IssueBoard { IssueBoard(issues: issues) }

    var projectsByID: [String: Project] {
        Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0) })
    }

    func project(id: String?) -> Project? {
        guard let id else { return nil }
        return projectsByID[id]
    }

    func issues(inProject projectID: String) -> [Issue] {
        issues.filter { $0.projectID == projectID }
    }

    func board(forProject projectID: String?) -> IssueBoard {
        guard let projectID else { return board }
        return IssueBoard(issues: issues(inProject: projectID))
    }

    /// A short plain-text summary of the workspace for the on-device model.
    func digest(projectID: String? = nil) -> String {
        board(forProject: projectID).digest(projectsByID: projectsByID)
    }

    // MARK: - Loading

    /// Pulls projects, issues, and agents together. Keeps whatever is already
    /// on screen if the refresh fails, so a dropped connection does not blank
    /// the board.
    func refresh() async {
        isLoading = true
        defer { isLoading = false }

        do {
            async let projectsTask = client.projects()
            async let issuesTask = client.allIssues()
            async let agentsTask = client.agents()

            let (projects, issues, agents) = try await (projectsTask, issuesTask, agentsTask)
            self.projects = projects.sorted { $0.title.localizedCompare($1.title) == .orderedAscending }
            self.issues = issues
            self.agents = agents.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
            self.loadError = nil
            self.lastRefreshed = Date()
        } catch let error as MulticaError {
            loadError = error.userMessage
        } catch {
            loadError = error.localizedDescription
        }
    }

    /// Re-reads one issue after it changes elsewhere (a detail screen, a voice
    /// command, an agent run).
    func reload(issueID: String) async {
        guard let fresh = try? await client.issue(id: issueID) else { return }
        merge(fresh)
    }

    // MARK: - Writes

    @discardableResult
    func createIssue(_ draft: IssueDraft) async throws -> Issue {
        let issue = try await client.createIssue(draft)
        merge(issue)
        bumpProjectCount(for: issue.projectID)
        return issue
    }

    @discardableResult
    func update(issueID: String, _ change: IssueUpdate) async throws -> Issue {
        guard !change.isEmpty else {
            guard let existing = issues.first(where: { $0.id == issueID }) else {
                return try await client.issue(id: issueID)
            }
            return existing
        }
        let issue = try await client.updateIssue(id: issueID, change)
        merge(issue)
        return issue
    }

    @discardableResult
    func move(issueID: String, to lane: BoardLane) async throws -> Issue {
        try await update(issueID: issueID, IssueUpdate(status: lane.canonicalStatus))
    }

    @discardableResult
    func createProject(_ draft: ProjectDraft) async throws -> Project {
        let project = try await client.createProject(draft)
        projects.append(project)
        projects.sort { $0.title.localizedCompare($1.title) == .orderedAscending }
        return project
    }

    // MARK: - Lookup used by the voice tools

    // The resolution rules live in MulticaKit so they can be tested against
    // the awkward inputs speech produces.

    func findProject(named name: String) -> Project? {
        WorkspaceLookup.project(named: name, in: projects)
    }

    func findIssue(matching text: String) -> Issue? {
        WorkspaceLookup.issue(matching: text, in: issues)
    }

    func agent(named name: String) -> Agent? {
        WorkspaceLookup.agent(named: name, in: agents)
    }

    // MARK: - Local cache maintenance

    private func merge(_ issue: Issue) {
        if let index = issues.firstIndex(where: { $0.id == issue.id }) {
            issues[index] = issue
        } else {
            issues.append(issue)
        }
    }

    /// Keeps the project card's counts honest until the next full refresh.
    private func bumpProjectCount(for projectID: String?) {
        guard let projectID, let index = projects.firstIndex(where: { $0.id == projectID }) else { return }
        let current = projects[index]
        projects[index] = Project(
            id: current.id,
            title: current.title,
            description: current.description,
            icon: current.icon,
            status: current.status,
            priority: current.priority,
            leadID: current.leadID,
            leadType: current.leadType,
            issueCount: current.issueCount + 1,
            doneCount: current.doneCount,
            resourceCount: current.resourceCount,
            startDate: current.startDate,
            dueDate: current.dueDate,
            createdAt: current.createdAt,
            updatedAt: current.updatedAt,
            workspaceID: current.workspaceID
        )
    }
}
