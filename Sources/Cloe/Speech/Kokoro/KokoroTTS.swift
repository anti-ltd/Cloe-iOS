import Foundation
import Hub
import OnnxRuntimeBindings

/// On-device neural text-to-speech via Kokoro-82M (ONNX Runtime). App Store-clean:
/// model is Apache-2.0, runtime is MIT, phonemes come from the bundled misaki dicts
/// (no GPL espeak-ng). Weights download once from HuggingFace and cache offline,
/// mirroring `MLXBackend`.
///
/// State + playback live on the main actor; the actual inference runs on the
/// `KokoroSynth` actor so the model load and each render stay off the main thread.
@MainActor
@Observable
final class KokoroTTS {
    enum State: Equatable {
        case unavailable          // dictionaries missing — can't phonemize
        case idle                 // not downloaded yet
        case downloading(Double)
        case preparing            // building the ONNX session
        case ready
        case failed(String)
    }

    private(set) var state: State = .idle
    var isReady: Bool { state == .ready }

    private let player = KokoroAudioPlayer()
    private var synth: KokoroSynth?
    private var voiceURLs: [String: URL] = [:]   // voiceID → local style file
    private var loadedVoice: KokoroVoice?
    private var speakTask: Task<Void, Never>?

    // Streaming-speech session: render chunks arrive incrementally as the reply is
    // generated. `renderChain` serialises them so audio stays in order.
    private var streamSession: Int?
    private var streamVoice: KokoroVoice?
    private var streamSpeed: Float = 1
    private var renderChain: Task<Void, Never>?
    /// Guards `prepare()` against concurrent callers (launch prewarm + settings toggle
    /// + voice switch) double-downloading or double-building the session.
    private var isPreparing = false

    private let repo = "onnx-community/Kokoro-82M-v1.0-ONNX"
    private let modelFile = "onnx/model_q8f16.onnx"   // 86 MB int8/fp16 mix — best size/quality

