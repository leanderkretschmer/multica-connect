import Foundation

/// One comment on an issue. Threads are flat rows linked by ``parentID``.
public struct IssueComment: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let issueID: String
    public let content: String
    /// `true` when the server clipped ``content`` for a summary read.
    public let contentTruncated: Bool
    public let authorID: String?
    public let authorType: ActorKind?
    public let parentID: String?
    public let replyCount: Int
    public let resolvedAt: Date?
    public let createdAt: Date
    public let updatedAt: Date
    public let lastActivityAt: Date?
    /// Set when an agent run produced this comment.
    public let sourceTaskID: String?

    public var isResolved: Bool { resolvedAt != nil }
    public var isRoot: Bool { parentID == nil }

    private enum CodingKeys: String, CodingKey {
        case id, content
        case issueID = "issue_id"
        case contentTruncated = "content_truncated"
        case authorID = "author_id"
        case authorType = "author_type"
        case parentID = "parent_id"
        case replyCount = "reply_count"
        case resolvedAt = "resolved_at"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case lastActivityAt = "last_activity_at"
        case sourceTaskID = "source_task_id"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        issueID = try c.decodeIfPresent(String.self, forKey: .issueID) ?? ""
        content = try c.decodeIfPresent(String.self, forKey: .content) ?? ""
        contentTruncated = try c.decodeIfPresent(Bool.self, forKey: .contentTruncated) ?? false
        authorID = try c.decodeIfPresent(String.self, forKey: .authorID)
        authorType = try c.decodeIfPresent(ActorKind.self, forKey: .authorType)
        parentID = try c.decodeIfPresent(String.self, forKey: .parentID)
        replyCount = try c.decodeIfPresent(Int.self, forKey: .replyCount) ?? 0
        resolvedAt = try c.decodeIfPresent(Date.self, forKey: .resolvedAt)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? .distantPast
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? .distantPast
        lastActivityAt = try c.decodeIfPresent(Date.self, forKey: .lastActivityAt)
        sourceTaskID = try c.decodeIfPresent(String.self, forKey: .sourceTaskID)
    }

    public init(
        id: String,
        issueID: String,
        content: String,
        contentTruncated: Bool = false,
        authorID: String? = nil,
        authorType: ActorKind? = nil,
        parentID: String? = nil,
        replyCount: Int = 0,
        resolvedAt: Date? = nil,
        createdAt: Date = .distantPast,
        updatedAt: Date = .distantPast,
        lastActivityAt: Date? = nil,
        sourceTaskID: String? = nil
    ) {
        self.id = id
        self.issueID = issueID
        self.content = content
        self.contentTruncated = contentTruncated
        self.authorID = authorID
        self.authorType = authorType
        self.parentID = parentID
        self.replyCount = replyCount
        self.resolvedAt = resolvedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastActivityAt = lastActivityAt
        self.sourceTaskID = sourceTaskID
    }
}
