import Foundation
import Testing
@testable import MulticaKit

@Suite("Understanding what someone said")
struct SpokenTermsTests {
    @Test("The four lane names map to themselves")
    func canonicalLanes() {
        for lane in BoardLane.allCases {
            #expect(BoardLane(spoken: lane.rawValue) == lane)
            #expect(BoardLane(spoken: lane.title) == lane)
        }
    }

    @Test("The way people actually say a lane in English")
    func englishSynonyms() {
        #expect(BoardLane(spoken: "in progress") == .ongoing)
        #expect(BoardLane(spoken: "In Progress") == .ongoing)
        #expect(BoardLane(spoken: "blocked") == .ongoing)
        #expect(BoardLane(spoken: "todo") == .planned)
        #expect(BoardLane(spoken: "to do") == .planned)
        #expect(BoardLane(spoken: "backlog") == .planned)
        #expect(BoardLane(spoken: "in review") == .staged)
        #expect(BoardLane(spoken: "done") == .finished)
        #expect(BoardLane(spoken: "shipped") == .finished)
    }

    @Test("German works too, since the workspace does")
    func germanSynonyms() {
        #expect(BoardLane(spoken: "geplant") == .planned)
        #expect(BoardLane(spoken: "in Arbeit") == .ongoing)
        #expect(BoardLane(spoken: "blockiert") == .ongoing)
        #expect(BoardLane(spoken: "erledigt") == .finished)
        #expect(BoardLane(spoken: "fertig") == .finished)
        #expect(BoardLane(spoken: "zur Prüfung") == .staged)
    }

    @Test("Spacing, dashes and accents do not change the answer")
    func normalisation() {
        #expect(BoardLane(spoken: "  IN-PROGRESS ") == .ongoing)
        #expect(BoardLane(spoken: "in_progress") == .ongoing)
        #expect(BoardLane(spoken: "Zur Prufung") == .staged)
    }

    @Test("A word that means nothing here returns nil instead of a wrong lane")
    func rejectsNonsense() {
        #expect(BoardLane(spoken: "banana") == nil)
        #expect(BoardLane(spoken: "") == nil)
        #expect(BoardLane(spoken: "   ") == nil)
    }

    @Test("Priorities read the same way")
    func priorities() {
        #expect(IssuePriority(spoken: "urgent") == .urgent)
        #expect(IssuePriority(spoken: "ASAP") == .urgent)
        #expect(IssuePriority(spoken: "dringend") == .urgent)
        #expect(IssuePriority(spoken: "wichtig") == .high)
        #expect(IssuePriority(spoken: "mittel") == .medium)
        #expect(IssuePriority(spoken: "niedrig") == .low)
        // `.none` here would read as Optional.none, so name the case explicitly.
        #expect(IssuePriority(spoken: "normal") == IssuePriority.none)
        #expect(IssuePriority(spoken: "purple") == nil)
    }
}

@Suite("Finding the thing someone meant")
struct WorkspaceLookupTests {
    private let projects = [
        Project(id: "p-1", title: "Multica Connect"),
        Project(id: "p-2", title: "Connect Marketing Site"),
        Project(id: "p-3", title: "blkbox.stream"),
    ]

    private let issues = [
        MulticaKit.Issue(id: "i-1", identifier: "CRATCH-4", title: "Ship the voice gateway", status: .inProgress),
        MulticaKit.Issue(id: "i-2", identifier: "CRATCH-5", title: "Ship the docs", status: .done),
        MulticaKit.Issue(id: "i-3", identifier: "CRATCH-6", title: "Ship the docs later", status: .todo),
    ]

    @Test("An exact title beats a fragment that also matches")
    func exactTitleWins() {
        #expect(WorkspaceLookup.project(named: "Multica Connect", in: projects)?.id == "p-1")
        #expect(WorkspaceLookup.issue(matching: "Ship the docs", in: issues)?.id == "i-2")
    }

    @Test("An identifier is matched case-insensitively")
    func identifierMatch() {
        #expect(WorkspaceLookup.issue(matching: "cratch-4", in: issues)?.id == "i-1")
        #expect(WorkspaceLookup.issue(matching: "CRATCH-6", in: issues)?.id == "i-3")
    }

    @Test("A raw id still resolves, for anything the app passes straight through")
    func idMatch() {
        #expect(WorkspaceLookup.project(named: "p-3", in: projects)?.title == "blkbox.stream")
        #expect(WorkspaceLookup.issue(matching: "i-3", in: issues)?.identifier == "CRATCH-6")
    }

    @Test("A fragment that fits two projects picks the closer-fitting title")
    func ambiguousFragment() {
        #expect(WorkspaceLookup.project(named: "connect", in: projects)?.id == "p-1")
    }

    @Test("A fragment prefers open work over something already finished")
    func prefersOpenWork() {
        let match = WorkspaceLookup.issue(matching: "docs later", in: issues)
        #expect(match?.id == "i-3")
    }

    @Test("Nothing matching returns nil rather than the first thing on the list")
    func noMatch() {
        #expect(WorkspaceLookup.project(named: "nonexistent", in: projects) == nil)
        #expect(WorkspaceLookup.issue(matching: "nothing like this", in: issues) == nil)
        #expect(WorkspaceLookup.project(named: "", in: projects) == nil)
        #expect(WorkspaceLookup.issue(matching: "  ", in: issues) == nil)
    }

    @Test("Agents resolve by name and by fragment")
    func agentLookup() {
        let agents = [Agent(id: "a-1", name: "Mika"), Agent(id: "a-2", name: "Blkbox")]
        #expect(WorkspaceLookup.agent(named: "mika", in: agents)?.id == "a-1")
        #expect(WorkspaceLookup.agent(named: "blk", in: agents)?.id == "a-2")
        #expect(WorkspaceLookup.agent(named: "nobody", in: agents) == nil)
    }
}
