import Foundation

/// Kokoro-82M's phoneme → token-id table, taken verbatim from the model's
/// `config.json` `vocab` (178 entries). The G2P emits IPA in *exactly* this symbol
/// set (misaki's inventory — note the compressed diphthong glyphs A I O Q S T W Y ᵊ),
/// so each character maps straight to an id. Unknown characters are dropped.
///
/// Token id 0 is the pad/boundary token: the model expects `[0, ids…, 0]`.
enum KokoroVocab {
    /// Phoneme character → integer id. Built once.
    static let table: [Character: Int] = {
        let pairs: [(String, Int)] = [
            (";", 1), (":", 2), (",", 3), (".", 4), ("!", 5), ("?", 6),
            ("—", 9), ("…", 10), ("\"", 11), ("(", 12), (")", 13),
            ("\u{201C}", 14), ("\u{201D}", 15), (" ", 16), ("\u{0303}", 17),
            ("ʣ", 18), ("ʥ", 19), ("ʦ", 20), ("ʨ", 21), ("ᵝ", 22), ("ꭧ", 23),
            ("A", 24), ("I", 25), ("O", 31), ("Q", 33), ("S", 35), ("T", 36),
            ("W", 39), ("Y", 41), ("ᵊ", 42),
            ("a", 43), ("b", 44), ("c", 45), ("d", 46), ("e", 47), ("f", 48),
            ("h", 50), ("i", 51), ("j", 52), ("k", 53), ("l", 54), ("m", 55),
            ("n", 56), ("o", 57), ("p", 58), ("q", 59), ("r", 60), ("s", 61),
            ("t", 62), ("u", 63), ("v", 64), ("w", 65), ("x", 66), ("y", 67),
            ("z", 68),
            ("ɑ", 69), ("ɐ", 70), ("ɒ", 71), ("æ", 72), ("β", 75), ("ɔ", 76),
            ("ɕ", 77), ("ç", 78), ("ɖ", 80), ("ð", 81), ("ʤ", 82), ("ə", 83),
            ("ɚ", 85), ("ɛ", 86), ("ɜ", 87), ("ɟ", 90), ("ɡ", 92), ("ɥ", 99),
            ("ɨ", 101), ("ɪ", 102), ("ʝ", 103), ("ɯ", 110), ("ɰ", 111),
            ("ŋ", 112), ("ɳ", 113), ("ɲ", 114), ("ɴ", 115), ("ø", 116),
            ("ɸ", 118), ("θ", 119), ("œ", 120), ("ɹ", 123), ("ɾ", 125),
            ("ɻ", 126), ("ʁ", 128), ("ɽ", 129), ("ʂ", 130), ("ʃ", 131),
            ("ʈ", 132), ("ʧ", 133), ("ʊ", 135), ("ʋ", 136), ("ʌ", 138),
            ("ɣ", 139), ("ɤ", 140), ("χ", 142), ("ʎ", 143), ("ʒ", 147),
            ("ʔ", 148), ("ˈ", 156), ("ˌ", 157), ("ː", 158), ("ʰ", 162),
            ("ʲ", 164), ("↓", 169), ("→", 171), ("↗", 172), ("↘", 173),
            ("ᵻ", 177),
        ]
        var map: [Character: Int] = [:]
        for (s, id) in pairs {
            if let ch = s.first { map[ch] = id }
        }
        return map
    }()

    /// Token id used both as the begin/end-of-sequence marker and as padding.
    static let boundary = 0

    /// Longest phoneme run the model accepts in one pass (excludes the two boundary
    /// tokens). Callers chunk text to stay under this.
    static let maxPhonemes = 510

    /// Encode an IPA phoneme string into model ids, skipping anything outside the
    /// vocab. Does **not** add the boundary tokens — the synthesiser wraps them.
    static func encode(_ phonemes: String) -> [Int] {
        phonemes.compactMap { table[$0] }
    }
}
