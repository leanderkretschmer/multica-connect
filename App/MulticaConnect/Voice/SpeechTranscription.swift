import AVFoundation
import Foundation
import Speech

/// Turns the microphone into text on device, using `SpeechAnalyzer` with a
/// `SpeechTranscriber` module.
///
/// Nothing leaves the device: the locale's model is downloaded once by the
/// system and the audio is analysed locally.
@MainActor
final class SpeechTranscription {
    /// What the caller sees while someone is talking.
    struct Update {
        /// Everything finalised so far in this utterance, plus the volatile tail.
        let text: String
        /// `true` once the transcriber has committed the words.
        let isFinal: Bool
    }

    enum Failure: LocalizedError {
        case microphoneDenied
        case missingUsageDescription(String)
        case notSupportedOnDevice
        case localeUnsupported(Locale)
        case assetInstallFailed(String)
        case audioEngine(String)

        var errorDescription: String? {
            switch self {
            case .microphoneDenied:
                "Multica Connect needs the microphone to hear you. Turn it on in Settings."
            case .missingUsageDescription(let key):
                "This build is missing \(key) in its Info.plist, so iOS will not allow the microphone. Add it in the target's build settings."
            case .notSupportedOnDevice:
                "This device can't transcribe speech on device."
            case .localeUnsupported(let locale):
                "Speech isn't available for \(locale.identifier) yet. Try another language in Settings."
            case .assetInstallFailed(let detail):
                "The speech model could not be downloaded. \(detail)"
            case .audioEngine(let detail):
                "The microphone could not be started. \(detail)"
            }
        }
    }

    /// Fed while a call is running. A fresh stream is handed out by every
    /// ``start(locale:)`` — `AsyncStream` supports one consumer, so reusing a
    /// single stream across calls would drop the second call's transcript.
    private var updateContinuation: AsyncStream<Update>.Continuation?

    private let engine = AVAudioEngine()
    private var analyzer: SpeechAnalyzer?
    private var transcriber: SpeechTranscriber?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?
    private var analyzerFormat: AVAudioFormat?
    private var reservedLocale: Locale?

    /// Text committed so far in the current utterance.
    private var finalizedText = ""

    /// While `true` the tap drops audio — used so the assistant's own voice is
    /// never transcribed back as if the person had said it.
    var isMuted = false {
        didSet { feed?.setMuted(isMuted) }
    }

    private var feed: TapFeed?

    private(set) var isRunning = false

    // MARK: - Permission and assets

    /// The privacy keys iOS demands before this app may touch the microphone or
    /// on-device speech.
    ///
    /// A missing one is not an error iOS reports back: it terminates the process
    /// with `SIGKILL` and a TCC termination reason, which no `catch` can see and
    /// which points at whatever frame the thread happened to be in. Checking the
    /// bundle first turns that into a sentence naming the key.
    static var missingUsageDescriptionKeys: [String] {
        ["NSMicrophoneUsageDescription", "NSSpeechRecognitionUsageDescription"].filter { key in
            let value = Bundle.main.object(forInfoDictionaryKey: key) as? String
            return value?.isEmpty != false
        }
    }

