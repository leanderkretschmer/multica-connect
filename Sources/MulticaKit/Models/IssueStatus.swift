import Foundation

/// The statuses a Multica issue can hold, spelled exactly as the server spells them.
///
/// `other` exists so a status the server adds later degrades to a labelled pill
/// instead of failing the decode of an entire board page.
public enum IssueStatus: RawRepresentable, Codable, Sendable, Hashable {
    case backlog
    case todo
    case inProgress
    case inReview
    case done
    case blocked
    case cancelled
    case other(String)

    public init(rawValue: String) {
        switch rawValue {
        case "backlog": self = .backlog
        case "todo": self = .todo
        case "in_progress": self = .inProgress
        case "in_review": self = .inReview
        case "done": self = .done
        case "blocked": self = .blocked
        case "cancelled": self = .cancelled
        default: self = .other(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .backlog: "backlog"
        case .todo: "todo"
        case .inProgress: "in_progress"
        case .inReview: "in_review"
        case .done: "done"
        case .blocked: "blocked"
        case .cancelled: "cancelled"
        case .other(let raw): raw
        }
    }

    /// Every status the server documents, in board order. Excludes `other`.
    public static let known: [IssueStatus] = [
        .backlog, .todo, .inProgress, .inReview, .blocked, .done, .cancelled,
    ]

    public var displayName: String {
        switch self {
        case .backlog: "Backlog"
        case .todo: "Todo"
        case .inProgress: "In Progress"
        case .inReview: "In Review"
        case .done: "Done"
        case .blocked: "Blocked"
        case .cancelled: "Cancelled"
        case .other(let raw): raw.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    /// `true` while the issue still represents outstanding work.
    public var isOpen: Bool {
        switch self {
        case .done, .cancelled: false
        default: true
        }
    }
}

/// Priority as the API reports it. `none` is the server default.
public enum IssuePriority: String, Codable, CaseIterable, Sendable, Hashable, Comparable {
    case none
    case low
    case medium
    case high
    case urgent

    /// Lenient decode: an unrecognised priority sorts as `none` rather than
    /// failing the surrounding issue.
    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = IssuePriority(rawValue: raw) ?? .none
    }

    private var rank: Int {
        switch self {
        case .none: 0
        case .low: 1
        case .medium: 2
        case .high: 3
        case .urgent: 4
        }
    }

    public static func < (lhs: IssuePriority, rhs: IssuePriority) -> Bool {
        lhs.rank < rhs.rank
    }

    public var displayName: String {
        switch self {
        case .none: "No priority"
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        case .urgent: "Urgent"
        }
    }
}

/// Who owns or authored something. Multica models this as an id plus a discriminator.
public enum ActorKind: String, Codable, Sendable, Hashable {
    case member
    case agent
    case squad

    public init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ActorKind(rawValue: raw) ?? .member
    }
}
