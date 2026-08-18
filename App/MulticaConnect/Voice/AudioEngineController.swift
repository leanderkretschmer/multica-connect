import AVFoundation
import Foundation

/// Owns the audio session and the microphone engine, deliberately off the main
/// actor.
///
/// `AVAudioSession.setCategory` and `setActive` block while the route is
/// negotiated — AVFoundation logs a warning when they are called on the main
/// thread, and a long enough block there is exactly what the system watchdog
/// terminates an app for. Apple's suggested asynchronous `activate` API is
/// iOS 27; on iOS 26 the answer is not a different call but a different thread,
/// which is what being a plain actor buys.
actor AudioEngineController {
    private let engine = AVAudioEngine()
    private(set) var isRunning = false

    /// Activates the session and starts the microphone, sending every buffer to
    /// `feed`.
    func start(feed: TapFeed) throws {
        guard !isRunning else { return }

        let session = AVAudioSession.sharedInstance()
        do {
            // `.voiceChat` gives echo cancellation, which is what keeps the
            // assistant's own speech out of the transcript.
            try session.setCategory(
                .playAndRecord,
                mode: .voiceChat,
                options: [.defaultToSpeaker, .duckOthers]
            )
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            throw SpeechTranscription.Failure.audioEngine(error.localizedDescription)
        }

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else {
            deactivate()
            throw SpeechTranscription.Failure.audioEngine("No input route is available.")
        }

        // The tap fires on a realtime audio thread. `TapFeed` is built to be
        // called from there; nothing else here may be touched from it.
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
            feed.receive(buffer)
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            deactivate()
            throw SpeechTranscription.Failure.audioEngine(error.localizedDescription)
        }
        isRunning = true
    }

    /// Stops the microphone and hands the audio session back to whatever was
    /// playing before the call.
    func stop() {
        guard isRunning else { return }
        isRunning = false
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        deactivate()
    }

    /// Releasing the session is what un-ducks other audio. It blocks as well,
    /// which is the other reason this type exists.
    private func deactivate() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
