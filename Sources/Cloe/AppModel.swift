import AppIntents
import SwiftUI
import FoundationModels

@Observable
@MainActor
final class AppModel {
    /// A quick-access intent arriving from a Lock Screen Live Activity tap or an App
    /// Intent / Siri / Shortcut. The chat view observes this and acts, then clears it.
    enum QuickAction: Equatable {
        case openChat
        case startVoice
        case ask(String)
    }
    var pendingQuickAction: QuickAction?

    /// Set when an action needs the user to confirm/send a text — the chat view
    /// presents a Messages compose sheet, then clears this.
    var pendingCompose: ComposeRequest?

    /// When the user asks to text someone but gives no message ("text Claire"), Cloe
    /// asks what to say and remembers the recipient here; the next message is the body.
    var pendingTextContact: String?

    /// Leave time from the last commute answer (and a label for the alarm). Lets the
    /// user reply "set an alarm" / "yes" and have Cloe schedule one at that exact time —
    /// the model never saw the number, so the follow-up is handled deterministically.
    /// Held until consumed or replaced by a newer commute answer.
    var pendingCommuteLeave: Date?
    var pendingCommuteLabel: String?

    var messages: [Message] = []
    var isGenerating = false

    /// Every saved thread, most-recently-updated first. Drives the history view.
    private(set) var conversations: [Conversation] = []
    /// The thread currently mirrored in `messages`.
    private(set) var currentConversationID: UUID

    /// Non-nil whenever MLX is the active (or pending) backend.
    var mlxBackend: MLXBackend?
    private var backend: AIBackend?

    let settings: AppSettings
    let speech = SpeechService()
    private let deviceActions = DeviceActions()
    private let store = ConversationStore()

    init() {
        let settings = AppSettings()
        self.settings = settings

        // Restore saved threads; open the most recent, or start a fresh one.
        let saved = store.load().sorted { $0.updatedAt > $1.updatedAt }
        if let latest = saved.first {
            conversations = saved
            currentConversationID = latest.id
            messages = latest.messages
        } else {
            let convo = Conversation()
            conversations = [convo]
            currentConversationID = convo.id
        }

        if #available(iOS 26.0, *),
           SystemLanguageModel.default.isAvailable,
           !settings.preferMLX
        {
            backend = FoundationModelsBackend()
        } else {
            let mlx = MLXBackend(model: settings.selectedMLXModel)
            mlxBackend = mlx
            backend = mlx
        }

        // Spin the model up now so the first message doesn't pay cold-start latency.
        backend?.prewarm()

        // Pin (or refresh, if one survived a relaunch) the Lock Screen activity when
        // the user has quick access enabled. The controller is stateless — it queries
        // the live activities itself.
        if settings.liveActivityEnabled { CloeLiveActivityController.start() }

        // Expose this live model to App Intents (Siri / Shortcuts / Action Button) so
        // their `perform()` hands work to the same instance the UI is bound to.
        AppDependencyManager.shared.add(dependency: self)

        // Pick up a Control Center request that may have launched us.
        consumePendingIntent()
    }

    // MARK: - Deep links & quick actions

    /// Route a `cloe://…` deep link (from a Live Activity or widget tap) into a
    /// pending action.
    func handleDeepLink(_ url: URL) {
        switch url.host {
        case "voice": pendingQuickAction = .startVoice
        default: pendingQuickAction = .openChat
        }
    }

    /// Consume a request left by the widget extension (Control Center "Talk to Cloe")
    /// via `CloeIntentBridge`. Call on launch and whenever the app becomes active.
    func consumePendingIntent() {
        switch CloeIntentBridge.take() {
        case .voice: pendingQuickAction = .startVoice
        case .chat: pendingQuickAction = .openChat
        case nil: break
        }
    }

    var needsMLXSetup: Bool {
        guard let mlx = mlxBackend else { return false }
        if case .ready = mlx.loadState { return false }
        return true  // idle / downloading / loading / failed all stay on setup screen
    }

    // MARK: - Backend switching

