import Foundation

/// One Kokoro voice. The `id` is the HuggingFace voice-file stem (e.g. `af_heart`);
/// its style tensor lives at `voices/<id>.bin` in the ONNX repo. Prefix encodes
/// language + gender: `a`=American English, `b`=British English; `f`=female, `m`=male.
struct KokoroVoice: Identifiable, Hashable, Sendable {
    enum Region: String, Sendable {
        case american   // misaki us_gold dictionary
        case british    // misaki gb_gold dictionary
    }

    let id: String          // "af_heart"
    let name: String        // "Heart"
    let region: Region
    let isFemale: Bool

    /// Path of this voice's style file inside the ONNX repo, for the HF download.
    var remoteFile: String { "voices/\(id).bin" }

    var localeLabel: String { region == .american ? "American" : "British" }
    var genderLabel: String { isFemale ? "Female" : "Male" }
    var displayLabel: String { "\(name) · \(localeLabel) \(genderLabel)" }
}

/// Curated English voices (the `a*`/`b*` families). The model ships ~56 voices, but
/// only American/British English match our dictionary-based G2P; the rest target
/// other languages and would mispronounce English text.
enum KokoroVoiceCatalog {
    static let all: [KokoroVoice] = [
        // American — female
        .init(id: "af_heart",  name: "Heart",  region: .american, isFemale: true),
        .init(id: "af_bella",  name: "Bella",  region: .american, isFemale: true),
        .init(id: "af_nicole", name: "Nicole", region: .american, isFemale: true),
        .init(id: "af_aoede",  name: "Aoede",  region: .american, isFemale: true),
        .init(id: "af_kore",   name: "Kore",   region: .american, isFemale: true),
        .init(id: "af_sarah",  name: "Sarah",  region: .american, isFemale: true),
        .init(id: "af_nova",   name: "Nova",   region: .american, isFemale: true),
        .init(id: "af_sky",    name: "Sky",    region: .american, isFemale: true),
        // American — male
        .init(id: "am_michael", name: "Michael", region: .american, isFemale: false),
        .init(id: "am_fenrir",  name: "Fenrir",  region: .american, isFemale: false),
        .init(id: "am_puck",    name: "Puck",    region: .american, isFemale: false),
        .init(id: "am_echo",    name: "Echo",    region: .american, isFemale: false),
        .init(id: "am_eric",    name: "Eric",    region: .american, isFemale: false),
        .init(id: "am_liam",    name: "Liam",    region: .american, isFemale: false),
        .init(id: "am_onyx",    name: "Onyx",    region: .american, isFemale: false),
        .init(id: "am_adam",    name: "Adam",    region: .american, isFemale: false),
        // British — female
        .init(id: "bf_emma",     name: "Emma",     region: .british, isFemale: true),
        .init(id: "bf_isabella", name: "Isabella", region: .british, isFemale: true),
        .init(id: "bf_alice",    name: "Alice",    region: .british, isFemale: true),
        .init(id: "bf_lily",     name: "Lily",     region: .british, isFemale: true),
        // British — male
        .init(id: "bm_george",  name: "George",  region: .british, isFemale: false),
        .init(id: "bm_fable",   name: "Fable",   region: .british, isFemale: false),
        .init(id: "bm_daniel",  name: "Daniel",  region: .british, isFemale: false),
        .init(id: "bm_lewis",   name: "Lewis",   region: .british, isFemale: false),
    ]

    /// The default voice — warm American female, the model's reference voice.
    static let `default` = all[0]

    static func voice(id: String) -> KokoroVoice {
        all.first { $0.id == id } ?? `default`
    }
}
