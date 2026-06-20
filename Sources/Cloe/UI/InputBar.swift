import SwiftUI

#Preview("Empty") {
    ZStack(alignment: .bottom) {
        Color(.systemGroupedBackground).ignoresSafeArea()
        InputBar(input: .constant(""), isRecording: false, onSend: {})
    }
}

#Preview("Recording") {
    ZStack(alignment: .bottom) {
        Color(.systemGroupedBackground).ignoresSafeArea()
        InputBar(input: .constant("turn on the flashlight"), isRecording: true, onSend: {})
    }
}

struct InputBar: View {
    @Binding var input: String
    var isRecording: Bool = false
    /// Finger pressed down on the mic — start recording.
    var onMicDown: () -> Void = {}
    /// Finger lifted off the mic — stop recording and submit.
    var onMicUp: () -> Void = {}
    let onSend: () -> Void

    /// Tracks the press so the start fires once per hold (gesture `onChanged` repeats).
    @State private var micPressed = false

    private var isEmpty: Bool {
        input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Show the send arrow only when there's typed text and we're not recording;
    /// otherwise the trailing control is the press-and-hold mic.
    private var showsSend: Bool { !isEmpty && !isRecording }

    /// Press-and-hold: down starts recording, release stops + submits.
    private var pttGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                if !micPressed { micPressed = true; onMicDown() }
            }
            .onEnded { _ in
                micPressed = false
                onMicUp()
            }
    }

    var body: some View {
        if #available(iOS 26.0, *) {
            glassBar
        } else {
            classicBar
        }
    }

    // MARK: - iOS 26 liquid glass

    @available(iOS 26.0, *)
    private var glassBar: some View {
        GlassEffectContainer {
            HStack(spacing: 8) {
                TextField(isRecording ? "Listening…" : "Message", text: $input, axis: .vertical)
                    .lineLimit(1...5)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .onSubmit(onSend)
                    .glassEffect(in: RoundedRectangle(cornerRadius: 22, style: .continuous))

                if showsSend {
                    Button(action: onSend) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 15, weight: .bold))
                            .frame(width: 36, height: 36)
                    }
                    .foregroundStyle(.white)
                    .glassEffect(.regular.tint(.accentColor), in: Circle())
                } else {
                    // Hold to talk, release to send.
                    Image(systemName: isRecording ? "waveform" : "mic.fill")
                        .font(.system(size: 15, weight: .bold))
                        .frame(width: 36, height: 36)
                        .foregroundStyle(isRecording ? .white : Color.secondary)
                        .glassEffect(isRecording ? .regular.tint(.red) : .regular, in: Circle())
                        .scaleEffect(micPressed ? 1.18 : 1)
                        .animation(.spring(response: 0.25, dampingFraction: 0.6), value: micPressed)
                        .contentShape(Circle())
                        .gesture(pttGesture)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .padding(.bottom, 4)
    }

    // MARK: - Classic fallback (< iOS 26)

    private var classicBar: some View {
        HStack(spacing: 8) {
            TextField(isRecording ? "Listening…" : "Message", text: $input, axis: .vertical)
                .lineLimit(1...5)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .onSubmit(onSend)

            if showsSend {
                Button(action: onSend) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(Color.accentColor)
                }
            } else {
                // Hold to talk, release to send.
                Image(systemName: isRecording ? "waveform.circle.fill" : "mic.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(isRecording ? .red : Color.secondary)
                    .scaleEffect(micPressed ? 1.18 : 1)
                    .animation(.spring(response: 0.25, dampingFraction: 0.6), value: micPressed)
                    .contentShape(Circle())
                    .gesture(pttGesture)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.bar)
    }
}
