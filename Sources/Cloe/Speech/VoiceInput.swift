import Foundation
import Speech
import AVFoundation
import os

/// Bridges audio buffers from the realtime tap thread to the recognizer, and
/// derives a smoothed input level (0…1) so the UI waveform can react to the
/// user's actual voice.
private final class BufferSink: @unchecked Sendable {
    private let request: SFSpeechAudioBufferRecognitionRequest
    /// Smoothed mic loudness, 0 (silent) … 1 (loud). Written on the realtime audio
    /// thread, read on the main thread — guarded by an unfair lock.
    private let levelState = OSAllocatedUnfairLock(initialState: 0.0)

    init(_ request: SFSpeechAudioBufferRecognitionRequest) { self.request = request }

    /// Current smoothed level, safe to read from any thread.
    var level: Double { levelState.withLock { $0 } }

    func append(_ buffer: AVAudioPCMBuffer) {
        request.append(buffer)
        updateLevel(from: buffer)
    }

    /// RMS → dB → normalised 0…1, with attack/decay smoothing so the bars glide.
    private func updateLevel(from buffer: AVAudioPCMBuffer) {
        guard let channel = buffer.floatChannelData?[0] else { return }
        let n = Int(buffer.frameLength)
        guard n > 0 else { return }
        var sum: Float = 0
        for i in 0..<n { let s = channel[i]; sum += s * s }
        let rms = sqrt(sum / Float(n))
        let db = rms > 0 ? 20 * log10(rms) : -80
        // Map a generous speech window (−58…−15 dB) onto 0…1, then a gamma lift
        // (^0.6) so ordinary, quiet speech already drives the bars well up — the
        // waveform should feel lively, not only spike on shouts.
        let linear = min(1, max(0, (Double(db) + 55) / 42))
        let norm = pow(linear, 0.55)
        levelState.withLock { state in
            let k = norm > state ? 0.32 : 0.16
            state += (norm - state) * k
        }
    }
}

/// On-device speech-to-text so the user can *talk* to Cloe instead of typing.
/// Streams a live transcript that the input bar binds into the message field.
@Observable
@MainActor
final class VoiceInput {
    private let recognizer = SFSpeechRecognizer()
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    private(set) var isRecording = false
    /// Latest transcript. The view mirrors this into the text field while recording.
    private(set) var transcript = ""

    /// Holds the live mic-level source while recording; nil when idle.
    private var sink: BufferSink?
    /// Smoothed mic loudness, 0…1. Read live by the waveform each frame (not an
    /// `@Observable` property — the view's `TimelineView` polls it). 0 when idle.
    var audioLevel: CGFloat { CGFloat(sink?.level ?? 0) }

    /// Fired once when recording auto-stops after a silence gap — the view uses this
    /// to auto-send the transcript so the user can just talk and stop, hands-free.
    var onAutoSubmit: (() -> Void)?
    /// Quiet gap after the last recognized speech before we auto-stop + submit.
    var silenceInterval: TimeInterval = 0.8
    private var silenceTimer: Timer?

    /// True between `startHold()` and `endHold()` — i.e. the user is physically holding
    /// the mic button. In this mode the quiet-gap auto-stop is disabled; the release
    /// ends the turn, so a pause mid-sentence doesn't cut the user off.
    private var holdMode = false

    var isAvailable: Bool { recognizer?.isAvailable ?? false }

    init() { prewarm() }

