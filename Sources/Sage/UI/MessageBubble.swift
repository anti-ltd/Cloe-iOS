import SwiftUI

#Preview("User") {
    MessageBubble(message: Message(role: .user, content: "Hey, what's the capital of France?"))
        .padding()
}

#Preview("Assistant") {
    MessageBubble(message: Message(role: .assistant, content: "The capital of France is Paris."))
        .padding()
}

#Preview("Long") {
    MessageBubble(message: Message(role: .assistant, content: "Sure! Here's a brief overview: Paris is one of the world's great cities, renowned for the Eiffel Tower, the Louvre, and its café culture. It's been the capital since the late 10th century."))
        .padding()
}

struct MessageBubble: View {
    let message: Message

    var isUser: Bool { message.role == .user }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 60) }
            Text(message.content)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(isUser ? Color.accentColor : Color(.secondarySystemBackground))
                .foregroundStyle(isUser ? .white : .primary)
                .clipShape(RoundedRectangle(cornerRadius: 18))
            if !isUser { Spacer(minLength: 60) }
        }
    }
}
