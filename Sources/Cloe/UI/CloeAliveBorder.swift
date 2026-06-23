import SwiftUI

/// Smooths only the live voice level — state expansion is handled separately
/// by a spring so entering listen/speak reads as one deliberate swell.
private final class AliveLevelSmoother {
    private var level: Double = 0

    func tick(_ raw: Double) -> Double {
        let alpha = raw > level ? 0.06 : 0.04
        level += (raw - level) * alpha
        return level
    }
}

/// Living perimeter glow — a conic spectrum stroked along the screen edge, blurred
/// into a soft rim. Colours sweep *around* the bezel (not solid wedges on each side).
/// Rests as a hairline at idle; springs thicker when Cloe listens, thinks, or speaks.
struct CloeAliveBorder: View {
    var theme: CloeTheme = .original
    var state: CloeOrbState = .idle
    /// Live level 0…1 — mic while listening, synthetic envelope while speaking.
    var level: () -> CGFloat = { 0 }

    /// 0 at idle → 1 when fully active. Spring-animated on state changes.
    @State private var activeAmount: CGFloat = 0
    @State private var levelSmoother = AliveLevelSmoother()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let now = timeline.date.timeIntervalSinceReferenceDate
            let lvl = levelSmoother.tick(Double(min(1, max(0, level()))))
            let breathe = 0.5 + 0.5 * sin(now * 0.45)

            // Stroke width before blur — the blur is what blooms inward.
            let rim = 3 + activeAmount * 14 + CGFloat(lvl) * 4
            let blur = 6 + activeAmount * 12 + CGFloat(lvl) * 3
            let intensity = 0.16 + Double(activeAmount) * 0.28
                + lvl * 0.12
                + (state == .thinking ? breathe * 0.04 : 0)
            let spin = now * 0.010

            GeometryReader { geo in
                Rectangle()
                    .strokeBorder(
                        AngularGradient(
                            gradient: Gradient(colors: spectrum),
                            center: .center,
                            angle: .degrees(spin * 360)
                        ),
                        lineWidth: rim
                    )
                    .blur(radius: blur)
                    .opacity(intensity)
                    .frame(width: geo.size.width, height: geo.size.height)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .onAppear { activeAmount = Self.activeAmount(for: state) }
        .onChange(of: state) { _, newState in
            withAnimation(CloeMotion.rimSwell) {
                activeAmount = Self.activeAmount(for: newState)
            }
        }
    }

    /// Slightly softened so the rim reads luminous, not neon.
    private var spectrum: [Color] {
        theme.aliveSpectrum.map { $0.opacity(0.82) }
    }

    private static func activeAmount(for state: CloeOrbState) -> CGFloat {
        switch state {
        case .idle: 0
        case .listening: 1.0
        case .thinking: 0.55
        case .speaking: 1.0
        }
    }
}

#Preview("States") {
    struct Demo: View {
        @State private var state: CloeOrbState = .idle
        var body: some View {
            ZStack {
                Color.black.ignoresSafeArea()
                CloeAliveBorder(theme: .original, state: state, level: { state == .idle ? 0 : 0.55 })
                VStack {
                    Spacer()
                    HStack {
                        ForEach([CloeOrbState.idle, .listening, .thinking, .speaking], id: \.self) { s in
                            Button(s.word) { state = s }
                                .buttonStyle(.bordered)
                        }
                    }
                    .padding()
                }
            }
        }
    }
    return Demo()
}