    /// Lock in a record-capable session category and materialise the input node's
    /// hardware format once, up front. Without this the very first cold STT start
    /// reads a stale 0ch/0Hz format and `installTap` throws an uncatchable ObjC
    /// exception → crash. Prewarming means no TTS warm-up is needed first.
    private func prewarm() {
        let session = AVAudioSession.sharedInstance()
        // Briefly adopt a record-capable category — long enough to materialise the
        // input node's hardware format — then hand the session back. `.mixWithOthers`
        // means this never interrupts the user's music, and the revert means an idle
        // app doesn't hold the mic / keep other audio ducked while we're not recording.
        try? session.setCategory(.playAndRecord, mode: .measurement,
                                 options: [.duckOthers, .defaultToSpeaker, .mixWithOthers])
        _ = engine.inputNode.outputFormat(forBus: 0)
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.mixWithOthers])
    }

    func toggle() {
        if isRecording { stop() } else { requestAndStart() }
    }

    // MARK: - Push-to-talk

    /// Finger went down on the mic button: start recording with no quiet-gap auto-stop.
    func startHold() {
        guard !holdMode else { return }
        holdMode = true
        requestAndStart(hold: true)
    }

    /// Finger lifted: end the turn and submit whatever was transcribed.
    func endHold() {
        guard holdMode else { return }
        holdMode = false
        guard isRecording else { return } // released before start landed → nothing to send
        stop()
        onAutoSubmit?()
    }

    // MARK: - Permissions → start

    private func requestAndStart(hold: Bool = false) {
        // The permission callbacks fire on a background queue. Keep their closures
        // `nonisolated` (via these static wrappers) so the Swift runtime doesn't run
        // a main-executor isolation check on a background thread → `dispatch_assert_queue`
        // trap → crash. We hop to `start()` once, explicitly, after both grants.
        Task {
            guard await Self.speechAuthorized(),
                  await Self.recordPermissionGranted() else { return }
            // The user may have released during the permission/await window — don't
            // start a recording nobody is holding.
            if hold && !self.holdMode { return }
            self.start() // requestAndStart is @MainActor → Task body resumes on main
        }
    }

    private nonisolated static func speechAuthorized() async -> Bool {
        await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0 == .authorized) }
        }
    }

    private nonisolated static func recordPermissionGranted() async -> Bool {
        await withCheckedContinuation { cont in
            AVAudioApplication.requestRecordPermission { cont.resume(returning: $0) }
        }
    }

    private func start() {
        guard let recognizer, recognizer.isAvailable, !isRecording else { return }
        task?.cancel()
        task = nil
        transcript = ""

        // `.playAndRecord` (not `.record`) so the input node stays valid even after
        // TTS left the session in `.playback`; otherwise the cached input format goes
        // to 0ch/0Hz and `installTap` throws an uncatchable ObjC exception → crash.
        // `.mixWithOthers` so the user's music keeps playing (ducked) instead of being
        // stopped while they talk to Cloe.
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .measurement,
                                 options: [.duckOthers, .defaultToSpeaker, .mixWithOthers])
        try? session.setActive(true, options: .notifyOthersOnDeactivation)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        self.request = request

        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        // Last line of defence: never hand `installTap` an invalid format.
        guard format.channelCount > 0, format.sampleRate > 0 else {
            cleanupAudio()
            self.request = nil
            return
        }
        // The tap runs on the realtime audio thread. Feed the recognizer through a
        // Sendable box so the capture is legal whether or not the SDK marks the tap
        // block `@Sendable`. Appending to the request from this thread is Apple's
        // documented pattern.
        let sink = BufferSink(request)
        self.sink = sink
        // `@Sendable` keeps this block nonisolated. Without it the closure inherits the
        // class's `@MainActor` isolation, and the realtime audio thread that drives the
        // tap fails the Swift 6 executor check → `dispatch_assert_queue` trap → crash.
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { @Sendable buffer, _ in
            sink.append(buffer)
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            cleanupAudio()
            return
        }
        isRecording = true

        // Same reason as the tap: `@Sendable` so Speech's background queue doesn't trip
        // the main-executor isolation check. We hop to the main actor inside.
        task = recognizer.recognitionTask(with: request) { @Sendable [weak self] result, error in
            // Extract Sendable value types here (on Speech's queue); `result` itself is
            // non-Sendable and must not cross into the main-actor hop.
            let text = result?.bestTranscription.formattedString
            let done = error != nil || (result?.isFinal ?? false)
            Task { @MainActor in
                guard let self else { return }
                if let text { self.transcript = text }
                if done {
                    self.stop()
                } else if text?.isEmpty == false {
                    // New speech recognized — restart the quiet-gap countdown.
                    self.scheduleSilenceTimer()
                }
            }
        }
    }

    /// (Re)arm the quiet-gap countdown. Each new recognized phrase restarts it; if it
    /// fires the user has gone silent → stop recording and let the view auto-submit.
    private func scheduleSilenceTimer() {
        guard !holdMode else { return } // release, not silence, ends a held turn
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: silenceInterval,
                                            repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isRecording else { return }
                self.stop()
                self.onAutoSubmit?()
            }
        }
    }

    func stop() {
        guard isRecording else { return }
        silenceTimer?.invalidate()
        silenceTimer = nil
        cleanupAudio()
        request?.endAudio()
        task?.finish()
        request = nil
        task = nil
        sink = nil
        isRecording = false
    }

    private func cleanupAudio() {
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
