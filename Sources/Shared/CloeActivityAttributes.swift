import ActivityKit

/// Live Activity payload shared between the app (which starts/updates the activity)
/// and the `CloeWidgets` extension (which renders it). Lives in `Sources/Shared`
/// so both targets compile the same definition.
struct CloeActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var phase: Phase
        /// Snippet of the most recent reply (shown while/after `replying`); empty otherwise.
        var snippet: String

        enum Phase: String, Codable, Hashable {
            case idle      // launcher: "Ask Cloe"
            case thinking  // a reply is generating
            case replying  // shows the latest answer
        }

        /// Single source of truth for the headline both the Lock Screen and the
        /// (required-but-stubbed) Dynamic Island presentations render.
        var headline: String {
            switch phase {
            case .idle: return "Ask Cloe"
            case .thinking: return "Thinking…"
            case .replying: return snippet.isEmpty ? "Tap to continue" : snippet
            }
        }
    }

    /// Static activity name, set once at request time.
    var label: String
}
