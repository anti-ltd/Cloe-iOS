import SwiftUI
import iUXiOS

#Preview("Empty") {
    let model = AppModel()
    return ChatView()
        .environment(model)
        .environment(model.settings)
}

#Preview("Conversation") {
    let model = AppModel()
    model.messages = [
        Message(role: .user, content: "Hey, what's the capital of France?"),
        Message(role: .assistant, content: "The capital of France is Paris."),
        Message(role: .user, content: "What about Germany?"),
        Message(role: .assistant, content: "The capital of Germany is Berlin."),
    ]
    return ChatView()
        .environment(model)
        .environment(model.settings)
}

#Preview("Generating") {
    let model = AppModel()
    model.messages = [
        Message(role: .user, content: "Tell me something interesting about space."),
        Message(role: .assistant, content: "Did you know that a day on Venus is longer than a year on Venus?"),
    ]
    model.isGenerating = true
    return ChatView()
        .environment(model)
        .environment(model.settings)
}

/// Cloe — voice-first assistant with a calm editorial layout. One live orb on the
/// home screen; conversation is typography-first with a compact status orb.
struct ChatView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings
    @State private var input = ""
    @State private var showSettings = false
    @State private var showHistory = false
    @State private var voice = VoiceInput()
    @State private var orbHeld = false
    @State private var showIntentions = false
    @State private var lastSeededWord = ""
    @AppStorage("cloe.didHoldOrb") private var didHoldOrb = false

    private var theme: CloeTheme { settings.visualTheme }
    private var atRest: Bool { model.messages.isEmpty }

    private static let intentions: [OrbitIntention] = [
        OrbitIntention(word: "Write",  prompt: "Help me write a short, warm message."),
        OrbitIntention(word: "Plan",   prompt: "Help me plan out my day."),
        OrbitIntention(word: "Wonder", prompt: "Tell me something surprising I don't already know."),
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                CloeStage(theme: theme)

                if atRest {
                    heroView
                        .transition(.opacity)
                } else {
                    conversationView
                        .transition(.opacity)
                }
            }
            .animation(CloeMotion.hero, value: atRest)
            .safeAreaInset(edge: .bottom) {
                InputBar(input: $input,
                         theme: theme,
                         isRecording: voice.isRecording,
                         level: { voice.audioLevel },
                         onSend: send)
            }
            .toolbar { chatToolbar }
            .toolbarBackground(.hidden, for: .navigationBar)
            .task(id: atRest) {
                showIntentions = false
                guard atRest else { return }
                try? await Task.sleep(for: .seconds(0.8))
                guard atRest else { return }
                withAnimation(CloeMotion.intentionReveal) { showIntentions = true }
            }
            .onChange(of: voice.transcript) { _, newValue in
                if voice.isRecording, !newValue.isEmpty { input = newValue }
            }
            .onAppear {
                voice.onAutoSubmit = { send() }
                voice.silenceInterval = settings.dictationSilence
                model.consumePendingIntent()
                handleQuickAction(model.pendingQuickAction)
            }
            .onChange(of: settings.dictationSilence) { _, newValue in
                voice.silenceInterval = newValue
            }
            .onChange(of: model.pendingQuickAction) { _, action in
                handleQuickAction(action)
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
                    .environment(settings)
                    .environment(model)
            }
            .sheet(isPresented: $showHistory) {
                HistoryView()
                    .environment(model)
                    .environment(settings)
            }
            .sheet(item: composeBinding) { request in
                MessageComposeView(request: request) { model.pendingCompose = nil }
                    .ignoresSafeArea()
            }
        }
        .tint(theme.primary)
    }

    // MARK: - Hero

    private var heroView: some View {
        VStack(spacing: 0) {
            Spacer()

            talkableOrb(size: 160)

            Text("Cloe")
                .font(CloeTypography.hero)
                .foregroundStyle(CloePalette.ink)
                .padding(.top, 32)

            Text(statusLabel)
                .font(CloeTypography.footnote)
                .foregroundStyle(CloePalette.inkMuted)
                .padding(.top, 6)

            if !didHoldOrb, orbState == .idle {
                Text("Hold the orb to speak")
                    .font(CloeTypography.footnote)
                    .foregroundStyle(CloePalette.inkMuted.opacity(0.7))
                    .padding(.top, 4)
            }

            IntentionStrip(theme: theme, items: Self.intentions, visible: showIntentions) { intention in
                lastSeededWord = intention.word
                seed(intention)
            }
            .padding(.top, 36)
            .sensoryFeedback(.selection, trigger: lastSeededWord)

            Spacer()
            Spacer(minLength: 40)
        }
    }

    // MARK: - Conversation

    private var conversationView: some View {
        VStack(spacing: 0) {
            conversationHeader

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 28) {
                        ForEach(model.messages) { message in
                            DialogueLine(
                                message: message,
                                theme: theme,
                                isSpeaking: model.speech.isSpeaking(message.content),
                                isWaiting: model.isGenerating && message.id == model.messages.last?.id,
                                onSpeak: message.role == .assistant
                                    ? { model.speech.toggle(message.content) }
                                    : nil
                            )
                            .id(message.id)
                        }
                    }
                    .frame(maxWidth: 360)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                    .padding(.bottom, 16)
                }
                .scrollContentBackground(.hidden)
                .scrollIndicators(.hidden)
                .onChange(of: model.messages.count) { scrollToBottom(proxy: proxy) }
                .onChange(of: model.isGenerating) { scrollToBottom(proxy: proxy) }
                .onChange(of: model.messages.last?.content) { scrollToBottom(proxy: proxy) }
            }
        }
    }

    private var conversationHeader: some View {
        HStack(spacing: 14) {
            talkableOrb(size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text("Cloe")
                    .font(CloeTypography.captionMedium)
                    .foregroundStyle(CloePalette.ink)
                Text(statusLabel)
                    .font(CloeTypography.footnote)
                    .foregroundStyle(CloePalette.inkMuted)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    private var statusLabel: String {
        switch orbState {
        case .idle: "Ready"
        case .listening: "Listening…"
        case .thinking: "Thinking…"
        case .speaking: "Speaking…"
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var chatToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            iconButton("gearshape") { showSettings = true }
        }
        ToolbarItem(placement: .topBarTrailing) {
            iconButton("clock.arrow.circlepath") { showHistory = true }
        }
        ToolbarItem(placement: .topBarTrailing) {
            if !atRest {
                iconButton("square.and.pencil") { model.clearConversation() }
                    .disabled(model.isGenerating)
            }
        }
    }

    private func iconButton(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(CloePalette.ink.opacity(0.72))
                .frame(width: 36, height: 36)
        }
    }

    // MARK: - Orb

    @ViewBuilder
    private func talkableOrb(size: CGFloat) -> some View {
        CloeOrb(theme: theme, state: orbState, pressed: orbHeld, size: size,
                level: { currentLevel() })
            .scaleEffect(orbHeld ? 1.04 : 1)
            .animation(CloeMotion.orbPress, value: orbHeld)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !orbHeld, !model.isGenerating {
                            orbHeld = true
                            didHoldOrb = true
                            voice.startHold()
                        }
                    }
                    .onEnded { _ in
                        if orbHeld {
                            orbHeld = false
                            voice.endHold()
                        }
                    }
            )
            .sensoryFeedback(trigger: orbHeld) { _, held in
                held ? .impact(weight: .medium, intensity: 0.7)
                     : .impact(weight: .light, intensity: 0.4)
            }
    }

    private func currentLevel() -> CGFloat {
        if voice.isRecording { return voice.audioLevel }
        if model.speech.isSpeaking {
            let t = Date().timeIntervalSinceReferenceDate
            return 0.35 + 0.25 * CGFloat(abs(sin(t * 4.5)))
        }
        return 0
    }

    private var composeBinding: Binding<ComposeRequest?> {
        Binding(get: { model.pendingCompose }, set: { model.pendingCompose = $0 })
    }

    private var orbState: CloeOrbState {
        if model.isGenerating { return .thinking }
        if voice.isRecording { return .listening }
        if model.speech.isSpeaking { return .speaking }
        return .idle
    }

    // MARK: - Actions

    private func seed(_ intention: OrbitIntention) {
        guard !model.isGenerating else { return }
        withAnimation(CloeMotion.hero) { showIntentions = false }
        input = intention.prompt
        send()
    }

    private func handleQuickAction(_ action: AppModel.QuickAction?) {
        guard let action else { return }
        model.pendingQuickAction = nil
        switch action {
        case .openChat: break
        case .startVoice:
            if !voice.isRecording, !model.isGenerating { voice.toggle() }
        case .ask(let prompt):
            guard !model.isGenerating else { break }
            input = prompt
            send()
        }
    }

    private func send() {
        if voice.isRecording { voice.stop() }
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !model.isGenerating else { return }
        input = ""
        Task { await model.sendMessage(text) }
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.15)) {
            if let last = model.messages.last {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }
}

