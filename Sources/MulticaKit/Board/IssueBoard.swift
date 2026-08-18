import Foundation

/// Issues grouped into lanes and sorted the way the board renders them.
///
/// Built purely from values, so the whole grouping is testable without a
/// server and without SwiftUI.
public struct IssueBoard: Sendable, Hashable {
    public let sections: [Section]

    public struct Section: Sendable, Hashable, Identifiable {
        public let lane: BoardLane
        public let issues: [Issue]

        public var id: BoardLane { lane }
        public var count: Int { issues.count }
        public var isEmpty: Bool { issues.isEmpty }

        public init(lane: BoardLane, issues: [Issue]) {
            self.lane = lane
            self.issues = issues
        }
    }

    /// Groups `issues` into every lane, keeping empty lanes so the board does
    /// not reflow as work moves between them.
    public init(issues: [Issue]) {
        var buckets: [BoardLane: [Issue]] = [:]
        for issue in issues {
            buckets[issue.lane, default: []].append(issue)
        }
        self.sections = BoardLane.allCases.map { lane in
            Section(lane: lane, issues: IssueBoard.sorted(buckets[lane] ?? [], in: lane))
        }
    }

    public subscript(lane: BoardLane) -> [Issue] {
        sections.first { $0.lane == lane }?.issues ?? []
    }

    public var totalCount: Int { sections.reduce(0) { $0 + $1.count } }

    /// Open work only — what the voice assistant means by "what's on my plate".
    public var openCount: Int {
        sections.filter { $0.lane != .finished }.reduce(0) { $0 + $1.count }
    }

    /// Blocked work climbs to the top of `ongoing`; finished work reads
    /// newest-first; everything else follows priority then recency.
    private static func sorted(_ issues: [Issue], in lane: BoardLane) -> [Issue] {
        switch lane {
        case .finished:
            issues.sorted { $0.updatedAt > $1.updatedAt }
        case .ongoing:
            issues.sorted { lhs, rhs in
                if lhs.needsAttention != rhs.needsAttention { return lhs.needsAttention }
                if lhs.priority != rhs.priority { return lhs.priority > rhs.priority }
                return lhs.updatedAt > rhs.updatedAt
            }
        case .planned, .staged:
            issues.sorted { lhs, rhs in
                if lhs.priority != rhs.priority { return lhs.priority > rhs.priority }
                return lhs.updatedAt > rhs.updatedAt
            }
        }
    }
}

extension IssueBoard {
    /// A compact plain-text digest of the board.
    ///
    /// This is what gets handed to the on-device model as context, and what the
    /// assistant reads back when asked for an overview — so it has to stay
    /// short enough to sit in a prompt and clear enough to be spoken aloud.
    public func digest(projectsByID: [String: Project] = [:], limitPerLane: Int = 5) -> String {
        var lines: [String] = []
        for section in sections where !section.isEmpty {
            lines.append("\(section.lane.title) (\(section.count)):")
            for issue in section.issues.prefix(limitPerLane) {
                let project = issue.projectID.flatMap { projectsByID[$0]?.title }
                let suffix = project.map { " — \($0)" } ?? ""
                let blocked = issue.needsAttention ? " [blocked]" : ""
                lines.append("  \(issue.identifier): \(issue.title)\(suffix)\(blocked)")
            }
            if section.count > limitPerLane {
                lines.append("  …and \(section.count - limitPerLane) more")
            }
        }
        return lines.isEmpty ? "No tasks in this workspace yet." : lines.joined(separator: "\n")
    }
}
