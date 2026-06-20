import Foundation

/// Cross-app bridge to the sibling **Clink** keyboard's clipboard manager and
/// notepad/scratchpad. Clink exposes no URL scheme or App Intent — both apps just
/// share the App Group `group.ltd.anti.clink` and read/write the same JSON files.
///
/// The models below MIRROR Clink's `ClipboardEntry` / `NotepadNote` exactly (field
/// names, types, and the plain `JSONEncoder()`/`JSONDecoder()` with default date
/// strategy) so the files stay byte-compatible in both directions. If Clink ever
/// changes its schema, update these to match.
enum ClinkStore {
    static let appGroupID = "group.ltd.anti.clink"
    private static let clipboardFile = "clink-clipboard.v2.json"
    private static let notepadFile = "clink-notepad.v1.json"
    private static let maxClips = 20      // unpinned cap, mirrors ClipboardManager
    private static let maxNotes = 50      // mirrors NotepadManager

    // MARK: - Models (mirror Clink/ClinkKit)

    struct Clip: Codable, Equatable {
        enum Kind: String, Codable { case text, image }
        var kind: Kind
        var text: String
        var imageFile: String?
        var imageUTType: String?
        var imageHash: String?
        var date: Date
        var pinned: Bool

        init(text: String, date: Date = .now, pinned: Bool = false) {
            self.kind = .text
            self.text = text
            self.date = date
            self.pinned = pinned
        }

        // Lenient decode, matching Clink's own (older/partial entries still load).
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            kind = try c.decodeIfPresent(Kind.self, forKey: .kind) ?? .text
            text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
            imageFile = try c.decodeIfPresent(String.self, forKey: .imageFile)
            imageUTType = try c.decodeIfPresent(String.self, forKey: .imageUTType)
            imageHash = try c.decodeIfPresent(String.self, forKey: .imageHash)
            date = try c.decodeIfPresent(Date.self, forKey: .date) ?? .now
            pinned = try c.decodeIfPresent(Bool.self, forKey: .pinned) ?? false
        }

        var displayText: String { kind == .image ? "🖼 image" : text }
    }

    struct Note: Codable, Equatable, Identifiable {
        var id: UUID = UUID()
        var text: String
        var date: Date = .now
    }

    private struct NotepadPayload: Codable {
        var scratch: String
        var notes: [Note]
    }

    // MARK: - Paths

    private static func url(_ name: String) -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent(name)
    }

    // MARK: - Clipboard

    static func clips() -> [Clip] {
        guard let u = url(clipboardFile), let data = try? Data(contentsOf: u),
              let arr = try? JSONDecoder().decode([Clip].self, from: data) else { return [] }
        return arr
    }

    /// Add a text clip to the front, de-duping on exact text and trimming the
    /// unpinned tail — the same rules ClipboardManager applies.
    @discardableResult
    static func addClip(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let u = url(clipboardFile) else { return false }
        var arr = clips()
        arr.removeAll { $0.kind == .text && $0.text == trimmed }
        arr.insert(Clip(text: trimmed), at: 0)
        let pinned = arr.filter(\.pinned)
        let unpinned = Array(arr.filter { !$0.pinned }.prefix(maxClips))
        arr = pinned + unpinned
        guard let data = try? JSONEncoder().encode(arr) else { return false }
        return (try? data.write(to: u, options: .atomic)) != nil
    }

    // MARK: - Scratchpad / notepad

    private static func notepad() -> NotepadPayload {
        guard let u = url(notepadFile), let data = try? Data(contentsOf: u),
              let payload = try? JSONDecoder().decode(NotepadPayload.self, from: data) else {
            return NotepadPayload(scratch: "", notes: [])
        }
        return payload
    }

    /// Save text as a new note at the front of the scratchpad archive (cap 50),
    /// leaving the live compose buffer untouched.
    @discardableResult
    static func addNote(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let u = url(notepadFile) else { return false }
        var payload = notepad()
        payload.notes.insert(Note(text: trimmed), at: 0)
        if payload.notes.count > maxNotes { payload.notes = Array(payload.notes.prefix(maxNotes)) }
        guard let data = try? JSONEncoder().encode(payload) else { return false }
        return (try? data.write(to: u, options: .atomic)) != nil
    }

    // MARK: - Retrieval (deterministic answer)

    /// True when Cloe can actually reach the shared App Group container. False
    /// means the entitlement / group link is missing (or Clink isn't installed).
    static var hasAppGroupAccess: Bool {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) != nil
    }

    /// If the user is asking about their Clink clipboard or scratchpad, build the
    /// answer DIRECTLY from the shared store and return it — no model generation, so
    /// the data always shows. nil when it isn't a retrieval question.
    static func retrievalReply(for userText: String) -> String? {
        let t = userText.lowercased()
        let wantsClip = t.contains("clipboard") || t.contains("copied")
            || t.contains("what did i copy") || t.contains("copy history")
        let wantsScratch = t.contains("scratchpad") || t.contains("scratch pad")
            || t.contains("notepad") || t.contains("scratch note")
        guard wantsClip || wantsScratch else { return nil }

        guard hasAppGroupAccess else {
            return "I can't reach Clink's storage yet — check that Clink is installed and Cloe shares its app group."
        }

        var parts: [String] = []
        if wantsClip {
            let items = clips()
            if items.isEmpty {
                parts.append("Your Clink clipboard is empty right now.")
            } else {
                let list = items.prefix(8).enumerated()
                    .map { "\($0.offset + 1). \(snippet($0.element.displayText))" }
                    .joined(separator: "\n")
                parts.append("Here's what's on your Clink clipboard:\n\(list)")
            }
        }
        if wantsScratch {
            let pad = notepad()
            var lines: [String] = []
            if !pad.scratch.isEmpty { lines.append("Current draft: \"\(snippet(pad.scratch))\"") }
            if !pad.notes.isEmpty {
                let notes = pad.notes.prefix(8).enumerated()
                    .map { "\($0.offset + 1). \(snippet($0.element.text))" }
                    .joined(separator: "\n")
                lines.append("Saved notes:\n\(notes)")
            }
            parts.append(lines.isEmpty
                ? "Your Clink scratchpad is empty."
                : "Here's your Clink scratchpad:\n" + lines.joined(separator: "\n"))
        }
        return parts.joined(separator: "\n\n")
    }

    private static func snippet(_ s: String, _ limit: Int = 140) -> String {
        let oneLine = s.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return oneLine.count > limit ? String(oneLine.prefix(limit)) + "…" : oneLine
    }
}
