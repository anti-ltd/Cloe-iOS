import AppIntents

// App Intents — the one sanctioned way a third-party app plugs into the assistant
// surface: Siri invocation, the Shortcuts app, Spotlight, and the Action Button.
//
// Both intents open the app and hand the work to the live `AppModel` (resolved via
// `@Dependency`, registered in `AppModel.init`). Speech-to-text and the streaming
// chat need the app foreground, so `openAppWhenRun = true`; an App Intents
// *extension* (to answer without launching) is a deliberate later step.

/// "Ask Cloe …" — the marquee shortcut. Siri / Shortcuts collect a prompt, the app
/// opens, and Cloe answers it in the chat.
struct AskCloeIntent: AppIntent {
    static let title: LocalizedStringResource = "Ask Cloe"
    static let description = IntentDescription(
        "Open Cloe and ask it something.",
        categoryName: "Chat")
    static let openAppWhenRun = true

    @Parameter(title: "Prompt", requestValueDialog: "What would you like to ask Cloe?")
    var prompt: String

    @Dependency private var appModel: AppModel

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .result(dialog: "Ask me anything when you're ready.") }
        appModel.pendingQuickAction = .ask(text)
        return .result(dialog: "On it.")
    }
}

/// "Open Cloe" / "Talk to Cloe" — opens the chat and starts hands-free voice so the
/// user can just speak. Pairs with the Action Button and Control Center (Item 2).
struct TalkToCloeIntent: AppIntent {
    static let title: LocalizedStringResource = "Talk to Cloe"
    static let description = IntentDescription(
        "Open Cloe and start talking hands-free.",
        categoryName: "Chat")
    static let openAppWhenRun = true

    @Dependency private var appModel: AppModel

    @MainActor
    func perform() async throws -> some IntentResult {
        appModel.pendingQuickAction = .startVoice
        return .result()
    }
}

/// Registers the spoken phrases. Phrases must contain the app name (`.applicationName`).
struct CloeAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AskCloeIntent(),
            phrases: [
                "Ask \(.applicationName)",
                "Ask \(.applicationName) a question",
            ],
            shortTitle: "Ask Cloe",
            systemImageName: "sparkles")

        AppShortcut(
            intent: TalkToCloeIntent(),
            phrases: [
                "Talk to \(.applicationName)",
                "Open \(.applicationName)",
            ],
            shortTitle: "Talk to Cloe",
            systemImageName: "mic.fill")
    }
}
