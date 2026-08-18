import Foundation
import Testing
@testable import MulticaKit

@Suite("Grouping tasks into board lanes")
struct BoardTests {
    private func issue(
        _ id: String,
        _ status: IssueStatus,
        priority: IssuePriority = .none,
        updated: TimeInterval = 0
    ) -> MulticaKit.Issue {
        MulticaKit.Issue(
            id: id,
            identifier: id.uppercased(),
            title: "Task \(id)",
            status: status,
            priority: priority,
            updatedAt: Date(timeIntervalSince1970: updated)
        )
    }

    @Test("Every documented status lands in exactly one lane")
    func everyStatusIsPlaced() {
        for status in IssueStatus.known {
            let lane = BoardLane.lane(for: status)
            #expect(lane.statuses.contains(status), "\(status.rawValue) is missing from \(lane.title)")
        }
        let placed = BoardLane.allCases.flatMap(\.statuses)
        #expect(Set(placed).count == placed.count, "a status is claimed by two lanes")
        #expect(Set(placed) == Set(IssueStatus.known))
    }

    @Test("Backlog and todo read as planned, in_review as staged")
    func laneMapping() {
        #expect(BoardLane.lane(for: .backlog) == .planned)
        #expect(BoardLane.lane(for: .todo) == .planned)
        #expect(BoardLane.lane(for: .inProgress) == .ongoing)
        #expect(BoardLane.lane(for: .inReview) == .staged)
        #expect(BoardLane.lane(for: .done) == .finished)
        #expect(BoardLane.lane(for: .cancelled) == .finished)
    }

    @Test("Blocked work stays in ongoing and is flagged")
    func blockedIsOngoingAndFlagged() {
        let blocked = issue("b1", .blocked)
        #expect(blocked.lane == .ongoing)
        #expect(blocked.needsAttention)
        #expect(issue("o1", .inProgress).needsAttention == false)
    }

    @Test("An unrecognised status still shows up, in planned")
    func unknownStatusStaysVisible() {
        let board = IssueBoard(issues: [issue("x", .other("awaiting_launch"))])
        #expect(board[.planned].count == 1)
        #expect(board.totalCount == 1)
    }

    @Test("Empty lanes are kept so the board does not reflow")
    func emptyLanesRetained() {
        let board = IssueBoard(issues: [issue("a", .todo)])
        #expect(board.sections.count == BoardLane.allCases.count)
        #expect(board.sections.map(\.lane) == BoardLane.allCases)
        #expect(board[.finished].isEmpty)
    }

    @Test("Blocked sorts above other ongoing work, then priority, then recency")
    func ongoingOrder() {
        let board = IssueBoard(issues: [
            issue("low", .inProgress, priority: .low, updated: 300),
            issue("urgent", .inProgress, priority: .urgent, updated: 100),
            issue("stuck", .blocked, priority: .none, updated: 50),
        ])
        #expect(board[.ongoing].map(\.id) == ["stuck", "urgent", "low"])
    }

    @Test("Finished work reads newest first")
    func finishedOrder() {
        let board = IssueBoard(issues: [
            issue("old", .done, updated: 10),
            issue("new", .done, updated: 90),
            issue("mid", .cancelled, updated: 50),
        ])
        #expect(board[.finished].map(\.id) == ["new", "mid", "old"])
    }

    @Test("Open count excludes finished work")
    func openCount() {
        let board = IssueBoard(issues: [
            issue("a", .todo), issue("b", .inProgress),
            issue("c", .inReview), issue("d", .done), issue("e", .cancelled),
        ])
        #expect(board.totalCount == 5)
        #expect(board.openCount == 3)
    }

    @Test("Each lane offers the status to write when work is moved into it")
    func canonicalStatuses() {
        #expect(BoardLane.planned.canonicalStatus == .todo)
        #expect(BoardLane.ongoing.canonicalStatus == .inProgress)
        #expect(BoardLane.staged.canonicalStatus == .inReview)
        #expect(BoardLane.finished.canonicalStatus == .done)
        for lane in BoardLane.allCases {
            #expect(BoardLane.lane(for: lane.canonicalStatus) == lane)
        }
    }
}

@Suite("The digest the assistant speaks and the model reads")
struct DigestTests {
    private func issue(_ id: String, _ status: IssueStatus, title: String, project: String? = nil) -> MulticaKit.Issue {
        MulticaKit.Issue(id: id, identifier: id.uppercased(), title: title, status: status, projectID: project)
    }

    @Test("The digest names lanes, identifiers and projects")
    func digestContent() {
        let board = IssueBoard(issues: [
            issue("i1", .inProgress, title: "Ship the board", project: "p1"),
            issue("i2", .todo, title: "Draft onboarding"),
        ])
        let digest = board.digest(projectsByID: ["p1": Project(id: "p1", title: "Connect")])
        #expect(digest.contains("Ongoing (1):"))
        #expect(digest.contains("I1: Ship the board — Connect"))
        #expect(digest.contains("Planned (1):"))
        #expect(digest.contains("I2: Draft onboarding"))
        #expect(digest.contains("Staged") == false, "empty lanes stay out of the spoken digest")
    }

    @Test("Blocked work is called out in the digest")
    func digestFlagsBlocked() {
        let board = IssueBoard(issues: [issue("i1", .blocked, title: "Waiting on keys")])
        #expect(board.digest().contains("[blocked]"))
    }

    @Test("Long lanes are clipped with a count so the prompt stays small")
    func digestClips() {
        let issues = (1...9).map { issue("i\($0)", .todo, title: "Task \($0)") }
        let digest = IssueBoard(issues: issues).digest(limitPerLane: 3)
        #expect(digest.contains("…and 6 more"))
        #expect(digest.split(separator: "\n").count == 5)
    }

    @Test("An empty workspace says so instead of returning nothing")
    func digestEmpty() {
        #expect(IssueBoard(issues: []).digest() == "No tasks in this workspace yet.")
    }
}
