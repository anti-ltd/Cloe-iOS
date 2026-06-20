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

struct ChatView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings
    @State private var input = ""
    @State private var showSettings = false
    @State private var showHistory = false
    @State private var voice = VoiceInput()

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        if model.messages.isEmpty {
                            emptyState
                        }
                        ForEach(model.messages) { message in
                            MessageBubble(
                                message: message,
                                isSpeaking: model.speech.isSpeaking(message.content),
                                // The last bubble hosts the typing dots while the reply is
                                // still empty — no separate indicator bubble below it.
                                isWaiting: model.isGenerating && message.id == model.messages.last?.id,
                                onSpeak: message.role == .assistant
                                    ? { model.speech.toggle(message.content) }
                                    : nil
                            )
                            .id(message.id)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 12)
                }
                // Scroll on new messages, state changes, and every streamed token
                .onChange(of: model.messages.count) { scrollToBottom(proxy: proxy) }
                .onChange(of: model.isGenerating) { scrollToBottom(proxy: proxy) }
                .onChange(of: model.messages.last?.content) { scrollToBottom(proxy: proxy) }
                // InputBar floats over scroll content — no opaque background needed
                .safeAreaInset(edge: .bottom) {
                    InputBar(input: $input,
                             isRecording: voice.isRecording,
                             onMicDown: { voice.startHold() },
                             onMicUp: { voice.endHold() },
                             onSend: send)
                }
                // Mirror the live transcript into the field while the user talks.
                .onChange(of: voice.transcript) { _, newValue in
                    if voice.isRecording, !newValue.isEmpty { input = newValue }
                }
                // Talk, pause → recording auto-stops and the transcript auto-sends.
                .onAppear {
                    voice.onAutoSubmit = { send() }
                    voice.silenceInterval = settings.dictationSilence
                    // A deep link / Control Center tap may have set an action before
                    // the view appeared.
                    model.consumePendingIntent()
                    handleQuickAction(model.pendingQuickAction)
                }
                .onChange(of: settings.dictationSilence) { _, newValue in
                    voice.silenceInterval = newValue
                }
                // Live Activity tap arrived while the chat was already open.
                .onChange(of: model.pendingQuickAction) { _, action in
                    handleQuickAction(action)
                }
            }
            .navigationTitle("Apple Intelligence")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showSettings = true } label: {
                        Image(systemName: "gear")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showHistory = true } label: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if !model.messages.isEmpty {
                        Button("Clear") { model.clearConversation() }
                            .disabled(model.isGenerating)
                    }
                }
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
    }

    /// Bridges `AppModel.pendingCompose` to a `.sheet(item:)` binding for the
    /// Messages compose sheet.
    private var composeBinding: Binding<ComposeRequest?> {
        Binding(get: { model.pendingCompose }, set: { model.pendingCompose = $0 })
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("On Device AI")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    /// Act on a quick-access intent from a Live Activity tap, Siri, a Shortcut, or the
    /// Action Button. `voice.toggle()` records in non-hold mode so a silent gap
    /// auto-stops and auto-sends — exactly what a hands-free mic tap should do.
    private func handleQuickAction(_ action: AppModel.QuickAction?) {
        guard let action else { return }
        model.pendingQuickAction = nil
        switch action {
        case .openChat:
            break  // already here
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
