import Foundation

/// A Multica project — the container the app groups tasks under.
public struct Project: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let title: String
    public let description: String?
    /// A single emoji the workspace picked for the project, when set.
    public let icon: String?
    public let status: ProjectStatus
    public let priority: IssuePriority
    public let leadID: String?
    public let leadType: ActorKind?
    public let issueCount: Int
    public let doneCount: Int
    public let resourceCount: Int
    public let startDate: String?
    public let dueDate: String?
    public let createdAt: Date
    public let updatedAt: Date
    public let workspaceID: String?

    /// Fraction of the project's issues that are finished, or `nil` when empty.
    public var completion: Double? {
        guard issueCount > 0 else { return nil }
        return Double(doneCount) / Double(issueCount)
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, description, icon, status, priority
        case leadID = "lead_id"
        case leadType = "lead_type"
        case issueCount = "issue_count"
        case doneCount = "done_count"
        case resourceCount = "resource_count"
        case startDate = "start_date"
        case dueDate = "due_date"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case workspaceID = "workspace_id"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        icon = try c.decodeIfPresent(String.self, forKey: .icon)
        status = try c.decodeIfPresent(ProjectStatus.self, forKey: .status) ?? .planned
        priority = try c.decodeIfPresent(IssuePriority.self, forKey: .priority) ?? .none
        leadID = try c.decodeIfPresent(String.self, forKey: .leadID)
        leadType = try c.decodeIfPresent(ActorKind.self, forKey: .leadType)
        issueCount = try c.decodeIfPresent(Int.self, forKey: .issueCount) ?? 0
        doneCount = try c.decodeIfPresent(Int.self, forKey: .doneCount) ?? 0
        resourceCount = try c.decodeIfPresent(Int.self, forKey: .resourceCount) ?? 0
        startDate = try c.decodeIfPresent(String.self, forKey: .startDate)
        dueDate = try c.decodeIfPresent(String.self, forKey: .dueDate)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? .distantPast
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? .distantPast
        workspaceID = try c.decodeIfPresent(String.self, forKey: .workspaceID)
    }

    public init(
        id: String,
        title: String,
        description: String? = nil,
        icon: String? = nil,
        status: ProjectStatus = .planned,
        priority: IssuePriority = .none,
        leadID: String? = nil,
        leadType: ActorKind? = nil,
        issueCount: Int = 0,
        doneCount: Int = 0,
        resourceCount: Int = 0,
        startDate: String? = nil,
        dueDate: String? = nil,
        createdAt: Date = .distantPast,
        updatedAt: Date = .distantPast,
        workspaceID: String? = nil
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.icon = icon
        self.status = status
        self.priority = priority
        self.leadID = leadID
        self.leadType = leadType
        self.issueCount = issueCount
        self.doneCount = doneCount
        self.resourceCount = resourceCount
        self.startDate = startDate
        self.dueDate = dueDate
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.workspaceID = workspaceID
    }
}

public enum ProjectStatus: RawRepresentable, Codable, Sendable, Hashable {
    case planned
    case inProgress
    case paused
    case completed
    case cancelled
    case other(String)

    public init(rawValue: String) {
        switch rawValue {
        case "planned": self = .planned
        case "in_progress": self = .inProgress
        case "paused": self = .paused
        case "completed": self = .completed
        case "cancelled": self = .cancelled
        default: self = .other(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .planned: "planned"
        case .inProgress: "in_progress"
        case .paused: "paused"
        case .completed: "completed"
        case .cancelled: "cancelled"
        case .other(let raw): raw
        }
    }

    public var displayName: String {
        switch self {
        case .planned: "Planned"
        case .inProgress: "In Progress"
        case .paused: "Paused"
        case .completed: "Completed"
        case .cancelled: "Cancelled"
        case .other(let raw): raw.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}
