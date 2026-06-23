import SwiftUI

#Preview("Resting") {
    ZStack(alignment: .bottom) {
        CloeStage()
        InputBar(input: .constant(""), onSend: {})
    }
}

#Preview("Typing") {
    ZStack(alignment: .bottom) {
        CloeStage(theme: .aurora)
        InputBar(input: .constant("what's the weather like"), theme: .aurora, onSend: {})
    }
}

#Preview("Recording") {
    ZStack(alignment: .bottom) {
        CloeStage(theme: .ocean)
        InputBar(input: .constant(""), theme: .ocean, isRecording: true, onSend: {})
    }
}

/// Clean input bar — surface pill, no animated blooms or glowing motes.
struct InputBar: View {
    @Binding var input: String
    var theme: CloeTheme = .original
    var isRecording: Bool = false
    var level: () -> CGFloat = { 1 }
    let onSend: () -> Void

    @FocusState private var focused: Bool

    private var isEmpty: Bool {
        input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    private var showsSend: Bool { !isEmpty && !isRecording }

    var body: some View {
        Group {
            if isRecording {
                recordingBar
            } else {
                writeBar
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .padding(.bottom, 4)
    }

    private var recordingBar: some View {
        VoiceWave(theme: theme, active: true, level: level, barCount: 40, height: 36)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
    }

    private var writeBar: some View {
        HStack(alignment: .bottom, spacing: 10) {
            ZStack(alignment: .leading) {
                if isEmpty, !focused {
                    Text("Message Cloe…")
                        .font(CloeTypography.body)
                        .foregroundStyle(CloePalette.inkMuted)
                        .allowsHitTesting(false)
                }

                TextField("", text: $input, axis: .vertical)
                    .lineLimit(1...5)
                    .focused($focused)
                    .font(CloeTypography.body)
                    .tint(theme.primary)
                    .foregroundStyle(CloePalette.ink)
                    .onSubmit(onSend)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(CloePalette.surface)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(CloePalette.separator, lineWidth: 0.5)
            }

            if showsSend {
                Button(action: onSend) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(theme.primary)
                }
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(CloeMotion.sendMote, value: showsSend)
    }
}
