import AVFoundation
import Observation

/// Wraps `AVSpeechSynthesizer` so the UI can speak any message and track which
/// one is currently being read aloud. Lives for the app's lifetime (owned by
/// `AppModel`) so speech survives view rebuilds.
@Observable
@MainActor
final class SpeechService: NSObject, AVSpeechSynthesizerDelegate {
    private let synth = AVSpeechSynthesizer()

    /// The exact text currently being spoken, or `nil` when silent.
    /// Compared against a bubble's content so each row can show its own play/stop state.
    private(set) var speakingText: String?

    /// 0…1 normalised speaking rate, persisted in `UserDefaults`.
    var rate: Float {
        didSet { UserDefaults.standard.set(rate, forKey: "speechRate") }
    }

    /// BCP-47 voice language (e.g. "en-US"); empty string = system language.
    /// Kept for back-compat and as the language hint when no explicit voice is chosen.
    var voiceLanguage: String {
        didSet { UserDefaults.standard.set(voiceLanguage, forKey: "speechVoice") }
    }

    /// Stable identifier of an explicitly chosen `AVSpeechSynthesisVoice`
    /// (e.g. "com.apple.voice.premium.en-US.Zoe"). Empty = auto-pick best quality.
    var voiceIdentifier: String {
        didSet { UserDefaults.standard.set(voiceIdentifier, forKey: "speechVoiceID") }
    }

    /// Use the on-device Kokoro neural voice instead of the system AVSpeech voice.
    /// Turning it on kicks off the model download/prepare; speaking falls back to
    /// AVSpeech until Kokoro reports `.ready`.
    var useNeuralVoice: Bool {
        didSet {
            UserDefaults.standard.set(useNeuralVoice, forKey: "useNeuralVoice")
            if useNeuralVoice { prepareNeural() }
        }
    }

    /// Selected Kokoro voice id (e.g. "af_heart"). Re-prepares when changed.
    var neuralVoiceID: String {
        didSet {
            UserDefaults.standard.set(neuralVoiceID, forKey: "neuralVoiceID")
            if useNeuralVoice { prepareNeural() }
        }
    }

    /// On-device neural TTS engine (lazy download, ONNX inference). State is observable
    /// for the settings UI (download progress / ready / failed).
    let kokoro = KokoroTTS()

    var neuralVoice: KokoroVoice { KokoroVoiceCatalog.voice(id: neuralVoiceID) }

    var isSpeaking: Bool { speakingText != nil }

    override init() {
        let savedRate = UserDefaults.standard.object(forKey: "speechRate") as? Float
        rate = savedRate ?? AVSpeechUtteranceDefaultSpeechRate
        voiceLanguage = UserDefaults.standard.string(forKey: "speechVoice") ?? ""
        voiceIdentifier = UserDefaults.standard.string(forKey: "speechVoiceID") ?? ""
        useNeuralVoice = UserDefaults.standard.bool(forKey: "useNeuralVoice")
        neuralVoiceID = UserDefaults.standard.string(forKey: "neuralVoiceID")
            ?? KokoroVoiceCatalog.default.id
        super.init()
        synth.delegate = self
    }

    /// Download (if needed) + build the Kokoro session for the current voice.
    func prepareNeural() {
        Task { await kokoro.prepare(voice: neuralVoice) }
    }

    /// At launch, warm Kokoro only if it's enabled *and* already downloaded — never
    /// triggers a surprise network download.
    func prewarmNeuralIfEnabled() {
        guard useNeuralVoice else { return }
        kokoro.prewarm(voice: neuralVoice)
    }

    // MARK: - Streaming speech (speak sentences as a reply generates)

    private var streamingActive = false
    private var streamDispatched = ""   // text already handed to the engine

    /// True when replies can be spoken incrementally (neural voice, loaded). The system
    /// AVSpeech path stays one-shot (spoken once the reply completes).
    var canStreamSpeak: Bool { useNeuralVoice && kokoro.isReady }

