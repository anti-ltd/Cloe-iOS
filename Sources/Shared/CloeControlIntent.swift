import AppIntents

/// Action for the Control Center "Talk to Cloe" button. Lives in `Sources/Shared`
/// so it compiles into the widget extension (the app-target `TalkToCloeIntent` can't
/// — it references `AppModel` via `@Dependency`). It opens the app and records the
/// voice request through `CloeIntentBridge`, which the app consumes on activation.
///
/// Hidden from the Shortcuts app (`isDiscoverable = false`) so it doesn't duplicate
/// the app-target `TalkToCloeIntent`, which already covers Siri / Shortcuts.
struct TalkToCloeControlIntent: AppIntent {
    static let title: LocalizedStringResource = "Talk to Cloe"
    static let isDiscoverable = false
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        CloeIntentBridge.request(.voice)
        return .result()
    }
}
