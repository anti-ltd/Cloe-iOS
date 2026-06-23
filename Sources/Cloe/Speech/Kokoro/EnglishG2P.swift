import Foundation

/// Dictionary-driven English grapheme→phoneme conversion, App Store-clean (no GPL
/// espeak-ng). Looks words up in misaki's Apache-2.0 pronunciation dictionaries
/// (`us_gold.json` / `gb_gold.json`, bundled under Resources/TTS), which are already
/// in Kokoro's exact IPA symbol set, so the output feeds `KokoroVocab.encode` directly.
///
/// Out-of-vocabulary words (rare names, typos, coined words) fall back to a crude
/// letter-sound spell-out — intelligible, not perfect. Homographs resolve to their
/// DEFAULT pronunciation (no POS tagging), so "read"/"lead"/"live" may pick the wrong
/// sense occasionally. Both are accepted tradeoffs for staying GPL-free.
struct EnglishG2P: Sendable {
    private let american: [String: String]
    private let british: [String: String]

    /// Loads the bundled dictionaries. Returns nil if the resources are missing
    /// (e.g. `make fetch-tts-assets` was never run) so the caller can fall back to
    /// the system voice rather than speak gibberish.
    init?() {
        guard let us = Self.loadDictionary(named: "us_gold") else { return nil }
        american = us
        // British is optional; American is a fine fallback if it's absent.
        british = Self.loadDictionary(named: "gb_gold") ?? us
    }

    func phonemes(for text: String, region: KokoroVoice.Region) -> String {
        let dict = region == .british ? british : american
        var out = ""
        for token in Self.tokenize(text) {
            switch token {
            case .word(let w):
                if !out.isEmpty && !out.hasSuffix(" ") { out.append(" ") }
                out.append(lookup(w, in: dict))
            case .number(let n):
                if !out.isEmpty && !out.hasSuffix(" ") { out.append(" ") }
                out.append(lookup(NumberWords.spell(n), in: dict, allowSpace: true))
            case .punct(let p):
                out.append(p)   // already a vocab symbol → prosodic pause
            }
        }
        return out
    }

    // MARK: - Lookup

    /// Resolve one word to phonemes, trying case variants before the OOV fallback.
    private func lookup(_ word: String, in dict: [String: String], allowSpace: Bool = false) -> String {
        if allowSpace {
            // A spelled-out number ("twenty one") — phonemize each part.
            return word.split(separator: " ")
                .map { lookup(String($0), in: dict) }
                .joined(separator: " ")
        }
        for key in [word, word.lowercased(), word.capitalized, word.uppercased()] {
            if let p = dict[key] { return p }
        }
        return Self.fallbackSpell(word)
    }

    // MARK: - Tokenizer

    private enum Token {
        case word(String)
        case number(Int)
        case punct(Character)
    }

    /// Punctuation that exists in Kokoro's vocab and shapes prosody.
    private static let keptPunct: Set<Character> = [",", ".", "!", "?", ";", ":"]

    private static func tokenize(_ text: String) -> [Token] {
        var tokens: [Token] = []
        var word = ""
        var number = ""

        func flushWord() {
            if !word.isEmpty { tokens.append(.word(word)); word = "" }
        }
        func flushNumber() {
            if !number.isEmpty {
                if let n = Int(number) { tokens.append(.number(n)) }
                else { tokens.append(.word(number)) }   // too big → read raw-ish
                number = ""
            }
        }

        for ch in text {
            if ch.isNumber {
                flushWord()
                number.append(ch)
            } else if ch.isLetter || ch == "'" || ch == "\u{2019}" {
                flushNumber()
                // normalise curly apostrophe so contraction keys match the dict
                word.append(ch == "\u{2019}" ? "'" : ch)
            } else {
                flushWord(); flushNumber()
                if keptPunct.contains(ch) { tokens.append(.punct(ch)) }
                // anything else (whitespace, brackets, symbols) just separates words
            }
        }
        flushWord(); flushNumber()
        return tokens
    }

    // MARK: - OOV fallback

