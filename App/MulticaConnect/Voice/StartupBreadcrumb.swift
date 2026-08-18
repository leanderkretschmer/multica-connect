import Foundation

/// Remembers which start-up step was running, so a crash leaves a trace.
///
/// When a framework traps, the process dies with no error to catch and nothing
/// left on screen to read. The step name is written to disk as the step begins
/// and removed when start-up ends cleanly, so a leftover file means the last
/// attempt never finished — and names where it stopped.
///
/// Deliberately a file and not `UserDefaults`: defaults are flushed
/// asynchronously, and a crash is exactly the case where that flush does not
/// happen. An atomic write is on disk before the next line runs.
enum StartupBreadcrumb {
    /// Caches is right for this: it always exists, and a diagnostic crumb is no
    /// loss if the system reclaims it.
    private static var fileURL: URL? {
        try? FileManager.default.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        .appendingPathComponent("call-startup-step")
    }

    static func begin(_ step: VoiceCallModel.Phase.Step) {
        guard let fileURL else { return }
        try? Data(step.rawValue.utf8).write(to: fileURL, options: .atomic)
    }

    /// Called when start-up finishes, one way or another.
    static func clear() {
        guard let fileURL else { return }
        try? FileManager.default.removeItem(at: fileURL)
    }

    /// The step a previous attempt was on when it stopped, if it never finished.
    static var unfinishedStep: VoiceCallModel.Phase.Step? {
        guard let fileURL,
              let raw = try? String(contentsOf: fileURL, encoding: .utf8)
        else { return nil }
        return VoiceCallModel.Phase.Step(rawValue: raw)
    }
}
