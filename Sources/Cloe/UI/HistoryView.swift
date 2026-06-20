import SwiftUI

#Preview {
    let model = AppModel()
    return HistoryView().environment(model)
}

/// Past-conversation list. Tap to open, swipe to delete, "+" to start fresh.
struct HistoryView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    private var saved: [Conversation] {
        // Hide the empty just-started thread from the list.
        model.conversations.filter { !$0.messages.isEmpty }
    }

    var body: some View {
        NavigationStack {
            Group {
                if saved.isEmpty {
                    ContentUnavailableView(
                        "No Conversations",
                        systemImage: "bubble.left.and.bubble.right",
                        description: Text("Your chats are saved on-device and appear here.")
                    )
                } else {
                    List {
                        ForEach(saved) { convo in
                            Button {
                                model.selectConversation(convo.id)
                                dismiss()
                            } label: {
                                row(convo)
                            }
                            .tint(.primary)
                        }
                        .onDelete { offsets in
                            offsets.map { saved[$0].id }.forEach(model.deleteConversation)
                        }
                    }
                }
            }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        model.newConversation()
                        dismiss()
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .disabled(model.isGenerating)
                }
            }
        }
    }

    private func row(_ convo: Conversation) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(convo.title.isEmpty ? "New Conversation" : convo.title)
                .font(.body)
                .lineLimit(1)
            HStack(spacing: 6) {
                if convo.id == model.currentConversationID {
                    Text("Current")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tint)
                }
                Text(convo.updatedAt, format: .relative(presentation: .named))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
