import Foundation
import FoundationModels

@available(iOS 26.0, *)
final class FoundationModelsBackend: AIBackend, @unchecked Sendable {
    private var session = LanguageModelSession(instructions: ActionRouter.conversationPrompt)

    func streamResponse(prompt: String, history: [Message]) -> AsyncThrowingStream<String, Error> {
        // The session's instructions are the lean persona. The device vocabulary is
        // injected inline only on turns that look like a command, so ordinary chat never
        // sees the tag list (which pushes a small model into parrot/stall/refusal mode).
        // Inlining (rather than swapping instructions) keeps the session's running
        // history intact.
        let input = ActionRouter.likelyCommand(prompt)
            ? ActionRouter.deviceVocabulary + "\n\n---\n\n" + prompt
            : prompt
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    let stream = self.session.streamResponse(to: input)
                    for try await partial in stream {
                        continuation.yield(partial.content)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    func resetContext() {
        session = LanguageModelSession(instructions: ActionRouter.conversationPrompt)
        session.prewarm()
    }

    func prewarm() {
        session.prewarm()
    }
}
