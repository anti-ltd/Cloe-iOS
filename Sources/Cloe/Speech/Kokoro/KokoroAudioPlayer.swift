import AVFoundation

/// Streaming playback of raw Float32 PCM (mono, 24 kHz — Kokoro's output) through an
/// `AVAudioEngine`. Buffers are scheduled as each sentence finishes rendering, so audio
/// starts after the first chunk instead of waiting for the whole reply. The node plays
/// queued buffers back-to-back; `onFinish` fires once the producer is done *and* every
/// scheduled buffer has played. A new session (or `stop`) cancels whatever's sounding.
@MainActor
final class KokoroAudioPlayer {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                       sampleRate: 24_000, channels: 1, interleaved: false)!

    /// Bumped on every begin/stop so a stale completion callback from a cancelled
    /// utterance can't advance counters or fire `onFinish`.
    private var generation = 0
    private var attached = false

    private var scheduled = 0
    private var completed = 0
    private var producerDone = false
    private var onFinish: (@MainActor () -> Void)?

    init() {}

    private func attachIfNeeded() {
        guard !attached else { return }
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        attached = true
    }

    /// Open a new playback session. Returns the session id callers must pass back to
    /// `enqueue`/`finishProducing` so a stale producer task can't feed a newer session.
    @discardableResult
    func begin(onFinish: @escaping @MainActor () -> Void) -> Int {
        stop()                       // cancel any prior session (bumps generation)
        self.onFinish = onFinish
        scheduled = 0
        completed = 0
        producerDone = false
        attachIfNeeded()
        try? engine.start()
        return generation
    }

    /// Append one chunk's samples to the play queue. Plays in scheduling order.
    /// Ignored if `session` is no longer the active one.
    func enqueue(_ samples: [Float], session: Int) {
        guard session == generation else { return }
        guard !samples.isEmpty,
              let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                            frameCapacity: AVAudioFrameCount(samples.count)) else { return }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { src in
            buffer.floatChannelData![0].update(from: src.baseAddress!, count: samples.count)
        }
        guard engine.isRunning else { return }

        let gen = generation
        scheduled += 1
        player.scheduleBuffer(buffer, at: nil, options: [],
                              completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor in self?.bufferCompleted(gen) }
        }
        if !player.isPlaying { player.play() }
    }

    /// Signal that no more chunks are coming. `onFinish` fires now if everything
    /// already played (e.g. all chunks were empty), otherwise after the last buffer.
    func finishProducing(session: Int) {
        guard session == generation else { return }
        producerDone = true
        checkDone(generation)
    }

    private func bufferCompleted(_ gen: Int) {
        guard gen == generation else { return }
        completed += 1
        checkDone(gen)
    }

    private func checkDone(_ gen: Int) {
        guard gen == generation, producerDone, completed >= scheduled else { return }
        let cb = onFinish
        onFinish = nil
        cb?()
    }

    /// Stop immediately and invalidate any pending completion callbacks.
    func stop() {
        generation += 1
        onFinish = nil
        scheduled = 0
        completed = 0
        producerDone = false
        if player.isPlaying { player.stop() }
        if engine.isRunning { engine.stop() }
    }
}
