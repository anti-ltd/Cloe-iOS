import SwiftUI

#Preview("Empty") {
    InputBar(input: .constant(""), onSend: {})
}

#Preview("With text") {
    InputBar(input: .constant("What's the weather like today?"), onSend: {})
}

struct InputBar: View {
    @Binding var input: String
    let onSend: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            TextField("Message", text: $input, axis: .vertical)
                .lineLimit(1...5)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .onSubmit(onSend)

            Button(action: onSend) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.secondary : Color.accentColor)
            }
            .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
    }
}
