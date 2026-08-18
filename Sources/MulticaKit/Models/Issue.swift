import Foundation

/// One Multica issue — the unit the app calls a "task".
///
/// Field names mirror the `/api/issues` payload verbatim; see ``MulticaRoutes``
/// for where the contract comes from.
public struct Issue: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    /// Workspace-scoped human key, e.g. `CRATCH-4`.
    public let identifier: String
    public let number: Int
    public let title: String
    public let description: String?
    public let status: IssueStatus
    public let priority: IssuePriority
    public let projectID: String?
    public let parentIssueID: String?
    public let assigneeID: String?
    public let assigneeType: ActorKind?
    public let creatorID: String?
    public let creatorType: ActorKind?
    public let stage: Int?
    public let position: Int?
    public let startDate: String?
    public let dueDate: String?
    public let labels: [Label]
    public let createdAt: Date
    public let updatedAt: Date
    public let workspaceID: String?

    public struct Label: Codable, Sendable, Hashable, Identifiable {
        public let id: String
        public let name: String
        /// Hex string such as `#6b7280`, or `nil` when the server omits it.
        public let color: String?

        public init(id: String, name: String, color: String? = nil) {
            self.id = id
            self.name = name
            self.color = color
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id, identifier, number, title, description, status, priority
        case projectID = "project_id"
        case parentIssueID = "parent_issue_id"
        case assigneeID = "assignee_id"
        case assigneeType = "assignee_type"
        case creatorID = "creator_id"
        case creatorType = "creator_type"
        case stage, position, labels
        case startDate = "start_date"
        case dueDate = "due_date"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case workspaceID = "workspace_id"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        identifier = try c.decodeIfPresent(String.self, forKey: .identifier) ?? ""
        number = try c.decodeIfPresent(Int.self, forKey: .number) ?? 0
        title = try c.decode(String.self, forKey: .title)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        status = try c.decodeIfPresent(IssueStatus.self, forKey: .status) ?? .backlog
        priority = try c.decodeIfPresent(IssuePriority.self, forKey: .priority) ?? .none
        projectID = try c.decodeIfPresent(String.self, forKey: .projectID)
        parentIssueID = try c.decodeIfPresent(String.self, forKey: .parentIssueID)
        assigneeID = try c.decodeIfPresent(String.self, forKey: .assigneeID)
        assigneeType = try c.decodeIfPresent(ActorKind.self, forKey: .assigneeType)
        creatorID = try c.decodeIfPresent(String.self, forKey: .creatorID)
        creatorType = try c.decodeIfPresent(ActorKind.self, forKey: .creatorType)
        stage = try c.decodeIfPresent(Int.self, forKey: .stage)
        position = try c.decodeIfPresent(Int.self, forKey: .position)
        startDate = try c.decodeIfPresent(String.self, forKey: .startDate)
        dueDate = try c.decodeIfPresent(String.self, forKey: .dueDate)
        labels = try c.decodeIfPresent([Label].self, forKey: .labels) ?? []
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? .distantPast
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? .distantPast
        workspaceID = try c.decodeIfPresent(String.self, forKey: .workspaceID)
    }

    public init(
        id: String,
        identifier: String,
        number: Int = 0,
        title: String,
        description: String? = nil,
        status: IssueStatus = .backlog,
        priority: IssuePriority = .none,
        projectID: String? = nil,
        parentIssueID: String? = nil,
        assigneeID: String? = nil,
        assigneeType: ActorKind? = nil,
        creatorID: String? = nil,
        creatorType: ActorKind? = nil,
        stage: Int? = nil,
        position: Int? = nil,
        startDate: String? = nil,
        dueDate: String? = nil,
        labels: [Label] = [],
        createdAt: Date = .distantPast,
        updatedAt: Date = .distantPast,
        workspaceID: String? = nil
    ) {
        self.id = id
        self.identifier = identifier
        self.number = number
        self.title = title
        self.description = description
        self.status = status
        self.priority = priority
        self.projectID = projectID
        self.parentIssueID = parentIssueID
        self.assigneeID = assigneeID
        self.assigneeType = assigneeType
        self.creatorID = creatorID
        self.creatorType = creatorType
        self.stage = stage
        self.position = position
        self.startDate = startDate
        self.dueDate = dueDate
        self.labels = labels
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.workspaceID = workspaceID
    }
}

/// A page of issues as `/api/issues` returns it.
public struct IssuePage: Codable, Sendable {
    public let issues: [Issue]
    public let hasMore: Bool

    private enum CodingKeys: String, CodingKey {
        case issues
        case hasMore = "has_more"
    }

    public init(issues: [Issue], hasMore: Bool = false) {
        self.issues = issues
        self.hasMore = hasMore
    }

    public init(from decoder: any Decoder) throws {
        // The list endpoint wraps its results; search returns a bare array.
        if let c = try? decoder.container(keyedBy: CodingKeys.self),
           let issues = try? c.decode([Issue].self, forKey: .issues) {
            self.issues = issues
            let more = try? c.decodeIfPresent(Bool.self, forKey: .hasMore)
            self.hasMore = more.flatMap { $0 } ?? false
        } else {
            self.issues = try decoder.singleValueContainer().decode([Issue].self)
            self.hasMore = false
        }
    }
}
