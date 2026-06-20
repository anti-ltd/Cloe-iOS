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

    /// BCP-47 voice language (e.g. "en-US"); empty string = system default.
    var voiceLanguage: String {
        didSet { UserDefaults.standard.set(voiceLanguage, forKey: "speechVoice") }
    }

    var isSpeaking: Bool { speakingText != nil }

    override init() {
        let savedRate = UserDefaults.standard.object(forKey: "speechRate") as? Float
        rate = savedRate ?? AVSpeechUtteranceDefaultSpeechRate
        voiceLanguage = UserDefaults.standard.string(forKey: "speechVoice") ?? ""
        super.init()
        synth.delegate = self
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
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if synth.isSpeaking {
            synth.stopSpeaking(at: .immediate)
        }
        configureSession()

        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.rate = rate
        if !voiceLanguage.isEmpty {
            utterance.voice = AVSpeechSynthesisVoice(language: voiceLanguage)
        }
        synth.speak(utterance)
        speakingText = text
    }

    func stop() {
        if synth.isSpeaking {
            synth.stopSpeaking(at: .immediate)
        }
        speakingText = nil
    }

    /// Duck other audio (music, podcasts) while Cloe talks rather than stopping it.
    private func configureSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
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