    /// Asks for the microphone once. Returns `false` if the person said no.
    static func requestMicrophoneAccess() async throws -> Bool {
        if let missing = missingUsageDescriptionKeys.first {
            throw Failure.missingUsageDescription(missing)
        }

        switch AVAudioApplication.shared.recordPermission {
        case .granted: return true
        case .denied: return false
        default:
            return await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    /// Makes sure the locale's on-device model is installed, downloading it if
    /// this is the first run.
    ///
    /// - Returns: the locale that will actually be used, which may be a
    ///   regional equivalent of the one asked for.
    func prepare(locale requested: Locale) async throws -> Locale {
        guard SpeechTranscriber.isAvailable else { throw Failure.notSupportedOnDevice }

        guard let locale = await SpeechTranscription.supportedLocale(for: requested) else {
            throw Failure.localeUnsupported(requested)
        }

        let module = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [module]) {
            do {
                try await request.downloadAndInstall()
            } catch {
                throw Failure.assetInstallFailed(error.localizedDescription)
            }
        }
        // Reserving keeps the model from being evicted while the call runs.
        if try await AssetInventory.reserve(locale: locale) {
            reservedLocale = locale
        }
        return locale
    }

    /// The requested locale, a regional equivalent of it, or English as a last
    /// resort.
    ///
    /// Written as two statements rather than one `??`: the right-hand side of
    /// `??` is an autoclosure, and an autoclosure cannot be `async`.
    private static func supportedLocale(for requested: Locale) async -> Locale? {
        if let exact = await SpeechTranscriber.supportedLocale(equivalentTo: requested) {
            return exact
        }
        return await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "en-US"))
    }

    // MARK: - Running

    /// Starts listening and returns the stream of transcript updates for this
    /// call.
    @discardableResult
    func start(locale: Locale) async throws -> AsyncStream<Update> {
        guard !isRunning else { throw Failure.audioEngine("A call is already running.") }
        guard try await SpeechTranscription.requestMicrophoneAccess() else {
            throw Failure.microphoneDenied
        }

        let (updates, continuation) = AsyncStream<Update>.makeStream()
        updateContinuation = continuation

        let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
        self.transcriber = transcriber

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        self.analyzer = analyzer
        analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])

        let (inputStream, inputContinuation) = AsyncStream<AnalyzerInput>.makeStream()
        self.inputContinuation = inputContinuation

        resultsTask = Task { [weak self] in
            await self?.consumeResults(from: transcriber)
        }

        do {
            try await analyzer.start(inputSequence: inputStream)
            try startEngine()
        } catch {
            // Do not leave a half-open stream behind for the caller to iterate.
            continuation.finish()
            updateContinuation = nil
            resultsTask?.cancel()
            resultsTask = nil
            self.analyzer = nil
            self.transcriber = nil
            throw error
        }
        isRunning = true
        return updates
    }

    /// Stops the microphone and lets the analyzer flush what it still holds.
    func stop() async {
        guard isRunning else { return }
        isRunning = false

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        feed = nil
        inputContinuation?.finish()
        inputContinuation = nil
        updateContinuation?.finish()
        updateContinuation = nil

        if let analyzer {
            try? await analyzer.finalizeAndFinishThroughEndOfInput()
        }
        resultsTask?.cancel()
        resultsTask = nil
        analyzer = nil
        transcriber = nil

        if let reservedLocale {
            _ = await AssetInventory.release(reservedLocale: reservedLocale)
            self.reservedLocale = nil
        }
        finalizedText = ""
    }

    /// Forgets the current utterance so the next one starts clean.
    func resetUtterance() {
        finalizedText = ""
    }

    // MARK: - Audio

    private func startEngine() throws {
        let session = AVAudioSession.sharedInstance()
        do {
            // `.voiceChat` gives echo cancellation, which is what keeps the
            // assistant's own speech out of the transcript.
            try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .duckOthers])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            throw Failure.audioEngine(error.localizedDescription)
        }

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0 else {
            throw Failure.audioEngine("No input route is available.")
        }

        let feed = TapFeed(continuation: inputContinuation, target: analyzerFormat, isMuted: isMuted)
        self.feed = feed
        // The tap fires on a realtime audio thread. `TapFeed` is built to be
        // called from there — the SDK does not mark this block `@Sendable`, so
        // the compiler treats it as inheriting this method's isolation, which
        // is why nothing here may touch main-actor state.
        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { buffer, _ in
            feed.receive(buffer)
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw Failure.audioEngine(error.localizedDescription)
        }
    }

    // MARK: - Results

    private func consumeResults(from transcriber: SpeechTranscriber) async {
        do {
            for try await result in transcriber.results {
                let text = String(result.text.characters)
                if result.isFinal {
                    finalizedText = [finalizedText, text]
                        .filter { !$0.isEmpty }
                        .joined(separator: " ")
                    updateContinuation?.yield(Update(text: finalizedText, isFinal: true))
                } else {
                    let combined = [finalizedText, text]
                        .filter { !$0.isEmpty }
                        .joined(separator: " ")
                    updateContinuation?.yield(Update(text: combined, isFinal: false))
                }
            }
        } catch {
            // A cancelled call tears the stream down; that is not an error worth
            // surfacing. Anything else stops transcription until the next start.
            if !Task.isCancelled {
                updateContinuation?.yield(Update(text: finalizedText, isFinal: true))
            }
        }
    }
}

