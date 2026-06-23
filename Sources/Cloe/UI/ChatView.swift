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

/// Presence — Cloe is one living thing on the void. There is no chrome: every word,
/// suggestion and control is either the orb or light it casts. A single persistent
/// orb glides between the centre (at rest) and the top (in conversation); the only
/// standing text is one breathing lowercase word.
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
    /// First-run only: nudge the user to hold the orb, then never again.
    @AppStorage("cloe.didHoldOrb") private var didHoldOrb = false

    private var theme: CloeTheme { settings.visualTheme }
    private var atRest: Bool { model.messages.isEmpty }

    /// Suggestions as motes of her light — three, never four, so it never reads as a
    /// template chip grid. The word seeds the conversation; no icons.
    private static let intentions: [OrbitIntention] = [
        OrbitIntention(word: "write",  prompt: "Help me write a short, warm message."),
        OrbitIntention(word: "plan",   prompt: "Help me plan out my day."),
        OrbitIntention(word: "wonder", prompt: "Tell me something surprising I don't already know."),
    ]

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let orbSize: CGFloat = atRest ? 196 : 104
                let orbY: CGFloat = atRest
                    ? geo.size.height * 0.44
                    : geo.safeAreaInsets.top + 52

                ZStack {
                    CloeStage(theme: theme, orbState: orbState,
                              orbCenter: UnitPoint(x: 0.5, y: orbY / max(geo.size.height, 1)))

                    Group {
                        if atRest {
                            heroContent(orbY: orbY, orbSize: orbSize, geo: geo)
                        } else {
                            conversation(orbY: orbY, orbSize: orbSize, geo: geo)
                        }
                    }
                    .transition(.opacity)

                    // The one persistent orb — glides + resizes between states so the
                    // rise is a real motion, not a flashing cross-branch swap.
                    talkableOrb(size: orbSize)
                        .position(x: geo.size.width / 2, y: orbY)

                    CloeAliveBorder(theme: theme, state: orbState, level: { currentLevel() })

                    // Soft vignette — grounds the eye toward the input without a bar.
                    if atRest {
                        LinearGradient(
                            colors: [.clear, .black.opacity(0.55)],
                            startPoint: .center, endPoint: .bottom
                        )
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                    }
                }
                .animation(CloeMotion.hero, value: atRest)
            }
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
                try? await Task.sleep(for: .seconds(1.4))
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
            }
            .sheet(item: composeBinding) { request in
                MessageComposeView(request: request) { model.pendingCompose = nil }
                    .ignoresSafeArea()
            }
        }
        .tint(theme.primary)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var chatToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            glassMark("gearshape") { showSettings = true }
        }
        ToolbarItem(placement: .topBarTrailing) {
            glassMark("clock.arrow.circlepath") { showHistory = true }
        }
        ToolbarItem(placement: .topBarTrailing) {
            if !atRest {
                glassMark("square.and.pencil") { model.clearConversation() }
                    .disabled(model.isGenerating)
            }
        }
    }

    private func glassMark(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white.opacity(0.72))
                .frame(width: 40, height: 40)
                .cloeGlassCircle(tint: theme.primary)
        }
        .buttonStyle(CloeGlassPressStyle())
    }

    // MARK: - Home (at rest)

    private func heroContent(orbY: CGFloat, orbSize: CGFloat, geo: GeometryProxy) -> some View {
        ZStack {
            OrbitingIntentions(theme: theme,
                               items: Self.intentions,
                               radius: orbSize * 0.5 + 80,
                               visible: showIntentions) { intention in
                lastSeededWord = intention.word
                seed(intention)
            }
            .position(x: geo.size.width / 2, y: orbY)
            .allowsHitTesting(showIntentions && !model.isGenerating)
            .sensoryFeedback(.selection, trigger: lastSeededWord)

            PresenceText(theme: theme, state: orbState)
                .position(x: geo.size.width / 2, y: orbY + orbSize / 2 + 74)

            // First-run discoverability — the orb's only instruction, gone for good
            // once she's been held once (or while the intentions are showing).
            if !didHoldOrb, !showIntentions, orbState == .idle {
                HoldHint(theme: theme)
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    .position(x: geo.size.width / 2, y: orbY + orbSize / 2 + 108)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: orbState)
    }

    // MARK: - Conversation

    private func conversation(orbY: CGFloat, orbSize: CGFloat, geo: GeometryProxy) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 22) {
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
                .frame(maxWidth: 340)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 28)
                .padding(.top, orbY + orbSize / 2 + 36)
                .padding(.bottom, 16)
            }
            .scrollContentBackground(.hidden)
            .scrollIndicators(.hidden)
            .mask(topFade(orbY: orbY, orbSize: orbSize, height: geo.size.height))
            .onChange(of: model.messages.count) { scrollToBottom(proxy: proxy) }
            .onChange(of: model.isGenerating) { scrollToBottom(proxy: proxy) }
            .onChange(of: model.messages.last?.content) { scrollToBottom(proxy: proxy) }
        }
    }

    /// Old turns recede into her — content fades out as it passes behind the orb.
    private func topFade(orbY: CGFloat, orbSize: CGFloat, height: CGFloat) -> LinearGradient {
        let h = max(height, 1)
        let clearTo = (orbY - orbSize * 0.2) / h
        let solidFrom = (orbY + orbSize / 2 + 24) / h
        return LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .clear, location: min(max(clearTo, 0), 1)),
                .init(color: .white, location: min(max(solidFrom, 0.01), 1)),
                .init(color: .white, location: 1),
            ],
            startPoint: .top, endPoint: .bottom
        )
    }

    // MARK: - The orb

    @ViewBuilder
    private func talkableOrb(size: CGFloat) -> some View {
        CloeOrb(theme: theme, state: orbState, pressed: orbHeld, size: size,
                level: { currentLevel() })
            .scaleEffect(orbHeld ? 1.05 : 1)
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
            // Tactile confirmation: a firm tap as she starts listening, a soft one on release.
            .sensoryFeedback(trigger: orbHeld) { _, held in
                held ? .impact(weight: .medium, intensity: 0.85)
                     : .impact(weight: .light, intensity: 0.5)
            }
    }

    /// Mic level while listening; a synthetic envelope while speaking (TTS exposes no
    /// amplitude, so driving speaking visuals off the mic would sit dead at zero).
    private func currentLevel() -> CGFloat {
        if voice.isRecording { return voice.audioLevel }
        if model.speech.isSpeaking {
            let t = Date().timeIntervalSinceReferenceDate
            let env = abs(sin(t * 5.5)) * (0.6 + 0.4 * sin(t * 1.9))
            return 0.32 + 0.32 * CGFloat(env)
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

    /// Touch a mote of her light — the word seeds the conversation.
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
        case .openChat:
            break
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
        Task {
            await model.sendMessage(text)
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.15)) {
            if let last = model.messages.last {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }
}

// MARK: - Presence text

/// The only standing text on the void: one wide-tracked lowercase word, drawn as the
/// orb's light, breathing in opacity. 'cloe' at rest; the mode while she's active.
private struct PresenceText: View {
    var theme: CloeTheme
    var state: CloeOrbState

    var body: some View {
        TimelineView(.animation) { timeline in
            let now = timeline.date.timeIntervalSinceReferenceDate
            let breath = 0.54 + 0.14 * sin(now * 0.9)
            let shimmer = 0.5 + 0.5 * sin(now * 0.35)
            Text(state.word)
                .font(.system(size: 22, weight: .ultraLight, design: .rounded))
                .tracking(12)
                .textCase(.lowercase)
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            theme.primary.opacity(breath),
                            theme.secondary.opacity(breath * 0.88),
                            theme.tertiary.opacity(breath * 0.72 * shimmer),
                        ],
                        startPoint: .leading, endPoint: .trailing
                    )
                )
                .shadow(color: theme.primary.opacity(0.55), radius: 16)
                .shadow(color: theme.secondary.opacity(0.30), radius: 32)
                .contentTransition(.opacity)
                .animation(CloeMotion.presence, value: state.word)
        }
        .frame(height: 30)
    }
}

