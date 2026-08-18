import Foundation

/// Finds the thing someone meant from the words they used.
///
/// Voice never hands over a UUID. These resolvers accept an identifier, an
/// exact name, or a fragment, and are deliberately conservative: they prefer an
/// exact match, then open work, and return `nil` rather than guess wildly.
public enum WorkspaceLookup {
    public static func project(named name: String, in projects: [Project]) -> Project? {
        let needle = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return nil }
        if let byID = projects.first(where: { $0.id == needle }) { return byID }
        if let exact = projects.first(where: {
            $0.title.localizedCaseInsensitiveCompare(needle) == .orderedSame
        }) { return exact }
        let contains = projects.filter { $0.title.localizedCaseInsensitiveContains(needle) }
        // A fragment that fits several projects is ambiguous; take the shortest
        // title, which is the one the fragment covers most of.
        return contains.min { $0.title.count < $1.title.count }
    }

    public static func issue(matching text: String, in issues: [Issue]) -> Issue? {
        let needle = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return nil }
        if let byIdentifier = issues.first(where: {
            $0.identifier.localizedCaseInsensitiveCompare(needle) == .orderedSame
        }) { return byIdentifier }
        if let byID = issues.first(where: { $0.id == needle }) { return byID }
        if let exactTitle = issues.first(where: {
            $0.title.localizedCaseInsensitiveCompare(needle) == .orderedSame
        }) { return exactTitle }

        let matches = issues.filter { $0.title.localizedCaseInsensitiveContains(needle) }
        // Someone talking about a task almost always means a live one.
        return matches.first { $0.status.isOpen } ?? matches.first
    }

    public static func agent(named name: String, in agents: [Agent]) -> Agent? {
        let needle = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return nil }
        if let exact = agents.first(where: {
            $0.name.localizedCaseInsensitiveCompare(needle) == .orderedSame
        }) { return exact }
        return agents.first { $0.name.localizedCaseInsensitiveContains(needle) }
    }
}
