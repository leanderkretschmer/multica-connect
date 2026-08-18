import AVFoundation
import Foundation

/// Reads the assistant's replies out loud.
///
/// The call screen needs to know exactly when speaking starts and stops so it
/// can mute the microphone in between — otherwise the transcriber hears the
/// assistant and answers itself.
@MainActor
final class SpeechNarrator: NSObject {
    private let synthesizer = AVSpeechSynthesizer()
    private var completion: (@MainActor () -> Void)?
    /// The utterance the current ``completion`` belongs to, so a delegate
    /// callback arriving late for a superseded utterance is ignored instead of
    /// ending the wrong wait.
    private var currentUtterance: AVSpeechUtterance?

    private(set) var isSpeaking = false

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// Speaks `text` in `locale`, calling `onFinish` when the last word is out.
    ///
    /// A new utterance replaces whatever is currently being spoken, so the
    /// assistant never talks over itself.
    func speak(_ text: String, locale: Locale, onFinish: @escaping @MainActor () -> Void) {
        let spoken = SpeechNarrator.strippedForSpeech(text)
        guard !spoken.isEmpty else {
            onFinish()
            return
        }

        // Whoever was waiting on the previous utterance is released here, before
        // it is replaced. Dropping the old completion instead would strand its
        // caller on an `await` that can never finish.
        finishCurrent()
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        let utterance = AVSpeechUtterance(string: spoken)
        utterance.voice = SpeechNarrator.voice(for: locale)
        utterance.prefersAssistiveTechnologySettings = true
        currentUtterance = utterance
        completion = onFinish
        isSpeaking = true
        synthesizer.speak(utterance)
    }

    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        isSpeaking = false
        finishCurrent()
    }

    /// Ends the current wait exactly once, whatever caused it to end.
    private func finishCurrent() {
        let finish = completion
        completion = nil
        currentUtterance = nil
        finish?()
    }

    /// Picks the best installed voice for the locale, preferring the enhanced
    /// ones when the person has downloaded them.
    private static func voice(for locale: Locale) -> AVSpeechSynthesisVoice? {
        let identifier = locale.identifier.replacingOccurrences(of: "_", with: "-")
        let matching = AVSpeechSynthesisVoice.speechVoices().filter {
            $0.language.caseInsensitiveCompare(identifier) == .orderedSame
                || $0.language.hasPrefix(locale.language.languageCode?.identifier ?? identifier)
        }
        return matching.first { $0.quality == .premium }
            ?? matching.first { $0.quality == .enhanced }
            ?? matching.first
            ?? AVSpeechSynthesisVoice(language: identifier)
    }

    /// Removes the punctuation that reads badly out loud.
    ///
    /// The model is told not to emit Markdown, but a stray bullet or backtick
    /// should never become a spoken "asterisk".
    static func strippedForSpeech(_ text: String) -> String {
        var result = text
        for token in ["**", "__", "`", "#", "*", "_", ">"] {
            result = result.replacingOccurrences(of: token, with: "")
        }
        return result
            .replacingOccurrences(of: "\n", with: ". ")
            .replacingOccurrences(of: "..", with: ".")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension SpeechNarrator: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in ended(utterance) }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in ended(utterance) }
    }

    /// Callbacks hop to the main actor, so one for an utterance that has since
    /// been replaced can arrive after the next one started. Only the current
    /// utterance is allowed to end the wait.
    private func ended(_ utterance: AVSpeechUtterance) {
        guard utterance === currentUtterance else { return }
        isSpeaking = false
        finishCurrent()
    }
}
