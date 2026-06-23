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
        CloeStage(theme: .ocean, orbState: .listening)
        InputBar(input: .constant(""), theme: .ocean, isRecording: true, onSend: {})
    }
}

/// Presence input — no glass, no pill. At rest it's a single dim line of the orb's
/// light reading "speak, or write"; tap and it becomes drawn-light text with a
/// glowing send mote. While recording it's a bare prism waveform on the void.
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
    private var resting: Bool { isEmpty && !focused }
    private var engaged: Bool { focused || !isEmpty }

    var body: some View {
        if isRecording {
            recordingBar
        } else {
            writeBar
        }
    }

    /// Full-width waveform only — light reacting to the mic, sitting on the stage.
    private var recordingBar: some View {
        VoiceWave(theme: theme, active: true, level: level, barCount: 52, height: 44)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .padding(.bottom, 4)
    }

    private var writeBar: some View {
        HStack(alignment: .bottom, spacing: 12) {
            ZStack {
                TextField("", text: $input, axis: .vertical)
                    .lineLimit(1...5)
                    .focused($focused)
                    .font(.system(size: 17))
                    .tint(theme.primary)
                    .foregroundStyle(CloePalette.ink)
                    .multilineTextAlignment(.leading)
                    .onSubmit(onSend)

                if resting {
                    restingPrompt
                        .allowsHitTesting(false)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { focused = true }

            if showsSend {
                sendMote
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
            }
        }
        .padding(.horizontal, engaged ? 22 : 28)
        .padding(.vertical, engaged ? 16 : 12)
        .padding(.bottom, 4)
        .background { focusBloom }
        .animation(CloeMotion.inputFocus, value: engaged)
        .animation(CloeMotion.sendMote, value: showsSend)
        .animation(.smooth(duration: 0.3), value: resting)
    }

    /// Soft radial bloom that rises when the user engages — draws the eye without a box.
    private var focusBloom: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let pulse = engaged ? 0.55 + 0.12 * sin(t * 1.4) : 0.28 + 0.08 * sin(t * 0.9)
            RadialGradient(
                colors: [
                    theme.primary.opacity(pulse * (engaged ? 0.22 : 0.10)),
                    theme.secondary.opacity(pulse * (engaged ? 0.10 : 0.04)),
                    .clear,
                ],
                center: .bottom,
                startRadius: 0,
                endRadius: engaged ? 280 : 200
            )
        }
        .allowsHitTesting(false)
    }

    /// Resting placeholder — pulsing cursor line + inviting copy.
    private var restingPrompt: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let pulse = 0.42 + 0.58 * (0.5 + 0.5 * sin(t * 2.1))
            VStack(spacing: 9) {
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                theme.primary.opacity(0.25 + 0.55 * pulse),
                                theme.secondary.opacity(0.18 + 0.42 * pulse),
                            ],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                    .frame(width: 72 + 14 * pulse, height: 2.5)
                    .shadow(color: theme.primary.opacity(0.35 * pulse), radius: 8)
                Text("speak, or write")
                    .font(.system(size: 13))
                    .tracking(2.2)
                    .textCase(.lowercase)
                    .foregroundStyle(.white.opacity(0.22 + 0.10 * pulse))
            }
            .frame(maxWidth: .infinity)
        }
    }

    /// Glowing send mote — a prism ring that blooms when text is ready.
    private var sendMote: some View {
        Button(action: onSend) {
            ZStack {
                Circle()
                    .fill(theme.primary.opacity(0.14))
                    .frame(width: 44, height: 44)
                    .blur(radius: 6)
                Circle()
                    .strokeBorder(theme.primary.opacity(0.45), lineWidth: 0.75)
                    .frame(width: 36, height: 36)
                Image(systemName: "arrow.up")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(theme.primary)
                    .shadow(color: theme.primary.opacity(0.85), radius: 10)
            }
            .frame(width: 44, height: 44)
        }
        .buttonStyle(SendMotePressStyle())
        .sensoryFeedback(.impact(weight: .light, intensity: 0.7), trigger: showsSend)
    }
}

// MARK: - Send press

private struct SendMotePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.88 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(CloeMotion.intentionPress, value: configuration.isPressed)
    }
}