// MARK: - Dialogue

private struct DialogueLine: View {
    let message: Message
    var theme: CloeTheme
    var isSpeaking: Bool
    var isWaiting: Bool
    var onSpeak: (() -> Void)?

    private var isUser: Bool { message.role == .user }

    var body: some View {
        VStack(alignment: isUser ? .trailing : .leading, spacing: 8) {
            if message.content.isEmpty, isWaiting {
                TypingIndicator(theme: theme)
            } else if !message.content.isEmpty {
                Text(message.content)
                    .font(isUser ? CloeTypography.bodyMedium : CloeTypography.body)
                    .lineSpacing(5)
                    .foregroundStyle(isUser ? theme.dialogueUser : theme.dialogueCloe)
                    .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
                    .multilineTextAlignment(isUser ? .trailing : .leading)

                if !isUser, let onSpeak {
                    Button(action: onSpeak) {
                        Image(systemName: isSpeaking ? "stop.circle" : "speaker.wave.2")
                            .font(.footnote)
                            .foregroundStyle(isSpeaking ? theme.primary : CloePalette.inkMuted)
                    }
                    .buttonStyle(.plain)
                }
            }

            if !message.actions.isEmpty {
                actionChips
            }
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
    }

    private var actionChips: some View {
        FlowLayout(spacing: 8, lineSpacing: 8) {
            ForEach(Array(message.actions.enumerated()), id: \.offset) { _, action in
                Label(action.label, systemImage: action.systemImage)
                    .font(CloeTypography.captionMedium)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .foregroundStyle(CloePalette.ink.opacity(0.85))
                    .background(CloePalette.surface)
                    .clipShape(Capsule())
                    .overlay { Capsule().strokeBorder(CloePalette.separator, lineWidth: 0.5) }
            }
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
    }
}
