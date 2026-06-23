import SwiftUI

#Preview {
    let model = AppModel()
    return HistoryView()
        .environment(model)
        .environment(model.settings)
}

struct HistoryView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    private var saved: [Conversation] {
        model.conversations.filter { !$0.messages.isEmpty }
    }

    var body: some View {
        CloeSheetChrome(title: "History", dismiss: { dismiss() }) {
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
                    .scrollContentBackground(.hidden)
                }
            }
            .toolbar {
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
        .tint(settings.visualTheme.primary)
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
