import Foundation
import FoundationModels

@available(iOS 26.0, *)
final class FoundationModelsBackend: AIBackend, @unchecked Sendable {
    private var session = LanguageModelSession()

    func streamResponse(prompt: String, history: [Message]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let stream = self.session.streamResponse(to: prompt)
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
        session = LanguageModelSession()
    }
}
