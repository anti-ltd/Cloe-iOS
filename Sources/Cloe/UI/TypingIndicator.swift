import SwiftUI

#Preview {
    ZStack {
        CloeStage()
        TypingIndicator(theme: .aurora)
            .padding()
    }
}

/// Three prismatic motes — orbiting light, not generic dots.
struct TypingIndicator: View {
    var theme: CloeTheme = .original

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { i in
                    let phase = t * 2.4 + Double(i) * 0.85
                    let pulse = 0.5 + 0.5 * sin(phase)
                    let scale = 0.72 + 0.48 * pulse
                    let colors = theme.blobColors

                    ZStack {
                        Circle()
                            .fill(colors[i % colors.count].opacity(0.35 * pulse))
                            .frame(width: 14, height: 14)
                            .blur(radius: 4)
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [
                                        .white.opacity(0.85 + 0.15 * pulse),
                                        colors[i % colors.count].opacity(0.7),
                                        .clear,
                                    ],
                                    center: .center, startRadius: 0, endRadius: 5
                                )
                            )
                            .frame(width: 7, height: 7)
                            .scaleEffect(scale)
                            .shadow(color: colors[i % colors.count].opacity(0.6 * pulse), radius: 8)
                    }
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 4)
        }
    }
}
