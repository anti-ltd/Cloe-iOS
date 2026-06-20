import MessageUI
import SwiftUI

/// A pending "text someone" request that the chat view turns into a Messages
/// compose sheet. Cloe never sends silently — iOS requires the user to tap Send.
struct ComposeRequest: Identifiable, Equatable {
    let id = UUID()
    /// Resolved phone numbers (empty if no contact matched — the user fills it in).
    let recipients: [String]
    let body: String?
    /// The name shown in Cloe's chip, e.g. "Mom".
    let contactDisplay: String
}

/// Wraps `MFMessageComposeViewController` so Cloe can pre-fill recipient + body and
/// let the user confirm and send.
struct MessageComposeView: UIViewControllerRepresentable {
    let request: ComposeRequest
    /// Called when the sheet finishes (sent, cancelled, or failed). `@MainActor`
    /// because it clears `AppModel.pendingCompose`; being main-actor-typed also makes
    /// the closure `Sendable`, so the nonisolated delegate can hold it safely.
    let onFinish: @MainActor () -> Void

    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let vc = MFMessageComposeViewController()
        vc.messageComposeDelegate = context.coordinator
        vc.recipients = request.recipients.isEmpty ? nil : request.recipients
        if let body = request.body { vc.body = body }
        return vc
    }

    func updateUIViewController(_ vc: MFMessageComposeViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        let onFinish: @MainActor () -> Void
        init(onFinish: @escaping @MainActor () -> Void) { self.onFinish = onFinish }

        nonisolated func messageComposeViewController(
            _ controller: MFMessageComposeViewController,
            didFinishWith result: MessageComposeResult
        ) {
            // Read the Sendable callback out before hopping — capturing `self` or the
            // (non-Sendable) `controller` into the main-actor closure would race under
            // Swift 6. No manual dismiss needed: clearing `pendingCompose` collapses the
            // `.sheet(item:)`, which tears down this controller. MessageUI always calls
            // this on the main thread, so the isolation assumption holds.
            let finish = onFinish
            MainActor.assumeIsolated { finish() }
        }
    }
}
