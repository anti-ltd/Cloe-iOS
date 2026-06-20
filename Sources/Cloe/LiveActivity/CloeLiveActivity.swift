import ActivityKit
import Foundation

/// Thin wrapper over ActivityKit for Cloe's Lock Screen quick-access activity.
///
/// Stateless by design: it never holds an `Activity` reference (that type is
/// non-Sendable, so storing it and awaiting its async methods trips Swift 6 strict
/// concurrency). Instead every call queries the live `Activity.activities` and
/// awaits inline inside a nonisolated async helper — the same pattern Cling uses.
/// Cloe only ever runs one activity, so the loops touch at most one. Every call
/// no-ops gracefully when Live Activities are disabled or none is running.
enum CloeLiveActivityController {
    /// True when the user has Live Activities enabled for Cloe in system Settings.
    static var isSupported: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    /// Pin the quick-access activity to the Lock Screen, or refresh it to idle if
    /// one is already shown (e.g. it survived an app relaunch).
    static func start() {
        guard isSupported else { return }
        let content = ActivityContent(
            state: CloeActivityAttributes.ContentState(phase: .idle, snippet: ""),
            staleDate: nil)
        if Activity<CloeActivityAttributes>.activities.isEmpty {
            _ = try? Activity.request(
                attributes: CloeActivityAttributes(label: "Cloe"),
                content: content)
        } else {
            Task { await apply(content) }
        }
    }

    /// Push a new phase/snippet to the running activity. No-op if none is running.
    static func update(phase: CloeActivityAttributes.ContentState.Phase, snippet: String = "") {
        // Keep the payload small — the Lock Screen only shows a couple of lines.
        let trimmed = String(snippet.prefix(140))
        let content = ActivityContent(
            state: CloeActivityAttributes.ContentState(phase: phase, snippet: trimmed),
            staleDate: nil)
        Task { await apply(content) }
    }

    /// Remove the activity from the Lock Screen.
    static func end() {
        Task { await endAll() }
    }

    // MARK: - Async helpers

    // Nonisolated so the non-Sendable `Activity` stays a local within one async
    // function and is awaited inline — never sent across an isolation boundary.
    private static func apply(_ content: ActivityContent<CloeActivityAttributes.ContentState>) async {
        for activity in Activity<CloeActivityAttributes>.activities {
            await activity.update(content)
        }
    }

    private static func endAll() async {
        for activity in Activity<CloeActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}
