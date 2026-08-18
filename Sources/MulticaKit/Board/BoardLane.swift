import Foundation

/// The four lanes the app shows tasks in.
///
/// Multica has seven statuses; a person asking "what's planned?" does not want
/// to know whether something sits in `backlog` or `todo`. The lane is the
/// coarse answer, the status pill stays visible for the precise one.
///
/// `blocked` lands in ``ongoing`` deliberately: it is started work that stopped,
/// not work nobody has picked up. The row badges it so it never reads as healthy.
public enum BoardLane: String, CaseIterable, Sendable, Hashable, Identifiable {
    case planned
    case ongoing
    case staged
    case finished

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .planned: "Planned"
        case .ongoing: "Ongoing"
        case .staged: "Staged"
        case .finished: "Finished"
        }
    }

    /// One line explaining what belongs here, for the empty state.
    public var emptyMessage: String {
        switch self {
        case .planned: "Nothing queued up yet."
        case .ongoing: "No work in flight right now."
        case .staged: "Nothing waiting for review."
        case .finished: "Nothing finished yet."
        }
    }

    /// SF Symbol used for the lane header and the tab bar.
    public var symbolName: String {
        switch self {
        case .planned: "tray"
        case .ongoing: "bolt.horizontal"
        case .staged: "checkmark.seal"
        case .finished: "checkmark.circle"
        }
    }

    /// The statuses that fall into this lane.
    public var statuses: [IssueStatus] {
        switch self {
        case .planned: [.backlog, .todo]
        case .ongoing: [.inProgress, .blocked]
        case .staged: [.inReview]
        case .finished: [.done, .cancelled]
        }
    }

    /// Where a status belongs. An unrecognised status is treated as planned
    /// work so it stays visible rather than disappearing from every lane.
    public static func lane(for status: IssueStatus) -> BoardLane {
        switch status {
        case .backlog, .todo: .planned
        case .inProgress, .blocked: .ongoing
        case .inReview: .staged
        case .done, .cancelled: .finished
        case .other: .planned
        }
    }

    /// The status to write when someone asks to move a task into this lane.
    public var canonicalStatus: IssueStatus {
        switch self {
        case .planned: .todo
        case .ongoing: .inProgress
        case .staged: .inReview
        case .finished: .done
        }
    }
}

extension Issue {
    public var lane: BoardLane { BoardLane.lane(for: status) }

    /// `true` when the task needs attention beyond its lane — surfaced as a badge.
    public var needsAttention: Bool { status == .blocked }
}
