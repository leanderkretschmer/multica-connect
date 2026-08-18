import Foundation

/// The body of `POST /api/issues`. Only the fields the caller filled in are
/// sent, so the server keeps applying its own defaults for the rest.
public struct IssueDraft: Codable, Sendable, Hashable {
    public var title: String
    public var description: String?
    public var projectID: String?
    public var status: IssueStatus?
    public var priority: IssuePriority?
    public var assigneeID: String?
    public var parentIssueID: String?
    public var stage: Int?
    public var startDate: String?
    public var dueDate: String?

    public init(
        title: String,
        description: String? = nil,
        projectID: String? = nil,
        status: IssueStatus? = nil,
        priority: IssuePriority? = nil,
        assigneeID: String? = nil,
        parentIssueID: String? = nil,
        stage: Int? = nil,
        startDate: String? = nil,
        dueDate: String? = nil
    ) {
        self.title = title
        self.description = description
        self.projectID = projectID
        self.status = status
        self.priority = priority
        self.assigneeID = assigneeID
        self.parentIssueID = parentIssueID
        self.stage = stage
        self.startDate = startDate
        self.dueDate = dueDate
    }

    private enum CodingKeys: String, CodingKey {
        case title, description, status, priority, stage
        case projectID = "project_id"
        case assigneeID = "assignee_id"
        case parentIssueID = "parent_issue_id"
        case startDate = "start_date"
        case dueDate = "due_date"
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(title, forKey: .title)
        try c.encodeIfPresent(description, forKey: .description)
        try c.encodeIfPresent(projectID, forKey: .projectID)
        try c.encodeIfPresent(status?.rawValue, forKey: .status)
        try c.encodeIfPresent(priority?.rawValue, forKey: .priority)
        try c.encodeIfPresent(assigneeID, forKey: .assigneeID)
        try c.encodeIfPresent(parentIssueID, forKey: .parentIssueID)
        try c.encodeIfPresent(stage, forKey: .stage)
        try c.encodeIfPresent(startDate, forKey: .startDate)
        try c.encodeIfPresent(dueDate, forKey: .dueDate)
    }

    /// `true` once the draft has enough to be worth sending.
    public var isSubmittable: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// The body of `PATCH /api/issues/{id}`. Absent fields are left untouched.
public struct IssueUpdate: Codable, Sendable, Hashable {
    public var title: String?
    public var description: String?
    public var status: IssueStatus?
    public var priority: IssuePriority?
    public var projectID: String?
    public var assigneeID: String?
    public var dueDate: String?

    public init(
        title: String? = nil,
        description: String? = nil,
        status: IssueStatus? = nil,
        priority: IssuePriority? = nil,
        projectID: String? = nil,
        assigneeID: String? = nil,
        dueDate: String? = nil
    ) {
        self.title = title
        self.description = description
        self.status = status
        self.priority = priority
        self.projectID = projectID
        self.assigneeID = assigneeID
        self.dueDate = dueDate
    }

    private enum CodingKeys: String, CodingKey {
        case title, description, status, priority
        case projectID = "project_id"
        case assigneeID = "assignee_id"
        case dueDate = "due_date"
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(title, forKey: .title)
        try c.encodeIfPresent(description, forKey: .description)
        try c.encodeIfPresent(status?.rawValue, forKey: .status)
        try c.encodeIfPresent(priority?.rawValue, forKey: .priority)
        try c.encodeIfPresent(projectID, forKey: .projectID)
        try c.encodeIfPresent(assigneeID, forKey: .assigneeID)
        try c.encodeIfPresent(dueDate, forKey: .dueDate)
    }

    /// `true` when the update would change nothing, so callers can skip the call.
    public var isEmpty: Bool {
        title == nil && description == nil && status == nil && priority == nil
            && projectID == nil && assigneeID == nil && dueDate == nil
    }
}

/// The body of `POST /api/projects`.
public struct ProjectDraft: Codable, Sendable, Hashable {
    public var title: String
    public var description: String?
    public var icon: String?
    public var status: ProjectStatus?
    public var startDate: String?
    public var dueDate: String?

    public init(
        title: String,
        description: String? = nil,
        icon: String? = nil,
        status: ProjectStatus? = nil,
        startDate: String? = nil,
        dueDate: String? = nil
    ) {
        self.title = title
        self.description = description
        self.icon = icon
        self.status = status
        self.startDate = startDate
        self.dueDate = dueDate
    }

    private enum CodingKeys: String, CodingKey {
        case title, description, icon, status
        case startDate = "start_date"
        case dueDate = "due_date"
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(title, forKey: .title)
        try c.encodeIfPresent(description, forKey: .description)
        try c.encodeIfPresent(icon, forKey: .icon)
        try c.encodeIfPresent(status?.rawValue, forKey: .status)
        try c.encodeIfPresent(startDate, forKey: .startDate)
        try c.encodeIfPresent(dueDate, forKey: .dueDate)
    }

    public var isSubmittable: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// The body of `POST /api/issues/{id}/comments`.
public struct CommentDraft: Codable, Sendable, Hashable {
    public var content: String
    public var parentID: String?

    public init(content: String, parentID: String? = nil) {
        self.content = content
        self.parentID = parentID
    }

    private enum CodingKeys: String, CodingKey {
        case content
        case parentID = "parent_id"
    }
}
