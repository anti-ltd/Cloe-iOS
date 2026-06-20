import Foundation
import Hub
import MLXLLM
import MLXLMCommon

@Observable
final class MLXBackend: AIBackend, @unchecked Sendable {
    enum LoadState {
        case idle, downloading(Double), loading, ready, failed(String)
    }

    var loadState: LoadState = .idle
    private var modelContainer: ModelContainer?
    /// Guards `prepare()` against concurrent callers (launch prewarm + setup screen)
    /// double-loading the same model.
    private var isPreparing = false

    private let modelOption: MLXModelOption
    private var config: ModelConfiguration { modelOption.configuration }

    // Application Support survives app updates and relaunches (Caches, the default,
    // can be purged under storage pressure). Nothing in the sandbox survives a true
    // delete+reinstall — install new builds over the old app to keep downloaded models.
    private static var downloadBase: URL {
        let fm = FileManager.default
        let dir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// HubApi for downloading. `offline == true` loads purely from disk: no network
    /// HEAD revalidation, so a network blip can't fail the load (which would otherwise
    /// flip us to `.failed` and wipe the cached model on the next attempt).
    private static func hubApi(offline: Bool) -> HubApi {
        HubApi(downloadBase: downloadBase, useOfflineMode: offline ? true : nil)
    }

    /// True if this model's snapshot already exists on disk.
    /// HubApi stores at {downloadBase}/models/{org}/{repo}.
    private func modelExistsLocally() -> Bool {
        let dir = Self.downloadBase
            .appendingPathComponent("models")
            .appendingPathComponent(config.name)
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil
        ) else { return false }
        // A finished snapshot has weight files (*.safetensors), not just metadata.
        return contents.contains { $0.pathExtension == "safetensors" }
    }

    init(model: MLXModelOption = MLXModelCatalog.defaultModel) {
        self.modelOption = model
    }

    /// Qwen3 is a hybrid reasoner: left alone it emits a hidden `<think>…</think>`
    /// block before the real answer. We hide that block in the UI, so for a chat
    /// companion it's pure latency with nothing on screen. Disable it via Qwen3's
    /// `/no_think` soft-switch. Only applied to models that recognise it.
    private var isThinkingModel: Bool { modelOption.id.hasPrefix("qwen3") }

    /// System prompt for this model on a given user message: the per-turn gated
    /// persona/device prompt (lean for chat, +device vocabulary for commands), plus the
    /// `/no_think` switch for reasoning models.
    private func systemPrompt(for userText: String) -> String {
        let base = ActionRouter.systemPrompt(for: userText)
        return isThinkingModel ? base + "\n\n/no_think" : base
    }

    /// True if this model's weights are already on disk — i.e. `prepare()` will
    /// load offline rather than kick off a fresh download. Drives launch auto-load.
    var isDownloaded: Bool { modelExistsLocally() }

    // MARK: - Setup

    @MainActor
    func prepare() async {
        guard modelContainer == nil, !isPreparing else { return }
        isPreparing = true
        defer { isPreparing = false }

        loadState = .downloading(0)

        // If the model is already on disk, load it offline: no network revalidation,
        // so transient connectivity can't fail the load. Fall back to an online
        // download only if the offline load fails (missing/corrupt files).
        if modelExistsLocally() {
            do {
                modelContainer = try await load(offline: true)
                loadState = .ready
                await warmUp()
                return
            } catch {
                // Local files are unusable — clear them and re-download cleanly.
                clearModelCache()
            }
        }

        do {
            modelContainer = try await load(offline: false)
            loadState = .ready
            await warmUp()
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    /// Start loading the moment the app launches (if the model is already
    /// downloaded) instead of waiting for the setup screen's `.task` to fire, so
    /// load + warm-up overlap with the user reading the UI. No-op if not downloaded.
    func prewarm() {
        Task { @MainActor in
            if case .idle = loadState, isDownloaded { await prepare() }
        }
    }

    /// Run a 1-token throwaway generation right after load to compile the Metal
    /// graph and prime caches, so the user's *first real* message streams
    /// immediately instead of paying graph-compilation latency. Best-effort —
    /// failures here never affect the `.ready` state.
    private func warmUp() async {
        guard let container = modelContainer else { return }
        let warmChat: [Chat.Message] = [.system(systemPrompt(for: "Hi")), .user("Hi")]
        let warm = UserInput(chat: warmChat)
        try? await container.perform { context in
            let input = try await context.processor.prepare(input: warm)
            // Annotate the param: `generate` has `(Int)` and `([Int])` overloads,
            // and a bare `_` is ambiguous between them.
            _ = try MLXLMCommon.generate(
                input: input,
                parameters: GenerateParameters(maxTokens: 1),
                context: context
            ) { (_: Int) in .stop }
        }
    }

    private func load(offline: Bool) async throws -> ModelContainer {
        try await LLMModelFactory.shared.loadContainer(
            hub: Self.hubApi(offline: offline),
            configuration: config
        ) { [weak self] progress in
            Task { @MainActor in
                self?.loadState = .downloading(progress.fractionCompleted)
            }
        }
    }

    /// Removes this model's cached files so the next `prepare()` triggers a fresh download.
    private func clearModelCache() {
        // HubApi stores models at {downloadBase}/models/{org}/{repo}
        // config.name returns the full repo ID, e.g. "mlx-community/Qwen3-1.7B-4bit"
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let modelDir = appSupport
            .appendingPathComponent("models")
            .appendingPathComponent(config.name)
        try? FileManager.default.removeItem(at: modelDir)
    }

    // MARK: - Inference

    func streamResponse(prompt: String, history: [Message]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                guard let container = self.modelContainer else {
                    continuation.finish(throwing: MLXError.modelNotLoaded)
                    return
                }

                // Build UserInput before the @Sendable perform closure (Chat.Message isn't Sendable).
                let chatHistory: [Chat.Message] = [.system(self.systemPrompt(for: prompt))]
                    + history.dropLast().compactMap { msg in
                        switch msg.role {
                        case .user: return .user(msg.content)
                        case .assistant: return msg.content.isEmpty ? nil : .assistant(msg.content)
                        }
                    } + [.user(prompt)]
                let userInput = UserInput(chat: chatHistory)

                do {
                    try await container.perform { context in
                        let input = try await context.processor.prepare(input: userInput)
                        var tokens: [Int] = []
                        // Cap length so a small model can't run away (default is
                        // unbounded). A mild repetition penalty stops tiny models
                        // looping / parroting a previous turn's confirmation.
                        let _ = try MLXLMCommon.generate(
                            input: input,
                            parameters: GenerateParameters(maxTokens: 512, repetitionPenalty: 1.1),
                            context: context
                        ) { tokenId in
                            // Decode the FULL token sequence each step, never a single
                            // token in isolation: one multi-byte UTF-8 character (e.g. an
                            // emoji) spans several tokens, and per-token decode emits
                            // U+FFFD (�) for the split byte fragments. Re-decoding the
                            // whole array lets the bytes reassemble into the real glyph.
                            tokens.append(tokenId)
                            continuation.yield(context.tokenizer.decode(tokens: tokens))
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
