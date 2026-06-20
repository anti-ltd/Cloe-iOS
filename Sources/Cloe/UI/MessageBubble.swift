import SwiftUI

#Preview("User") {
    MessageBubble(message: Message(role: .user, content: "Hey, what's the capital of France?"))
        .padding()
}

#Preview("Assistant") {
    MessageBubble(message: Message(role: .assistant, content: "The capital of France is Paris."),
                  isSpeaking: false, onSpeak: {})
        .padding()
}

#Preview("With actions") {
    MessageBubble(message: Message(role: .assistant,
                                   content: "Done — flashlight is on and I gave you a little buzz.",
                                   actions: [.torch(.on), .haptic(.success)]),
                  isSpeaking: true, onSpeak: {})
        .padding()
}

struct MessageBubble: View {
    let message: Message
    /// `true` when this exact message is being read aloud right now.
    var isSpeaking: Bool = false
    /// `true` while the model is still generating this (assistant) reply — shows the
    /// typing dots inside the bubble until the first text streams in.
    var isWaiting: Bool = false
    /// Non-nil for assistant messages — toggles speech for this bubble.
    var onSpeak: (() -> Void)? = nil

    var isUser: Bool { message.role == .user }

    var body: some View {
        VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
            // A tag-first reply fires its action before any prose streams in. Rather than
            // show a stray blank pill, the bubble hosts the typing dots until text arrives —
            // dots and text share one bubble, with the action chip below it.
            if message.content.isEmpty, !isUser, isWaiting {
                TypingIndicator()
            } else if !message.content.isEmpty {
                HStack(alignment: .bottom, spacing: 6) {
                    if isUser { Spacer(minLength: 60) }

                    Text(message.content)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(isUser ? Color.accentColor : Color(.secondarySystemBackground))
                        .foregroundStyle(isUser ? .white : .primary)
                        .clipShape(RoundedRectangle(cornerRadius: 18))

                    if !isUser, let onSpeak {
                        Button(action: onSpeak) {
                            Image(systemName: isSpeaking ? "stop.circle.fill" : "speaker.wave.2.fill")
                                .font(.system(size: 17))
                                .foregroundStyle(isSpeaking ? Color.accentColor : .secondary)
                                .symbolEffect(.variableColor, isActive: isSpeaking)
                        }
                        .buttonStyle(.plain)
                    }

                    if !isUser { Spacer(minLength: 60) }
                }
            }

            if !message.actions.isEmpty {
                actionChips
            }
        }
    }

    private var actionChips: some View {
        HStack(spacing: 6) {
            ForEach(Array(message.actions.enumerated()), id: \.offset) { _, action in
                Label(action.label, systemImage: action.systemImage)
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.15))
                    .foregroundStyle(Color.accentColor)
                    .clipShape(Capsule())
            }
        }
    }
}
