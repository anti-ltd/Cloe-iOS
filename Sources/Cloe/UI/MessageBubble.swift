import SwiftUI
import iUXiOS

#Preview("User") {
    MessageBubble(message: Message(role: .user, content: "Hey, what's the capital of France?"))
        .padding()
        .background { CloeStage() }
}

#Preview("Assistant") {
    MessageBubble(message: Message(role: .assistant, content: "The capital of France is Paris."),
                  isSpeaking: false, onSpeak: {})
        .padding()
        .background { CloeStage() }
}

struct MessageBubble: View {
    let message: Message
    var theme: CloeTheme = .original
    var isSpeaking: Bool = false
    var isWaiting: Bool = false
    var onSpeak: (() -> Void)? = nil

    var isUser: Bool { message.role == .user }

    var body: some View {
        if isUser {
            userMessage
        } else {
            assistantMessage
        }
    }

    private var userMessage: some View {
        HStack {
            Spacer(minLength: 48)
            Text(message.content)
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .foregroundStyle(.white)
                .background(theme.brand, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(.white.opacity(0.22), lineWidth: 0.5)
                }
                .shadow(color: theme.primary.opacity(0.40), radius: 12, y: 5)
        }
    }

    private var assistantMessage: some View {
        VStack(alignment: .leading, spacing: 10) {
            if message.content.isEmpty, isWaiting {
                TypingIndicator(theme: theme)
            } else if !message.content.isEmpty {
                Text(message.content)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let onSpeak {
                    Button(action: onSpeak) {
                        Label(isSpeaking ? "Stop" : "Speak",
                              systemImage: isSpeaking ? "stop.circle.fill" : "speaker.wave.2.fill")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(isSpeaking ? theme.primary : .secondary)
                            .symbolEffect(.variableColor, isActive: isSpeaking)
                    }
                    .buttonStyle(.plain)
                }
            }

            if !message.actions.isEmpty {
                actionChips
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cloeGlass(cornerRadius: 24, tint: theme.primary.opacity(0.6))
        .overlay(alignment: .leading) {
            Capsule()
                .fill(theme.brand)
                .frame(width: 3)
                .padding(.vertical, 14)
                .padding(.leading, 2)
                .shadow(color: theme.primary.opacity(0.5), radius: 4, y: 0)
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var actionChips: some View {
        FlowLayout(spacing: 6, lineSpacing: 6) {
            ForEach(Array(message.actions.enumerated()), id: \.offset) { _, action in
                Label(action.label, systemImage: action.systemImage)
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(theme.primary.opacity(0.16))
                    .foregroundStyle(theme.primary)
                    .clipShape(Capsule())
                    .overlay {
                        Capsule().strokeBorder(theme.primary.opacity(0.22), lineWidth: 0.5)
                    }
            }
        }
    }
}
