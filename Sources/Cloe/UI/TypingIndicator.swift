import SwiftUI

#Preview {
    ZStack {
        CloeStage()
        TypingIndicator(theme: .aurora)
            .padding()
    }
}

/// Minimal typing indicator — three dots, one lightweight animation.
struct TypingIndicator: View {
    var theme: CloeTheme = .original

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 15.0)) { timeline in
            let phase = timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: 5) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(CloePalette.inkMuted.opacity(0.35 + 0.45 * dotOpacity(phase, index: i)))
                        .frame(width: 6, height: 6)
                }
            }
        }
    }

    private func dotOpacity(_ t: Double, index: Int) -> Double {
        0.5 + 0.5 * sin(t * 3.5 + Double(index) * 0.9)
    }
}
