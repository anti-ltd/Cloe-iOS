import Foundation

/// One saved chat thread. Persisted locally so model/backend switches and app
/// relaunches no longer wipe history.
struct Conversation: Identifiable, Codable {
    let id: UUID
    var title: String
    var messages: [Message]
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String = "",
        messages: [Message] = [],
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.title = title
        self.messages = messages
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// First user line, trimmed for a list label. Empty until the user speaks.
    static func deriveTitle(from messages: [Message]) -> String {
        guard let first = messages.first(where: { $0.role == .user })?.content
            .trimmingCharacters(in: .whitespacesAndNewlines), !first.isEmpty
        else { return "" }
        return first.count > 50 ? String(first.prefix(50)) + "…" : first
    }
}

/// Codable + FileManager persistence into Application Support. A local-first step;
/// SwiftData+CloudKit sync is a possible follow-on (see ROADMAP item 3).
@MainActor
final class ConversationStore {
    /// Bump when the on-disk shape changes; `load` discards anything it can't decode.
    private let schemaVersion = 1
    private let url: URL

    private struct Payload: Codable {
        var version: Int
        var conversations: [Conversation]
    }

    init() {
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? URL.documentsDirectory
        let dir = base.appendingPathComponent("Cloe", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("conversations.json")
    }

    func load() -> [Conversation] {
        guard
            let data = try? Data(contentsOf: url),
            let payload = try? JSONDecoder().decode(Payload.self, from: data),
            payload.version == schemaVersion
        else { return [] }
        return payload.conversations
    }

    func save(_ conversations: [Conversation]) {
        let payload = Payload(version: schemaVersion, conversations: conversations)
        guard let data = try? JSONEncoder().encode(payload) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
