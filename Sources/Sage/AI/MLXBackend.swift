import Foundation
import MLXLLM
import MLXLMCommon

@Observable
final class MLXBackend: AIBackend, @unchecked Sendable {
    enum LoadState {
        case idle, downloading(Double), loading, ready, failed(String)
    }

    var loadState: LoadState = .idle
    private var modelContainer: ModelContainer?

    // Llama 3.2 1B 4-bit: ~700 MB download, runs on A14+
    private let config = LLMRegistry.llama3_2_1B_4bit

    func prepare() async {
        guard modelContainer == nil else { return }
        loadState = .downloading(0)
        do {
            let container = try await LLMModelFactory.shared.loadContainer(
                configuration: config
            ) { [weak self] progress in
                Task { @MainActor in
                    self?.loadState = .downloading(progress.fractionCompleted)
                }
            }
            modelContainer = container
            loadState = .ready
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    func streamResponse(prompt: String, history: [Message]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                guard let container = self.modelContainer else {
                    continuation.finish(throwing: MLXError.modelNotLoaded)
                    return
                }

                // Build UserInput before the @Sendable perform closure (Chat.Message isn't Sendable).
                let chatHistory: [Chat.Message] = history.dropLast().compactMap { msg in
                    switch msg.role {
                    case .user: return .user(msg.content)
                    case .assistant: return msg.content.isEmpty ? nil : .assistant(msg.content)
                    }
                } + [.user(prompt)]
                let userInput = UserInput(chat: chatHistory)

                do {
                    try await container.perform { context in
                        let input = try await context.processor.prepare(input: userInput)
                        var accumulated = ""
                        let _ = try MLXLMCommon.generate(
                            input: input,
                            parameters: GenerateParameters(),
                            context: context
                        ) { tokenId in
                            let piece = context.tokenizer.decode(tokens: [tokenId])
                            accumulated += piece
                            continuation.yield(accumulated)
                            return .more
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    func resetContext() {
        // Each generate call is independent; nothing to reset.
    }

    enum MLXError: LocalizedError {
        case modelNotLoaded
        var errorDescription: String? { "Model not loaded." }
    }
}