    // Same Application Support base as MLXBackend so models survive updates.
    private static var downloadBase: URL {
        let fm = FileManager.default
        let dir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Local snapshot dir HubApi writes to: {base}/models/{repo}.
    private var snapshotDir: URL {
        Self.downloadBase.appendingPathComponent("models").appendingPathComponent(repo)
    }

    private func localModelURL() -> URL? {
        let url = snapshotDir.appendingPathComponent(modelFile)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private func localVoiceURL(_ voice: KokoroVoice) -> URL? {
        let url = snapshotDir.appendingPathComponent(voice.remoteFile)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// True once the model file is on disk — drives the launch auto-prepare and the
    /// "downloaded" badge in settings without hitting the network.
    var isDownloaded: Bool { localModelURL() != nil }

    // MARK: - Setup

    /// Download (if needed) and build the ONNX session for `voice`. Cheap when the
    /// model is already cached and the session is already built for this voice.
    func prepare(voice: KokoroVoice) async {
        // Need the dictionaries to phonemize at all (cheap file check; the heavy
        // decode happens on the synth actor, off the main thread).
        guard EnglishG2P.dictionariesAvailable else { state = .unavailable; return }

        // Already ready for this exact voice — nothing to do.
        if isReady, loadedVoice?.id == voice.id { return }

        // One prepare at a time — a concurrent caller just waits this one out.
        guard !isPreparing else { return }
        isPreparing = true
        defer { isPreparing = false }

        // Fetch model + the chosen voice file.
        do {
            let (modelURL, voiceURL) = try await fetch(voice: voice)
            voiceURLs[voice.id] = voiceURL

            if synth == nil {
                state = .preparing
                let s = KokoroSynth(modelPath: modelURL.path)
                try await s.load()
                synth = s
            }
            loadedVoice = voice
            state = .ready
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// Ensure model + voice files are local, downloading what's missing. Tries the
    /// cache first (offline) so a network blip can't fail an already-downloaded model.
    private func fetch(voice: KokoroVoice) async throws -> (model: URL, voice: URL) {
        if let m = localModelURL(), let v = localVoiceURL(voice) {
            return (m, v)
        }
        state = .downloading(0)
        let hub = HubApi(downloadBase: Self.downloadBase)
        let repoRef = Hub.Repo(id: repo)
        _ = try await hub.snapshot(from: repoRef, matching: [modelFile, voice.remoteFile]) { @Sendable [weak self] progress in
            let fraction = progress.fractionCompleted
            Task { @MainActor in self?.state = .downloading(fraction) }
        }
        guard let m = localModelURL(), let v = localVoiceURL(voice) else {
            throw KokoroError.downloadIncomplete
        }
        return (m, v)
    }

    /// Kick off prepare at launch only if the model is already downloaded — no
    /// surprise cellular downloads. Mirrors `MLXBackend.prewarm()`.
    func prewarm(voice: KokoroVoice) {
        guard isDownloaded, case .idle = state else { return }
        Task { await prepare(voice: voice) }
    }

    // MARK: - Speak

    /// Synthesise `text` with `voice` and play it. `rate` is the app's 0…1 speech
    /// rate; `onFinish` fires on the main actor when playback ends or is skipped.
    func speak(_ text: String, voice: KokoroVoice, rate: Float, onFinish: @escaping @MainActor () -> Void) {
        guard let synth, let voiceURL = voiceURLs[voice.id] else { onFinish(); return }
        speakTask?.cancel()
        let speed = Self.speed(forRate: rate)

        // Split up front, then render + play each chunk as it's ready so audio starts
        // after the first sentence instead of the whole reply.
        let chunks = KokoroSynth.splitChunks(text)
        guard !chunks.isEmpty else { onFinish(); return }

        let session = player.begin(onFinish: onFinish)
        let region = voice.region
        let voiceID = voice.id

        speakTask = Task {
            for chunk in chunks {
                if Task.isCancelled { return }   // a newer session / stop took over
                do {
                    let pcm = try await synth.renderChunk(chunk,
                                                          region: region,
                                                          voiceURL: voiceURL,
                                                          voiceID: voiceID,
                                                          speed: speed)
                    if Task.isCancelled { return }
                    player.enqueue(pcm, session: session)
                } catch {
                    continue   // skip a bad chunk, keep speaking the rest
                }
            }
            if !Task.isCancelled { player.finishProducing(session: session) }
        }
    }

    func stop() {
        speakTask?.cancel()
        speakTask = nil
        renderChain?.cancel()
        renderChain = nil
        streamSession = nil
        streamVoice = nil
        player.stop()
    }

    // MARK: - Streaming speak (sentence-by-sentence as the reply generates)

    /// Open a streaming session: audio plays as sentences are fed in via
    /// `enqueueStreaming`, ending when `finishStreaming` is called.
    func beginStreaming(voice: KokoroVoice, rate: Float, onFinish: @escaping @MainActor () -> Void) {
        guard voiceURLs[voice.id] != nil else { onFinish(); return }
        speakTask?.cancel()
        renderChain?.cancel()
        renderChain = nil
        streamVoice = voice
        streamSpeed = Self.speed(forRate: rate)
        streamSession = player.begin(onFinish: onFinish)
    }

    /// Render `text` (one or more freshly-completed sentences) and append it to the
    /// stream. Renders chain off the previous one so playback order is preserved.
    func enqueueStreaming(_ text: String) {
        guard let synth, let voice = streamVoice, let session = streamSession,
              let voiceURL = voiceURLs[voice.id] else { return }
        let chunks = KokoroSynth.splitChunks(text)
        guard !chunks.isEmpty else { return }
        let speed = streamSpeed
        let region = voice.region
        let voiceID = voice.id
        let previous = renderChain

        renderChain = Task {
            await previous?.value
            for chunk in chunks {
                if Task.isCancelled { return }
                if let pcm = try? await synth.renderChunk(chunk, region: region,
                                                          voiceURL: voiceURL,
                                                          voiceID: voiceID, speed: speed) {
                    if Task.isCancelled { return }
                    player.enqueue(pcm, session: session)
                }
            }
        }
    }

    /// No more sentences are coming. Fires the session's `onFinish` after the last
    /// queued render has played.
    func finishStreaming() {
        guard let session = streamSession else { return }
        let chain = renderChain
        Task {
            await chain?.value
            player.finishProducing(session: session)
        }
    }

    /// Map the app's 0…1 rate onto Kokoro's speed multiplier (1.0 = natural).
    private static func speed(forRate rate: Float) -> Float {
        // ~0.5 default → ~1.05; clamp to a sane range.
        min(1.4, max(0.7, 0.7 + rate * 0.7))
    }

    enum KokoroError: LocalizedError {
        case downloadIncomplete
        case dictionariesMissing
        var errorDescription: String? {
            switch self {
            case .downloadIncomplete: return "Voice download didn't complete."
            case .dictionariesMissing: return "Pronunciation data missing."
            }
        }
    }
}

// MARK: - Inference actor (off the main thread)

/// Owns the ONNX Runtime session and renders text → 24 kHz mono PCM. An actor so the
/// non-Sendable ORT objects stay isolated and the heavy work never touches main.
actor KokoroSynth {
    private let modelPath: String
    private var g2p: EnglishG2P?

    private var env: ORTEnv?
    private var session: ORTSession?
    private var outputName = ""
    private var styleCache: [String: [Float]] = [:]   // voiceID → full (510×256) table

    /// Phonemes per chunk. Well under the model's 510 cap to bound latency/memory.
    private static let chunkPhonemeLimit = 400

    init(modelPath: String) {
        self.modelPath = modelPath
    }

    /// Load the dictionaries and build the ORT session. Heavy (5 MB JSON decode +
    /// model load) — runs on the actor executor, not main.
    func load() throws {
        guard let g2p = EnglishG2P() else { throw KokoroTTS.KokoroError.dictionariesMissing }
        self.g2p = g2p

        let env = try ORTEnv(loggingLevel: ORTLoggingLevel.warning)
        let options = try ORTSessionOptions()
        let session = try ORTSession(env: env, modelPath: modelPath, sessionOptions: options)
        self.env = env
        self.session = session
        // Kokoro has a single output; resolve its name rather than hardcoding.
        self.outputName = try session.outputNames().first ?? "waveform"

        // Warm the graph with a throwaway inference so the user's first real sentence
        // doesn't pay ONNX Runtime's cold-start (allocation + graph optimisation).
        let warmTokens: [Int64] = [0, 50, 56, 16, 50, 0]
        let warmStyle = [Float](repeating: 0, count: 256)
        _ = try? run(session: session, tokens: warmTokens, style: warmStyle, speed: 1.0)
    }

    /// Render one already-split chunk to PCM. Returns `[]` for a chunk that produced
    /// no recognisable phonemes (caller just skips it).
    func renderChunk(_ chunk: String, region: KokoroVoice.Region, voiceURL: URL,
                     voiceID: String, speed: Float) throws -> [Float] {
        guard let session, let g2p else { throw KokoroTTS.KokoroError.downloadIncomplete }
        let style = try styleTable(voiceID: voiceID, url: voiceURL)

        let phonemes = g2p.phonemes(for: chunk, region: region)
        var ids = KokoroVocab.encode(phonemes)
        guard !ids.isEmpty else { return [] }
        if ids.count > KokoroVocab.maxPhonemes {
            ids = Array(ids.prefix(KokoroVocab.maxPhonemes))
        }

        let styleRow = styleVector(from: style, phonemeCount: ids.count)
        let tokens: [Int64] = [Int64(KokoroVocab.boundary)]
            + ids.map(Int64.init)
            + [Int64(KokoroVocab.boundary)]

        let samples = try run(session: session, tokens: tokens, style: styleRow, speed: speed)
        // Replace the model's uneven end-tail with a deterministic, punctuation-keyed pause.
        return KokoroSynth.trimSilence(samples)
            + [Float](repeating: 0, count: KokoroSynth.trailingPauseSamples(for: chunk))
    }

    // MARK: ONNX call

    private func run(session: ORTSession, tokens: [Int64], style: [Float], speed: Float) throws -> [Float] {
        let idsValue = try tensor(int64: tokens, shape: [1, NSNumber(value: tokens.count)])
        let styleValue = try tensor(float: style, shape: [1, 256])
        let speedValue = try tensor(float: [speed], shape: [1])

        let outputs = try session.run(
            withInputs: ["input_ids": idsValue, "style": styleValue, "speed": speedValue],
            outputNames: [outputName],
            runOptions: nil)

        guard let out = outputs[outputName] else { return [] }
        let data = try out.tensorData() as Data
        return data.withUnsafeBytes { raw in
            Array(raw.bindMemory(to: Float.self))
        }
    }

    private func tensor(float values: [Float], shape: [NSNumber]) throws -> ORTValue {
        let data = NSMutableData(bytes: values, length: values.count * MemoryLayout<Float>.stride)
        return try ORTValue(tensorData: data, elementType: .float, shape: shape)
    }

    private func tensor(int64 values: [Int64], shape: [NSNumber]) throws -> ORTValue {
        let data = NSMutableData(bytes: values, length: values.count * MemoryLayout<Int64>.stride)
        return try ORTValue(tensorData: data, elementType: .int64, shape: shape)
    }

    // MARK: Style + chunking

    /// Load and cache a voice's full style table: 510 rows × 256 floats, flat.
    private func styleTable(voiceID: String, url: URL) throws -> [Float] {
        if let cached = styleCache[voiceID] { return cached }
        let data = try Data(contentsOf: url)
        let floats = data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        styleCache[voiceID] = floats
        return floats
    }

    /// Kokoro indexes the style table by phoneme count: `voice[len(phonemes)]`.
    private func styleVector(from table: [Float], phonemeCount: Int) -> [Float] {
        let rows = table.count / 256
        guard rows > 0 else { return [Float](repeating: 0, count: 256) }
        let row = min(max(phonemeCount, 0), rows - 1)
        let start = row * 256
        return Array(table[start ..< start + 256])
    }

    /// Punctuation pauses, in seconds — TUNE HERE. We trim the model's own (uneven)
    /// end-silence and insert these instead, so every period/!/? gets the same beat and
    /// every comma/dash/colon gets the same (shorter) one, regardless of how Kokoro
    /// happened to voice them.
    static let sentencePause = 0.30   // . ! ?
    static let clausePause   = 0.20   // , ; : — –
    static let defaultPause  = 0.10   // wrapped fragment with no trailing punctuation
    private static let sampleRate = 24_000

    /// Break text into render units — one per sentence *and* per clause — so each
    /// punctuation mark becomes a chunk boundary we can pause after deterministically.
    /// A mark only counts as a boundary when followed by whitespace/end, so "3:30" and
    /// "1,000" don't split. Pure + static so the main actor can split before the synth.
    static func splitChunks(_ text: String) -> [String] {
        let norm = text.replacingOccurrences(of: "--", with: "—")
        let terminators: Set<Character> = [".", "!", "?", "\n"]
        let clauses: Set<Character> = [",", ";", ":", "—", "–"]
        let chars = Array(norm)

        var units: [String] = []
        var current = ""
        func flush() {
            let t = current.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { units.append(t) }
            current = ""
        }
        for (i, c) in chars.enumerated() {
            current.append(c)
            guard terminators.contains(c) || clauses.contains(c) else { continue }
            let next: Character = i + 1 < chars.count ? chars[i + 1] : " "
            if c == "\n" || next.isWhitespace { flush() }   // not mid-token (e.g. 3:30)
        }
        flush()

        // Hard word-wrap any single unit past the phoneme budget.
        let wordCap = chunkPhonemeLimit / 3
        return units.flatMap { unit -> [String] in
            let words = unit.split(separator: " ")
            guard words.count > wordCap else { return [unit] }
            return stride(from: 0, to: words.count, by: wordCap).map {
                words[$0 ..< min($0 + wordCap, words.count)].joined(separator: " ")
            }
        }
    }

    /// Samples of trailing silence to append after a chunk, chosen by its final
    /// punctuation so pauses are uniform per punctuation type.
    static func trailingPauseSamples(for chunk: String) -> Int {
        let last = chunk.reversed().first { !$0.isWhitespace }
        let seconds: Double
        switch last {
        case ".", "!", "?":           seconds = sentencePause
        case ",", ";", ":", "—", "–": seconds = clausePause
        default:                      seconds = defaultPause
        }
        return Int(Double(sampleRate) * seconds)
    }

    /// Trim near-silent samples from both ends so the model's own variable end-tail is
    /// removed; the caller appends a deterministic pause instead. Tiny pads avoid
    /// clipping the onset/last phoneme.
    static func trimSilence(_ samples: [Float]) -> [Float] {
        let threshold: Float = 0.005
        var end = samples.count
        while end > 0 && abs(samples[end - 1]) < threshold { end -= 1 }
        var start = 0
        while start < end && abs(samples[start]) < threshold { start += 1 }
        guard start < end else { return [] }
        let lead = max(0, start - 240)          // ~10 ms onset pad
        let tail = min(samples.count, end + 120) // ~5 ms tail pad
        return Array(samples[lead ..< tail])
    }
}
