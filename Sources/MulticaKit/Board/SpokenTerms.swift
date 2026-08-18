import Foundation

/// Turning spoken words into lanes and priorities.
///
/// The model is told to use the four lane names, but speech is not a form
/// field: people say "in progress", "erledigt", "review". Mapping the obvious
/// synonyms here is the difference between a command that works and one that
/// answers "unknown lane".
extension BoardLane {
    /// Maps a word someone said, in English or German, onto a lane.
    public init?(spoken text: String) {
        let key = SpokenTerms.normalize(text)
        guard !key.isEmpty else { return nil }
        guard let lane = BoardLane.spokenIndex[key] else { return nil }
        self = lane
    }

    private static let spokenIndex: [String: BoardLane] = {
        var index: [String: BoardLane] = [:]
        let table: [BoardLane: [String]] = [
            .planned: [
                "planned", "plan", "backlog", "todo", "to do", "next", "queued", "upcoming",
                "geplant", "plane", "offen", "warteschlange", "anstehend",
            ],
            .ongoing: [
                "ongoing", "in progress", "inprogress", "progress", "started", "doing",
                "active", "current", "working", "blocked", "wip",
                "laufend", "in arbeit", "inarbeit", "aktiv", "angefangen", "blockiert",
            ],
            .staged: [
                "staged", "stage", "review", "in review", "inreview", "ready",
                "waiting", "pending", "check",
                "review offen", "zur prufung", "prufung", "bereit", "wartend",
            ],
            .finished: [
                "finished", "finish", "done", "complete", "completed", "closed", "shipped",
                "cancelled", "canceled",
                "fertig", "erledigt", "abgeschlossen", "beendet", "abgebrochen",
            ],
        ]
        for (lane, words) in table {
            index[lane.rawValue] = lane
            for word in words { index[SpokenTerms.normalize(word)] = lane }
        }
        return index
    }()
}

extension IssuePriority {
    /// Maps a spoken urgency onto a priority.
    public init?(spoken text: String) {
        let key = SpokenTerms.normalize(text)
        guard !key.isEmpty else { return nil }
        guard let priority = IssuePriority.spokenIndex[key] else { return nil }
        self = priority
    }

    private static let spokenIndex: [String: IssuePriority] = {
        var index: [String: IssuePriority] = [:]
        let table: [IssuePriority: [String]] = [
            .none: ["none", "no priority", "normal", "keine", "egal"],
            .low: ["low", "minor", "later", "niedrig", "gering", "spater"],
            .medium: ["medium", "mid", "moderate", "mittel"],
            .high: ["high", "important", "soon", "hoch", "wichtig"],
            .urgent: ["urgent", "critical", "asap", "now", "dringend", "kritisch", "sofort"],
        ]
        for (priority, words) in table {
            index[priority.rawValue] = priority
            for word in words { index[SpokenTerms.normalize(word)] = priority }
        }
        return index
    }()
}

enum SpokenTerms {
    /// Lower-cases, folds accents, and collapses whitespace so "In Arbeit" and
    /// "in  arbeit" reach the same key.
    static func normalize(_ text: String) -> String {
        text
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .split(whereSeparator: { $0.isWhitespace || $0 == "-" || $0 == "_" })
            .joined(separator: " ")
            .trimmingCharacters(in: .punctuationCharacters)
    }
}
