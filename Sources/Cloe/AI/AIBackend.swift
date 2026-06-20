import Foundation

protocol AIBackend: AnyObject {
    /// Stream accumulated text (full response so far, not deltas) for a prompt + history.
    func streamResponse(prompt: String, history: [Message]) -> AsyncThrowingStream<String, Error>
    func resetContext()

    /// Spin up the model ahead of the first real prompt so initial latency
    /// (load / KV-cache warm-up) isn't paid when the user is waiting. No-op by default.
    func prewarm()
}

extension AIBackend {
    func prewarm() {}
}