/// First-run nudge — a breathing ring and whisper, not a label.
private struct HoldHint: View {
    var theme: CloeTheme

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let pulse = 0.5 + 0.5 * sin(t * 2.0)
            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .strokeBorder(theme.primary.opacity(0.10 + 0.14 * pulse), lineWidth: 0.75)
                        .frame(width: 22 + 6 * pulse, height: 22 + 6 * pulse)
                    Circle()
                        .fill(theme.primary.opacity(0.35 + 0.25 * pulse))
                        .frame(width: 5, height: 5)
                        .shadow(color: theme.primary.opacity(0.5), radius: 6)
                }
                Text("hold to speak")
                    .font(.system(size: 12))
                    .tracking(2.4)
                    .textCase(.lowercase)
                    .foregroundStyle(.white.opacity(0.20 + 0.12 * pulse))
            }
        }
    }
}

// MARK: - Dialogue line

/// A turn rendered as light on the void — distinguished by colour and side, not a
/// bubble. Cloe is ink; you are her theme colour. No glass cards in conversation.
private struct DialogueLine: View {
    let message: Message
    var theme: CloeTheme
    var isSpeaking: Bool
    var isWaiting: Bool
    var onSpeak: (() -> Void)?

    @State private var appeared = false

    private var isUser: Bool { message.role == .user }

    var body: some View {
        VStack(alignment: isUser ? .trailing : .leading, spacing: 8) {
            if message.content.isEmpty, isWaiting {
                TypingIndicator(theme: theme)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if !message.content.isEmpty {
                Text(message.content)
                    .font(.system(size: 17))
                    .lineSpacing(5)
                    .foregroundStyle(isUser ? theme.dialogueUser : theme.dialogueCloe)
                    .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
                    .multilineTextAlignment(isUser ? .trailing : .leading)

                if !isUser, let onSpeak {
                    Button(action: onSpeak) {
                        Image(systemName: isSpeaking ? "stop.circle" : "speaker.wave.2")
                            .font(.footnote)
                            .foregroundStyle(isSpeaking ? theme.primary : CloePalette.inkMuted)
                            .symbolEffect(.variableColor, isActive: isSpeaking)
                    }
                    .buttonStyle(.plain)
                }
            }

            if !message.actions.isEmpty {
                actionChips
            }
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : isUser ? 10 : 14)
        .scaleEffect(appeared ? 1 : 0.985, anchor: isUser ? .bottomTrailing : .bottomLeading)
        .onAppear {
            withAnimation(CloeMotion.dialogueEnter) { appeared = true }
        }
    }

    private var actionChips: some View {
        FlowLayout(spacing: 6, lineSpacing: 6) {
            ForEach(Array(message.actions.enumerated()), id: \.offset) { _, action in
                Label(action.label, systemImage: action.systemImage)
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .foregroundStyle(theme.primary)
                    .overlay {
                        Capsule().strokeBorder(theme.primary.opacity(0.35), lineWidth: 0.75)
                    }
            }
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
    }
}

// MARK: - Glass press

private struct CloeGlassPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.90 : 1)
            .opacity(configuration.isPressed ? 0.78 : 1)
            .animation(CloeMotion.glassPress, value: configuration.isPressed)
    }
}