    /// Begin speaking a reply that's still generating. Feed growing text via
    /// `streamAppend`, then call `endStreaming` when done.
    func beginStreaming() {
        stop()
        guard canStreamSpeak else { return }
        streamingActive = true
        streamDispatched = ""
        configureSession()
        kokoro.beginStreaming(voice: neuralVoice, rate: rate) { [weak self] in
            self?.speakingText = nil
        }
    }

    /// Hand the latest cumulative reply text in. Any newly-completed sentences are
    /// rendered and queued immediately; trailing partial text waits.
    func streamAppend(_ cumulativeText: String) {
        guard streamingActive else { return }
        speakingText = cumulativeText   // keep the bubble's play/stop state in sync

        guard cumulativeText.hasPrefix(streamDispatched) else { return }
        let tail = cumulativeText.dropFirst(streamDispatched.count)
        // First dispatch breaks on a clause (comma/colon/semicolon) too, so audio
        // starts on the opening phrase instead of waiting for the whole first sentence.
        let clause = streamDispatched.isEmpty
        guard let boundary = Self.lastBoundary(in: tail, clause: clause) else { return }

        let ready = String(tail[tail.startIndex..<boundary])
        streamDispatched += ready
        dispatchSpoken(ready)
    }

    /// Flush any trailing partial sentence and close the stream.
    func endStreaming(_ finalText: String) {
        guard streamingActive else { return }
        streamingActive = false
        speakingText = finalText

        if finalText.hasPrefix(streamDispatched) {
            let rest = String(finalText.dropFirst(streamDispatched.count))
            if !rest.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                streamDispatched = finalText
                dispatchSpoken(rest)
            }
        }
        kokoro.finishStreaming()
    }

    private func dispatchSpoken(_ text: String) {
        let spoken = SpeechService.strippingEmoji(text)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !spoken.isEmpty else { return }
        kokoro.enqueueStreaming(spoken)
    }

    /// Index just past the last break point, or nil if none yet. Always breaks on a
    /// sentence terminator (`.`/`!`/`?`/newline); when `clause` is true, also on a
    /// clause boundary (`,`/`;`/`:`) so the first phrase can be spoken sooner.
    private static func lastBoundary(in s: Substring, clause: Bool) -> String.Index? {
        var result: String.Index?
        var i = s.startIndex
        while i < s.endIndex {
            let c = s[i]
            let isTerminator = c == "." || c == "!" || c == "?" || c == "\n"
            let isClause = clause && (c == "," || c == ";" || c == ":")
            if isTerminator || isClause {
                result = s.index(after: i)
            }
            i = s.index(after: i)
        }
        return result
    }

    /// True when *this specific text* is the one being read aloud right now.
    func isSpeaking(_ text: String) -> Bool {
        speakingText == text
    }

    /// Play if silent (or a different message is playing); stop if this exact text is already playing.
    func toggle(_ text: String) {
        if speakingText == text {
            stop()
        } else {
            speak(text)
        }
    }

    func speak(_ text: String) {
        // Speak a de-emojified copy so the voice doesn't read "grinning face" etc.,
        // but keep `speakingText` as the original so bubbles still match for play/stop.
        let spoken = SpeechService.strippingEmoji(text)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !spoken.isEmpty else { return }

        if synth.isSpeaking {
            synth.stopSpeaking(at: .immediate)
        }
        kokoro.stop()
        configureSession()
        speakingText = text

        // Prefer the neural voice when enabled and loaded; otherwise AVSpeech.
        if useNeuralVoice, kokoro.isReady {
            kokoro.speak(spoken, voice: neuralVoice, rate: rate) { [weak self] in
                self?.speakingText = nil
            }
            return
        }

        let utterance = AVSpeechUtterance(string: spoken)
        utterance.rate = rate
        utterance.voice = resolvedVoice()
        synth.speak(utterance)
    }

    /// Drops emoji and their joiners/modifiers so TTS skips them rather than reading
    /// out their names. Leaves ASCII punctuation, digits and `# *` intact. Collapses
    /// whitespace left behind so removed emoji don't create awkward double pauses.
    static func strippingEmoji(_ text: String) -> String {
        var out = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            let p = scalar.properties
            let v = scalar.value
            let isEmojiLike =
                p.isEmojiPresentation ||              // emoji-by-default glyphs
                p.isEmojiModifier ||                  // skin-tone modifiers
                p.isEmojiModifierBase ||              // bases that take a modifier
                v == 0x200D ||                        // zero-width joiner
                v == 0x20E3 ||                        // combining enclosing keycap
                (0xFE00...0xFE0F).contains(v) ||      // variation selectors
                (0x1F1E6...0x1F1FF).contains(v) ||    // regional indicators (flags)
                (p.isEmoji && v > 0x2000)             // text-default symbols shown as emoji (❤, ☀, ✅…)
            if !isEmojiLike { out.append(scalar) }
        }
        var result = String(out)
        while result.contains("  ") {
            result = result.replacingOccurrences(of: "  ", with: " ")
        }
        return result
    }

    func stop() {
        if synth.isSpeaking {
            synth.stopSpeaking(at: .immediate)
        }
        kokoro.stop()
        streamingActive = false
        speakingText = nil
    }

    // MARK: - Voice selection

    /// The voice to speak with: an explicit pick if still installed, otherwise the
    /// highest-quality voice for the chosen/system language. Falls back to `nil`
    /// (system default) only when no match exists at all.
    private func resolvedVoice() -> AVSpeechSynthesisVoice? {
        if !voiceIdentifier.isEmpty,
           let v = AVSpeechSynthesisVoice(identifier: voiceIdentifier) {
            return v
        }
        return SpeechService.bestVoice(for: targetLanguage)
    }

    /// BCP-47 language to read in: explicit override, else the device's preferred language.
    private var targetLanguage: String {
        if !voiceLanguage.isEmpty { return voiceLanguage }
        return AVSpeechSynthesisVoice.currentLanguageCode()
    }

    /// Best installed voice for `language`, ranked premium → enhanced → compact.
    /// Matches the exact locale first ("en-US"), then any voice sharing the base
    /// language code ("en"). Returns `nil` if nothing installed for that language.
    static func bestVoice(for language: String) -> AVSpeechSynthesisVoice? {
        let base = language.split(separator: "-").first.map(String.init) ?? language
        let candidates = AVSpeechSynthesisVoice.speechVoices().filter {
            $0.language == language
                || $0.language.split(separator: "-").first.map(String.init) == base
        }
        // Prefer an exact locale match, then highest quality.
        return candidates.max { lhs, rhs in
            let exactL = lhs.language == language ? 1 : 0
            let exactR = rhs.language == language ? 1 : 0
            if exactL != exactR { return exactL < exactR }
            return lhs.quality.rank < rhs.quality.rank
        }
    }

    /// True when the best voice available for the current language is only Compact
    /// quality — i.e. no Enhanced/Premium installed. Drives the in-app download nudge.
    /// Re-reads installed voices each call, so it flips to `false` automatically once
    /// the user returns from Settings having downloaded a natural voice.
    var needsBetterVoice: Bool {
        guard let best = SpeechService.bestVoice(for: targetLanguage) else { return true }
        return best.quality.rank < AVSpeechSynthesisVoiceQuality.enhanced.rank
    }

    /// All installed voices, grouped by language and sorted best-first, for the picker.
    static func installedVoices() -> [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices().sorted { lhs, rhs in
            if lhs.language != rhs.language { return lhs.language < rhs.language }
            if lhs.quality.rank != rhs.quality.rank { return lhs.quality.rank > rhs.quality.rank }
            return lhs.name < rhs.name
        }
    }

    /// Duck other audio (music, podcasts) while Cloe talks rather than stopping it.
    private func configureSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers, .mixWithOthers])
        try? session.setActive(true)
    }

    // MARK: - AVSpeechSynthesizerDelegate (nonisolated → hop back to main)

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.speakingText = nil }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                       didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.speakingText = nil }
    }
}

private extension AVSpeechSynthesisVoiceQuality {
    /// Higher = better. `.premium` (iOS 16+) > `.enhanced` > `.default` (compact).
    var rank: Int {
        switch self {
        case .premium: return 3
        case .enhanced: return 2
        case .default: return 1
        @unknown default: return 0
        }
    }
}