    /// Switch between Foundation Models and MLX at runtime.
    /// History is preserved — the new backend replays it via `streamResponse(history:)`.
    func switchBackend(preferMLX: Bool) {
        guard !isGenerating else { return }
        settings.preferMLX = preferMLX

        if preferMLX {
            let mlx = MLXBackend(model: settings.selectedMLXModel)
            mlxBackend = mlx
            backend = mlx
        } else {
            mlxBackend = nil
            if #available(iOS 26.0, *) {
                backend = FoundationModelsBackend()
            }
        }
        backend?.prewarm()
    }

    /// Switch to a different MLX model. Creates a fresh backend (idle state); history
    /// is kept and replayed into the new model via `streamResponse(history:)`.
    func switchMLXModel(to option: MLXModelOption) {
        guard !isGenerating else { return }
        settings.selectedMLXModelID = option.id
        let mlx = MLXBackend(model: option)
        mlxBackend = mlx
        backend = mlx
    }

    // MARK: - Messaging

    func sendMessage(_ text: String) async {
        guard let backend else { return }
        messages.append(Message(role: .user, content: text))

        // Follow-up to "what do you want to say?" — this message is the text body.
        if let contact = pendingTextContact {
            pendingTextContact = nil
            await fulfilPendingText(contact: contact, body: text)
            return
        }

        isGenerating = true
        // Reflect generation on the Lock Screen quick-access activity (no-op if off).
        CloeLiveActivityController.update(phase: .thinking)

        // An action often follows a send; warm the Taptic engine now so it's
        // charged by the time we fire (no cold-start lag).
        if settings.enableDeviceActions { deviceActions.prepareHaptics() }

        let assistantMessage = Message(role: .assistant, content: "")
        messages.append(assistantMessage)
        let idx = messages.count - 1

        // Fire actions the instant they're recognised, de-duplicating across the whole
        // turn so a cumulative stream doesn't re-fire the same tag on every chunk.
        // App-leaving / sheet-presenting / date-bearing actions are held back and run
        // once the reply is done (see `DeviceAction.runsAtTurnEnd`) so Cloe gets to
        // acknowledge before the screen changes.
        var fired: [DeviceAction] = []
        var deferred: [DeviceAction] = []
        func fire(_ actions: [DeviceAction]) async {
            guard settings.enableDeviceActions else { return }
            for action in actions {
                if action.runsAtTurnEnd {
                    if !deferred.contains(action) { deferred.append(action) }
                } else if !fired.contains(action) {
                    guard messages.indices.contains(idx) else { return }
                    if case .applied = await deviceActions.perform(action) {
                        fired.append(action)
                        messages[idx].actions = fired
                    }
                }
            }
        }

        // 1. Instant path: obvious intents from the user's own words — fired before
        //    the model has generated a single token.
        var userActions = ActionRouter.intents(fromUserText: text)

        // A text request with no message body becomes a clarifying question ("what do
        // you want to say?") instead of an empty Messages sheet. Pull it aside; every
        // other action in the turn still runs.
        let bodylessText = userActions.first {
            if case .text(_, let body) = $0 { return body?.isEmpty ?? true }
            return false
        }
        if let bodylessText { userActions.removeAll { $0 == bodylessText } }

        await fire(userActions)

        // Bodyless text → fire everything else, ask what to send, stash the recipient,
        // and skip the model. The next message becomes the body.
        if settings.enableDeviceActions, case .text(let contact, _)? = bodylessText {
            await runDeferred(deferred, userText: text, idx: idx, fired: &fired)
            pendingTextContact = contact
            let who = contact.split(separator: " ").first.map { String($0).capitalized } ?? contact
            messages[idx].content = "Sure — what do you want to say to \(who)?"
            isGenerating = false
            CloeLiveActivityController.update(phase: .replying, snippet: messages[idx].content)
            persist()
            if settings.autoSpeak { speech.speak(messages[idx].content) }
            return
        }

        // Retrieval: clipboard / scratchpad questions are answered DIRECTLY from
        // Clink's shared store — deterministic, so the data always shows rather than
        // the model deflecting ("let me check…"). Short-circuits the model entirely.
        if settings.enableDeviceActions, let reply = ClinkStore.retrievalReply(for: text) {
            messages[idx].content = reply
            isGenerating = false
            CloeLiveActivityController.update(phase: .replying, snippet: reply)
            persist()
            if settings.autoSpeak { speech.speak(reply) }
            return
        }

        // Contextual alarm: replying "set an alarm" (or just "yes") to a commute answer
        // schedules one at the leave time we computed — the model never saw that number.
        // Skipped when the message names its own time ("set an alarm for 6am"), which the
        // normal action path handles via the keyword/tag route.
        if settings.enableDeviceActions,
           let leave = pendingCommuteLeave, leave > Date(),
           ActionRouter.firstDate(in: text) == nil,
           ActionRouter.isAlarmRequest(text) || (isAffirmative(text) && previousReplyOfferedAlarm(before: idx)) {
            let label = pendingCommuteLabel
            pendingCommuteLeave = nil
            pendingCommuteLabel = nil
            let outcome = await deviceActions.perform(.alarm(at: leave, label: label))
            let formatter = DateFormatter()
            formatter.timeStyle = .short; formatter.dateStyle = .none
            let reply: String
            if case .applied = outcome {
                messages[idx].actions = [.alarm(at: leave, label: label)]
                reply = "⏰ Alarm set for \(formatter.string(from: leave)) — I'll make sure you're out the door on time."
            } else {
                reply = "I couldn't set the alarm — allow Alarms for Cloe in Settings and try again."
            }
            messages[idx].content = reply
            isGenerating = false
            CloeLiveActivityController.update(phase: .replying, snippet: reply)
            persist()
            if settings.autoSpeak { speech.speak(reply) }
            return
        }

        // Commute: "what time do I need to leave?" is computed from a real MapKit ETA
        // (arrival − travel), not guessed by the model — a leave time has to be exact.
        // Like the retrieval path, this short-circuits the model when it applies.
        if settings.enableDeviceActions, let plan = await CommutePlanner.plan(for: text, settings: settings) {
            messages[idx].content = plan.reply
            // Remember the leave time so the user can follow up with "set an alarm".
            pendingCommuteLeave = plan.leave
            pendingCommuteLabel = plan.leave == nil ? nil : "Leave for \(plan.destination)"
            isGenerating = false
            CloeLiveActivityController.update(phase: .replying, snippet: plan.reply)
            persist()
            if settings.autoSpeak { speech.speak(plan.reply) }
            return
        }

        do {
            let stream = backend.streamResponse(prompt: text, history: messages)
            for try await chunk in stream {
                // Strip thinking + tags live so the user never sees `<think>` or raw `{{…}}`.
                let (clean, actions) = ActionRouter.extract(from: chunk)
                messages[idx].content = clean
                // 2. Live path: fire a model tag the moment it finishes streaming. With
                //    tag-first prompting that's in the first tokens, not after the reply.
                await fire(actions)
            }
        } catch {
            messages[idx].content = error.localizedDescription
            backend.resetContext()
            isGenerating = false
            CloeLiveActivityController.update(phase: .idle)
            persist()
            return
        }

        isGenerating = false
        // Show the fresh answer on the Lock Screen so it's glanceable / tap-to-continue.
        if messages.indices.contains(idx) {
            CloeLiveActivityController.update(phase: .replying, snippet: messages[idx].content)
        }

        // 3. Turn-end path: now that Cloe has finished speaking, run the held-back
        //    actions. Reminder/event dates are read from the user's own words here.
        await runDeferred(deferred, userText: text, idx: idx, fired: &fired)

        persist()
        if settings.autoSpeak, messages.indices.contains(idx) {
            speech.speak(messages[idx].content)
        }
    }

    /// Run the held-back app-leaving / sheet / date-bearing actions and record them on
    /// the assistant message. Shared by the normal turn-end path and the bodyless-text
    /// branch.
    private func runDeferred(_ deferred: [DeviceAction], userText: String, idx: Int, fired: inout [DeviceAction]) async {
        guard settings.enableDeviceActions, !deferred.isEmpty else { return }
        for action in ActionRouter.attachingDates(deferred, userText: userText) {
            guard messages.indices.contains(idx) else { break }
            switch await deviceActions.perform(action) {
            case .applied:
                fired.append(action)
                messages[idx].actions = fired
            case .compose(let request):
                // Use the contact/body resolved during compose (the model may have
                // dropped the `name|message` pipe) so the chip shows the real name.
                fired.append(.text(contact: request.contactDisplay, body: request.body))
                messages[idx].actions = fired
                pendingCompose = request
            case .unavailable:
                break
            }
        }
    }

    /// A bare yes — accepts the alarm Cloe just offered after a commute answer.
    private func isAffirmative(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: CharacterSet(charactersIn: " .!?")).lowercased()
        let yes: Set<String> = [
            "yes", "yeah", "yep", "yup", "sure", "ok", "okay", "please", "yes please",
            "do it", "go on", "please do", "sounds good", "go for it", "set it", "set one",
        ]
        return yes.contains(t)
    }

    /// Did the previous assistant turn offer an alarm? Guards the bare-"yes" path so a
    /// stray "yeah" only sets an alarm when one was actually just offered. `idx` is the
    /// new (empty) assistant slot; the prior reply is two back (user message sits between).
    private func previousReplyOfferedAlarm(before idx: Int) -> Bool {
        let prior = idx - 2
        guard messages.indices.contains(prior), messages[prior].role == .assistant else { return false }
        return messages[prior].content.localizedCaseInsensitiveContains("alarm")
    }

    /// The user supplied the message body Cloe asked for. Resolve the contact and open
    /// the Messages compose sheet, with a short confirmation in chat.
    private func fulfilPendingText(contact: String, body: String) async {
        messages.append(Message(role: .assistant, content: ""))
        let idx = messages.count - 1
        guard settings.enableDeviceActions else {
            messages[idx].content = "Texting is turned off in settings."
            persist()
            return
        }
        switch await deviceActions.perform(.text(contact: contact, body: body)) {
        case .compose(let request):
            messages[idx].actions = [.text(contact: request.contactDisplay, body: request.body)]
            messages[idx].content = "Opening your message to \(request.contactDisplay)."
            pendingCompose = request
        case .applied:
            messages[idx].content = "Done."
        case .unavailable:
            messages[idx].content = "I couldn't open Messages just now."
        }
        persist()
        if settings.autoSpeak { speech.speak(messages[idx].content) }
    }

    // MARK: - Conversation management

    /// Start a fresh thread. The old one stays in history (dropped only if it was empty).
    func newConversation() {
        guard !isGenerating else { return }
        speech.stop()
        backend?.resetContext()
        pendingTextContact = nil
        leaveCurrent()
        let convo = Conversation()
        conversations.insert(convo, at: 0)
        currentConversationID = convo.id
        messages = []
        // Back to the launcher state on the Lock Screen.
        CloeLiveActivityController.update(phase: .idle)
    }

    /// Load a saved thread into the chat view.
    func selectConversation(_ id: UUID) {
        guard !isGenerating, id != currentConversationID else { return }
        speech.stop()
        backend?.resetContext()
        pendingTextContact = nil
        leaveCurrent()
        guard let convo = conversations.first(where: { $0.id == id }) else { return }
        currentConversationID = id
        messages = convo.messages
    }

    /// Delete a thread; if it's the open one, fall back to the next (or a fresh thread).
    func deleteConversation(_ id: UUID) {
        guard !isGenerating else { return }
        conversations.removeAll { $0.id == id }
        if id == currentConversationID {
            speech.stop()
            backend?.resetContext()
            if let next = conversations.first {
                currentConversationID = next.id
                messages = next.messages
            } else {
                let convo = Conversation()
                conversations = [convo]
                currentConversationID = convo.id
                messages = []
            }
        }
        store.save(conversations)
    }

    /// The "Clear" affordance — preserve the current thread in history and open a new one.
    func clearConversation() { newConversation() }

    // MARK: - Persistence

    /// Sync the live `messages` into the current thread and write to disk.
    private func persist() {
        let now = Date.now
        if let idx = conversations.firstIndex(where: { $0.id == currentConversationID }) {
            conversations[idx].messages = messages
            conversations[idx].updatedAt = now
            if conversations[idx].title.isEmpty {
                conversations[idx].title = Conversation.deriveTitle(from: messages)
            }
        } else {
            var convo = Conversation(id: currentConversationID, messages: messages, updatedAt: now)
            convo.title = Conversation.deriveTitle(from: messages)
            conversations.insert(convo, at: 0)
        }
        conversations.sort { $0.updatedAt > $1.updatedAt }
        store.save(conversations)
    }

    /// Before switching away: persist a non-empty thread, or discard an empty one so
    /// blank threads don't pile up in history.
    private func leaveCurrent() {
        if messages.isEmpty {
            conversations.removeAll { $0.id == currentConversationID }
            store.save(conversations)
        } else {
            persist()
        }
    }
}