    /// Naive English letter → IPA approximation for words missing from the dict.
    /// Crude but voiced rather than silent. Digraphs handled first.
    private static func fallbackSpell(_ word: String) -> String {
        let w = word.lowercased().filter { $0.isLetter }
        guard !w.isEmpty else { return "" }
        var result = ""
        let chars = Array(w)
        var i = 0
        while i < chars.count {
            // two-letter digraphs
            if i + 1 < chars.count {
                let pair = String(chars[i]) + String(chars[i + 1])
                if let ph = digraphs[pair] { result += ph; i += 2; continue }
            }
            result += singles[chars[i]] ?? ""
            i += 1
        }
        return result
    }

    private static let digraphs: [String: String] = [
        "ch": "ʧ", "sh": "ʃ", "th": "θ", "ph": "f", "wh": "w",
        "ck": "k", "ng": "ŋ", "qu": "kw", "oo": "u", "ee": "i",
        "ea": "i", "oa": "O", "ai": "A", "ay": "A", "ou": "W", "ow": "W",
    ]

    private static let singles: [Character: String] = [
        "a": "æ", "b": "b", "c": "k", "d": "d", "e": "ɛ", "f": "f",
        "g": "ɡ", "h": "h", "i": "ɪ", "j": "ʤ", "k": "k", "l": "l",
        "m": "m", "n": "n", "o": "ɑ", "p": "p", "q": "k", "r": "ɹ",
        "s": "s", "t": "t", "u": "ʌ", "v": "v", "w": "w", "x": "ks",
        "y": "j", "z": "z",
    ]

    // MARK: - Resource loading

    private static func loadDictionary(named name: String) -> [String: String]? {
        guard let url = bundledURL(name) ?? Bundle.main.url(forResource: name, withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        guard let decoded = try? JSONDecoder().decode([String: GoldEntry].self, from: data) else { return nil }
        var flat: [String: String] = [:]
        flat.reserveCapacity(decoded.count)
        for (word, entry) in decoded {
            if let p = entry.resolved { flat[word] = p }
        }
        return flat
    }

    private static func bundledURL(_ name: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: "json", subdirectory: "TTS")
    }

    /// Cheap presence check (no decode) so the main actor can decide availability
    /// before the heavy load runs off-thread.
    static var dictionariesAvailable: Bool {
        (bundledURL("us_gold") ?? Bundle.main.url(forResource: "us_gold", withExtension: "json")) != nil
    }

    /// A misaki dictionary value: either a plain IPA string, or an object keyed by
    /// part of speech (with a `DEFAULT`) for homographs. We collapse to one string.
    private struct GoldEntry: Decodable {
        let resolved: String?

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let s = try? container.decode(String.self) {
                resolved = s
            } else if let obj = try? container.decode([String: String?].self) {
                resolved = obj["DEFAULT"].flatMap { $0 }
                    ?? obj.values.compactMap { $0 }.first
            } else {
                resolved = nil   // null or unexpected shape
            }
        }
    }
}

/// Minimal integer → English words (0…999,999) so digits in replies are spoken
/// instead of dropped. Beyond the range, falls back to reading the digits.
enum NumberWords {
    private static let ones = ["zero","one","two","three","four","five","six","seven","eight","nine",
                               "ten","eleven","twelve","thirteen","fourteen","fifteen","sixteen",
                               "seventeen","eighteen","nineteen"]
    private static let tens = ["","","twenty","thirty","forty","fifty","sixty","seventy","eighty","ninety"]

    static func spell(_ n: Int) -> String {
        if n < 0 { return "minus " + spell(-n) }
        if n < 20 { return ones[n] }
        if n < 100 {
            let t = tens[n / 10]
            return n % 10 == 0 ? t : "\(t) \(ones[n % 10])"
        }
        if n < 1000 {
            let h = "\(ones[n / 100]) hundred"
            return n % 100 == 0 ? h : "\(h) \(spell(n % 100))"
        }
        if n < 1_000_000 {
            let th = "\(spell(n / 1000)) thousand"
            return n % 1000 == 0 ? th : "\(th) \(spell(n % 1000))"
        }
        return String(n).compactMap { $0.wholeNumberValue }.map { ones[$0] }.joined(separator: " ")
    }
}