/// Carries microphone buffers from the realtime audio thread to the analyzer.
///
/// This used to hop every buffer to the main actor. That cost a task per buffer
/// and, worse, did not preserve their order: tasks are not delivered in the
/// order they were created, and audio that reaches a transcriber out of order
/// comes back as nonsense. It also read a main-actor object from the audio
/// thread to do it.
///
/// Yielding straight from the tap fixes both — `AsyncStream.Continuation.yield`
/// is thread-safe and keeps order. `@unchecked Sendable` is the honest label:
/// the audio engine calls the tap serially, so the converter needs no lock, and
/// the one flag the main actor writes is locked.
private final class TapFeed: @unchecked Sendable {
    private let continuation: AsyncStream<AnalyzerInput>.Continuation?
    private let target: AVAudioFormat?

    private let mutedLock = NSLock()
    private var mutedFlag: Bool

    /// Touched only from the tap, which the engine calls one buffer at a time.
    private var converter: AVAudioConverter?

    init(
        continuation: AsyncStream<AnalyzerInput>.Continuation?,
        target: AVAudioFormat?,
        isMuted: Bool
    ) {
        self.continuation = continuation
        self.target = target
        self.mutedFlag = isMuted
    }

    func setMuted(_ muted: Bool) {
        mutedLock.lock()
        mutedFlag = muted
        mutedLock.unlock()
    }

    private var isMuted: Bool {
        mutedLock.lock()
        defer { mutedLock.unlock() }
        return mutedFlag
    }

    /// Called on the audio thread, once per buffer.
    func receive(_ buffer: AVAudioPCMBuffer) {
        guard !isMuted, let continuation else { return }
        guard let converted = convert(buffer) else { return }
        continuation.yield(AnalyzerInput(buffer: converted))
    }

    /// Resamples the microphone buffer into whatever format the analyzer asked
    /// for. Returns the buffer untouched when the formats already agree.
    private func convert(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        guard let target else { return buffer }
        if buffer.format == target { return buffer }

        if converter == nil || converter?.outputFormat != target || converter?.inputFormat != buffer.format {
            converter = AVAudioConverter(from: buffer.format, to: target)
            converter?.primeMethod = .none
        }
        guard let converter else { return nil }

        let ratio = target.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 64
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return nil }

        let source = ConversionSource(buffer)
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            source.next(inputStatus)
        }

        guard status != .error, output.frameLength > 0 else { return nil }
        return output
    }
}

/// Hands one buffer to `AVAudioConverter`, then reports that the input is spent.
///
/// The converter calls this block synchronously, on the thread that asked for
/// the conversion — but the block is typed `@Sendable`, so a captured `var` and
/// a captured buffer are both flagged. Putting the one-shot state in a class
/// says what is actually true (one buffer, handed over once, from one thread)
/// instead of silencing the check with `@preconcurrency`.
private final class ConversionSource: @unchecked Sendable {
    private let buffer: AVAudioPCMBuffer
    private var isConsumed = false

    init(_ buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }

    func next(_ status: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioBuffer? {
        guard !isConsumed else {
            status.pointee = .noDataNow
            return nil
        }
        isConsumed = true
        status.pointee = .haveData
        return buffer
    }
}
