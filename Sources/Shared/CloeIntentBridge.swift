import Foundation

/// Cross-target hand-off for quick actions triggered from the widget extension
/// (Control Center). The widget process can't reach the app's `AppModel`, so it
/// records the request in shared `UserDefaults`; the app reads + clears it when it
/// becomes active. (Home/Lock Screen widgets use `cloe://` deep links instead and
/// don't need this — only controls, which run an `AppIntent` rather than a URL.)
enum CloeIntentBridge {
    private static let key = "cloe.pendingQuickAction"

    enum Action: String { case chat, voice }

    static func request(_ action: Action) {
        UserDefaults.standard.set(action.rawValue, forKey: key)
    }

    /// Read and clear the pending action. Safe to call repeatedly (idempotent).
    static func take() -> Action? {
        let defaults = UserDefaults.standard
        guard let raw = defaults.string(forKey: key) else { return nil }
        defaults.removeObject(forKey: key)
        return Action(rawValue: raw)
    }
}
