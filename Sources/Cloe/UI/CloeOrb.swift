import SwiftUI

// Cloe's orb — a living liquid-glass plasma. Layered passes: a soft nebula body,
// a hot molten core, swirling energy filaments, a chromatic Fresnel rim, a
// specular gloss, and twinkling orbiting sparkles. The whole thing breathes,
// shimmers, and reacts to the mic level so speaking visibly lights it up.

/// What the orb is expressing. The chat maps app state → mood.
enum CloeOrbState: Equatable {
    case idle, listening, thinking, speaking

    var speed: Double {
        switch self {
        case .idle: 0.48
        case .listening: 0.85
        case .thinking: 1.20
        case .speaking: 0.92
        }
    }

    var churn: CGFloat {
        switch self {
        case .idle: 1.0
        case .listening: 1.18
        case .thinking: 1.32
        case .speaking: 1.12
        }
    }

    var glow: Double {
        switch self {
        case .idle: 0.85
        case .listening: 0.95
        case .thinking: 1.0
        case .speaking: 0.92
        }
    }

    var breath: CGFloat {
        switch self {
        case .idle: 0.035
        case .listening: 0.05
        case .thinking: 0.06
        case .speaking: 0.042
        }
    }

    /// How energetic the filaments + sparkles run.
    var energy: Double {
        switch self {
        case .idle: 0.55
        case .listening: 0.9
        case .thinking: 1.0
        case .speaking: 0.85
        }
    }

    var caption: String? {
        switch self {
        case .idle: nil
        case .listening: "Listening…"
        case .thinking: "Thinking…"
        case .speaking: "Speaking…"
        }
    }

    /// One lowercase word for the Presence layout — the orb's own name at rest,
    /// the mode while active. No "…", no status-label voice.
    var word: String {
        switch self {
        case .idle: "cloe"
        case .listening: "listening"
        case .thinking: "thinking"
        case .speaking: "speaking"
        }
    }
}

// MARK: - The orb

struct CloeOrb: View {
    var theme: CloeTheme = .original
    var state: CloeOrbState = .idle
    var pressed: Bool = false
    var size: CGFloat = 120
    var halo: Bool = true
    /// Live mic / output level 0…1 — pumps glow, bloom and sparkle when speaking.
    var level: () -> CGFloat = { 0 }

    /// Hero orb runs the full canvas; compact uses a static gradient (no GPU churn).
    private var live: Bool { size >= 100 }

    /// Below this the fancy surface detail is skipped (tiny settings swatch).
    private var rich: Bool { size >= 52 && live }

    private struct Blob {
        let colorIndex: Int
        let phase, rate, wobble: Double
        let orbit, radius: CGFloat
        let ellipY: CGFloat
    }

    /// Each blob orbits on its own Lissajous path — together they read as liquid colour.
    private static let blobs: [Blob] = [
        Blob(colorIndex: 0, phase: 0.0, rate: 0.68, wobble: 1.05, orbit: 0.22, radius: 0.40, ellipY: 1.0),
        Blob(colorIndex: 1, phase: 1.3, rate: 0.88, wobble: 1.25, orbit: 0.18, radius: 0.36, ellipY: 1.14),
        Blob(colorIndex: 2, phase: 2.6, rate: 0.52, wobble: 0.92, orbit: 0.24, radius: 0.34, ellipY: 0.88),
        Blob(colorIndex: 3, phase: 3.9, rate: 0.98, wobble: 1.15, orbit: 0.16, radius: 0.32, ellipY: 1.06),
        Blob(colorIndex: 4, phase: 5.1, rate: 0.74, wobble: 1.35, orbit: 0.20, radius: 0.30, ellipY: 0.96),
        Blob(colorIndex: 5, phase: 0.8, rate: 1.15, wobble: 1.5, orbit: 0.10, radius: 0.24, ellipY: 1.0),
    ]

    private struct Spark {
        let phase, rate, twPhase, twRate: Double
        let orbit, ellipY: CGFloat
        let big: Bool
    }

    /// Sparkles ride slow orbits and twinkle on their own clock.
    private static let sparks: [Spark] = [
        Spark(phase: 0.0, rate: 0.31, twPhase: 0.0, twRate: 2.3, orbit: 0.30, ellipY: 0.94, big: true),
        Spark(phase: 0.9, rate: -0.24, twPhase: 1.1, twRate: 3.1, orbit: 0.40, ellipY: 1.06, big: false),
        Spark(phase: 1.7, rate: 0.42, twPhase: 2.4, twRate: 2.7, orbit: 0.36, ellipY: 0.9, big: false),
        Spark(phase: 2.5, rate: -0.36, twPhase: 0.6, twRate: 3.6, orbit: 0.46, ellipY: 1.0, big: true),
        Spark(phase: 3.2, rate: 0.27, twPhase: 3.0, twRate: 2.1, orbit: 0.33, ellipY: 1.1, big: false),
        Spark(phase: 4.0, rate: -0.45, twPhase: 1.8, twRate: 4.0, orbit: 0.42, ellipY: 0.96, big: false),
        Spark(phase: 4.8, rate: 0.33, twPhase: 2.0, twRate: 2.9, orbit: 0.50, ellipY: 1.04, big: true),
        Spark(phase: 5.4, rate: -0.29, twPhase: 0.3, twRate: 3.3, orbit: 0.38, ellipY: 0.92, big: false),
        Spark(phase: 0.4, rate: 0.38, twPhase: 4.2, twRate: 2.5, orbit: 0.52, ellipY: 1.0, big: false),
        Spark(phase: 2.1, rate: -0.32, twPhase: 5.0, twRate: 3.8, orbit: 0.44, ellipY: 1.08, big: false),
        Spark(phase: 3.6, rate: 0.49, twPhase: 1.4, twRate: 2.2, orbit: 0.28, ellipY: 0.98, big: false),
        Spark(phase: 5.0, rate: -0.4, twPhase: 3.7, twRate: 3.4, orbit: 0.48, ellipY: 1.02, big: true),
    ]

    var body: some View {
        Group {
            if live {
                liveOrb
            } else {
                compactOrb
            }
        }
        .frame(width: size, height: size)
        .animation(.smooth(duration: 0.5), value: state)
        .animation(.smooth(duration: 0.25), value: pressed)
    }

    /// Static gradient sphere — used in conversation header and small swatches.
    private var compactOrb: some View {
        let colors = theme.blobColors
        return ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            colors[0].opacity(0.95),
                            colors[1].opacity(0.75),
                            colors[2].opacity(0.45),
                        ],
                        center: UnitPoint(x: 0.38, y: 0.32),
                        startRadius: 0,
                        endRadius: size * 0.55
                    )
                )
            Circle()
                .strokeBorder(.white.opacity(0.14), lineWidth: 0.5)
            if state != .idle {
                Circle()
                    .strokeBorder(theme.primary.opacity(0.55), lineWidth: 1.5)
                    .padding(2)
            }
        }
    }

    private var liveOrb: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            let now = timeline.date.timeIntervalSinceReferenceDate
            let lvl = clampedLevel()
            let t = now * state.speed * (pressed ? 1.18 : 1)
            let breath = 1 + CGFloat(sin(now * 1.35)) * state.breath + CGFloat(lvl) * 0.06

            ZStack {
                if halo { outerBloom(now: now, lvl: lvl) }
                liquid(t: t, lvl: lvl)
                    .saturation(1.12)
                    .scaleEffect(breath)
                    .mask(edgeMask)
                if rich {
                    surface(now: now, t: t, lvl: lvl)
                        .scaleEffect(breath)
                }
            }
            .compositingGroup()
        }
    }

    private func clampedLevel() -> CGFloat {
        min(1, max(0, level()))
    }

    /// Full-strength centre, fade only at the outer rim — keeps colour vivid inside.
    private var edgeMask: some View {
        RadialGradient(
            stops: [
                .init(color: .white, location: 0),
                .init(color: .white, location: 0.62),
                .init(color: .white.opacity(0.78), location: 0.80),
                .init(color: .white.opacity(0.30), location: 0.92),
                .init(color: .clear, location: 1.0),
            ],
            center: .center,
            startRadius: 0,
            endRadius: size * 0.52
        )
    }

    // MARK: Liquid body — soft nebula + molten core + energy filaments

    private func liquid(t: Double, lvl: CGFloat) -> some View {
        let colors = theme.blobColors
        let churn = state.churn * (pressed ? 1.08 : 1)
        let intensity = state.glow * (pressed ? 1.06 : 1) + Double(lvl) * 0.22
        let energy = state.energy + Double(lvl) * 0.4

        return Canvas { ctx, canvas in
            let s = min(canvas.width, canvas.height)
            let mid = CGPoint(x: canvas.width / 2, y: canvas.height / 2)

            // Dense luminous body FIRST — fills the whole disc so the orb reads as a
            // solid sphere of light, never a bright rim around a dark void.
            drawBody(ctx, s: s, mid: mid, colors: colors, t: t, intensity: intensity)
            drawNebula(ctx, s: s, mid: mid, colors: colors, t: t,
                       churn: churn, intensity: intensity, blur: s * 0.052,
                       scale: 1.0, peak: 0.88, mantle: 0.50)
            drawNebula(ctx, s: s, mid: mid, colors: colors, t: t,
                       churn: churn * 0.82, intensity: intensity * 1.1, blur: s * 0.020,
                       scale: 0.58, peak: 1.0, mantle: 0.42)
            if rich {
                drawFilaments(ctx, s: s, mid: mid, colors: colors, t: t,
                              energy: energy, intensity: intensity)
            }
        }
    }

    /// A soft sphere of theme colour that fills the disc edge-to-edge so the moving
    /// blobs read as currents inside a body of light — not a sparse flare on black.
    private func drawBody(_ ctx: GraphicsContext, s: CGFloat, mid: CGPoint,
                          colors: [Color], t: Double, intensity: Double) {
        ctx.drawLayer { layer in
            layer.addFilter(.blur(radius: s * 0.03))
            layer.blendMode = .plusLighter
            // Slow drift so the body breathes rather than sitting flat.
            let drift = CGFloat(sin(t * 0.4)) * s * 0.03
            let c = CGPoint(x: mid.x + drift, y: mid.y - drift * 0.6)
            let r = s * 0.50
            layer.fill(
                Path(ellipseIn: CGRect(x: mid.x - r, y: mid.y - r, width: 2 * r, height: 2 * r)),
                with: .radialGradient(
                    Gradient(stops: [
                        .init(color: colors[1].opacity(0.55 * intensity), location: 0.0),
                        .init(color: colors[0].opacity(0.42 * intensity), location: 0.34),
                        .init(color: colors[2].opacity(0.24 * intensity), location: 0.64),
                        .init(color: colors[0].opacity(0.08 * intensity), location: 0.86),
                        .init(color: .clear, location: 1.0),
                    ]),
                    center: c, startRadius: 0, endRadius: r
                )
            )
        }
    }

    /// One additive blur pass of orbiting radial blobs.
    private func drawNebula(_ ctx: GraphicsContext, s: CGFloat, mid: CGPoint,
                            colors: [Color], t: Double, churn: CGFloat,
                            intensity: Double, blur: CGFloat,
                            scale: CGFloat, peak: Double, mantle: Double) {
        ctx.drawLayer { layer in
            layer.addFilter(.blur(radius: blur))
            layer.blendMode = .plusLighter
            for blob in Self.blobs {
                let color = colors[blob.colorIndex % colors.count]
                let ang = blob.phase + t * blob.rate
                let reach = blob.orbit * churn * s
                let cx = mid.x + reach * cos(ang)
                let cy = mid.y + reach * sin(ang * 1.21 + blob.phase) * blob.ellipY
                let pulse = 0.90 + 0.10 * sin(t * blob.wobble + blob.phase)
                let r = blob.radius * s * pulse * scale
                let pt = CGPoint(x: cx, y: cy)
                layer.fill(
                    Path(ellipseIn: CGRect(x: cx - r, y: cy - r * blob.ellipY,
                                           width: 2 * r, height: 2 * r * blob.ellipY)),
                    with: .radialGradient(
                        Gradient(stops: [
                            .init(color: color.opacity(peak * intensity), location: 0),
                            .init(color: color.opacity(mantle * intensity), location: 0.32),
                            .init(color: color.opacity(0), location: 1),
                        ]),
                        center: pt, startRadius: 0, endRadius: r
                    )
                )
            }
        }
    }

    /// Thin spiralling light tendrils — the "energy" inside the glass.
    private func drawFilaments(_ ctx: GraphicsContext, s: CGFloat, mid: CGPoint,
                               colors: [Color], t: Double, energy: Double, intensity: Double) {
        ctx.drawLayer { layer in
            layer.addFilter(.blur(radius: s * 0.012))
            layer.blendMode = .plusLighter
            let count = 5
            for k in 0..<count {
                let base = Double(k) * 1.7 + t * (0.5 + 0.12 * Double(k)) * energy
                let color = colors[(k * 2 + 1) % colors.count]
                var path = Path()
                let steps = 26
                for j in 0...steps {
                    let f = Double(j) / Double(steps)
                    let ang = base + f * 4.6
                    let rad = (0.10 + 0.34 * f) * Double(s)
                    let x = mid.x + CGFloat(cos(ang) * rad)
                    let y = mid.y + CGFloat(sin(ang) * rad * 0.92)
                    if j == 0 { path.move(to: CGPoint(x: x, y: y)) }
                    else { path.addLine(to: CGPoint(x: x, y: y)) }
                }
                let twinkle = 0.45 + 0.55 * (0.5 + 0.5 * sin(t * 1.6 + Double(k)))
                let alpha = 0.55 * energy * intensity * twinkle
                layer.stroke(
                    path,
                    with: .linearGradient(
                        Gradient(colors: [color.opacity(0), color.opacity(alpha), color.opacity(0)]),
                        startPoint: mid,
                        endPoint: CGPoint(x: mid.x + s * 0.46, y: mid.y)
                    ),
                    style: StrokeStyle(lineWidth: s * 0.011, lineCap: .round, lineJoin: .round)
                )
            }
        }
    }

    // MARK: Surface — specular gloss, chromatic rim, sparkles

    private func surface(now: Double, t: Double, lvl: CGFloat) -> some View {
        let colors = theme.blobColors
        let energy = state.energy + Double(lvl) * 0.5

        return Canvas { ctx, canvas in
            let s = min(canvas.width, canvas.height)
            let mid = CGPoint(x: canvas.width / 2, y: canvas.height / 2)

            drawGlassEdge(ctx, s: s, mid: mid, colors: colors, lvl: lvl)
            drawSpecular(ctx, s: s, mid: mid)
            drawSparkles(ctx, s: s, mid: mid, colors: colors, now: now, t: t, energy: energy, lvl: lvl)
        }
        .blendMode(.plusLighter)
    }

    /// A tight chromatic meniscus hugging the body — colour from the theme, never a
    /// wide white ring that reads as a loading spinner on the void.
    private func drawGlassEdge(_ ctx: GraphicsContext, s: CGFloat, mid: CGPoint,
                               colors: [Color], lvl: CGFloat) {
        ctx.drawLayer { layer in
            layer.addFilter(.blur(radius: s * 0.018))
            let alpha = 0.22 + 0.14 * Double(lvl)
            let r = s * 0.46
            layer.stroke(
                Path(ellipseIn: CGRect(x: mid.x - r, y: mid.y - r, width: 2 * r, height: 2 * r)),
                with: .conicGradient(
                    Gradient(colors: [
                        colors[0].opacity(alpha * 0.5),
                        colors[2].opacity(alpha * 0.7),
                        colors[4].opacity(alpha * 0.45),
                        colors[1].opacity(alpha * 0.6),
                        colors[0].opacity(alpha * 0.5),
                    ]),
                    center: mid,
                    angle: .degrees(-90)
                ),
                style: StrokeStyle(lineWidth: s * 0.028)
            )
        }
    }

    /// Glossy highlight up and to the left — reads the orb as a sphere.
    private func drawSpecular(_ ctx: GraphicsContext, s: CGFloat, mid: CGPoint) {
        let c = CGPoint(x: mid.x - s * 0.15, y: mid.y - s * 0.18)
        let r = s * 0.20
        ctx.fill(
            Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r * 1.3,
                                   width: 2 * r, height: 2 * r * 1.3)),
            with: .radialGradient(
                Gradient(colors: [.white.opacity(0.55), .white.opacity(0)]),
                center: c, startRadius: 0, endRadius: r
            )
        )
    }

    /// Orbiting twinkles; the brightest throw a little cross flare.
    private func drawSparkles(_ ctx: GraphicsContext, s: CGFloat, mid: CGPoint,
                              colors: [Color], now: Double, t: Double,
                              energy: Double, lvl: CGFloat) {
        ctx.drawLayer { layer in
            layer.addFilter(.blur(radius: s * 0.003))
            for (i, sp) in Self.sparks.enumerated() {
                let ang = sp.phase + t * sp.rate * 0.6
                let rad = sp.orbit * s
                let x = mid.x + CGFloat(cos(ang)) * rad
                let y = mid.y + CGFloat(sin(ang)) * rad * sp.ellipY
                let raw = sin(now * sp.twRate + sp.twPhase)
                let tw = max(0, raw)
                let bright = tw * tw * (0.6 + 0.4 * energy) * (0.7 + 0.6 * Double(lvl))
                if bright < 0.02 { continue }
                let base = (sp.big ? 0.013 : 0.007) * s
                let dot = base * CGFloat(0.55 + 0.45 * tw)
                let tint = colors[i % colors.count]
                let core = Color.white.opacity(min(1, bright))
                layer.fill(
                    Path(ellipseIn: CGRect(x: x - dot, y: y - dot, width: 2 * dot, height: 2 * dot)),
                    with: .radialGradient(
                        Gradient(colors: [core, tint.opacity(bright * 0.7), .clear]),
                        center: CGPoint(x: x, y: y), startRadius: 0, endRadius: dot * 2.2
                    )
                )
                if sp.big && tw > 0.92 {
                    let flare = base * 3.4 * CGFloat(tw)
                    let w = max(0.6, s * 0.004)
                    let fa = Color.white.opacity(bright * 0.7)
                    layer.fill(Path(CGRect(x: x - flare, y: y - w / 2, width: 2 * flare, height: w)), with: .color(fa))
                    layer.fill(Path(CGRect(x: x - w / 2, y: y - flare, width: w, height: 2 * flare)), with: .color(fa))
                }
            }
        }
    }

    /// Tight coloured spill — stays inside the orb's silhouette so the stage
    /// doesn't get a cheap white halo ring.
    private func outerBloom(now: Double, lvl: CGFloat) -> some View {
        let e = state.glow * (pressed ? 1.06 : 1) + Double(lvl) * 0.5
        let pulse = 1 + CGFloat(sin(now * 1.35)) * 0.03 + lvl * 0.08
        return RadialGradient(
            colors: [
                theme.primary.opacity(0.20 * e),
                theme.tertiary.opacity(0.10 * e),
                theme.secondary.opacity(0.04 * e),
                .clear,
            ],
            center: .center,
            startRadius: size * 0.22,
            endRadius: size * 0.52
        )
        .frame(width: size * 1.15, height: size * 1.15)
        .blur(radius: size * 0.10)
        .scaleEffect(pulse)
        .blendMode(.plusLighter)
        .allowsHitTesting(false)
    }
}

// MARK: - Voice waveform

/// Per-bar spring physics + asymmetric attack/release on the global envelope.
/// Heights glide with momentum instead of snapping — the rainbow reads alive.
private final class WaveSmoother {
    private var amp: Double = 0
    private var bars: [Double] = []
    private var velocities: [Double] = []

    func tick(target: Double, barCount: Int, height: Double, t: Double, active: Bool) -> [CGFloat] {
        let attack = 0.20
        let release = 0.07
        amp += (target - amp) * (target > amp ? attack : release)

        if bars.count != barCount {
            bars = (0..<barCount).map { i in
                let center = envelope(i, barCount)
                return 0.05 + center * 0.04
            }
            velocities = Array(repeating: 0, count: barCount)
        }

        return (0..<barCount).map { i in
            let phase = Double(i) * 0.38 + t * 0.12 * Double(i % 4)
            let osc1 = (sin(t * 5.6 + phase) + 1) / 2
            let osc2 = (sin(t * 3.1 + phase * 1.6 + 0.8) + 1) / 2
            let osc = osc1 * 0.62 + osc2 * 0.38
            let center = envelope(i, barCount)

            let targetNorm: Double
            if active {
                targetNorm = amp * (0.26 + 0.74 * osc) * (0.32 + 0.68 * center) + center * 0.05
            } else {
                targetNorm = 0.035 + 0.028 * (0.5 + 0.5 * sin(t * 1.3 + phase)) * center
            }

            let stiffness = 0.13 + Double(i % 7) * 0.011
            let delta = targetNorm - bars[i]
            velocities[i] = velocities[i] * 0.70 + delta * stiffness
            bars[i] += velocities[i]

            return CGFloat(3 + height * bars[i])
        }
    }

    private func envelope(_ i: Int, _ count: Int) -> Double {
        let center = 1 - abs(Double(i) - Double(count - 1) / 2) / (Double(count) * 0.44)
        return pow(max(0, center), 0.82)
    }
}

struct VoiceWave: View {
    var theme: CloeTheme = .original
    var active: Bool
    var level: () -> CGFloat = { 1 }
    var barCount: Int = 7
    var height: CGFloat = 26

    @State private var smoother = WaveSmoother()

    private var barWidth: CGFloat { barCount > 20 ? 2.8 : 3.5 }
    private var barGap: CGFloat { barCount > 20 ? 2.0 : 2.5 }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let target = Double(min(1, max(0, level())))
            let heights = smoother.tick(
                target: target, barCount: barCount, height: Double(height), t: t, active: active
            )
            let colors = theme.blobColors
            let shimmer = 0.5 + 0.5 * sin(t * 0.9)

            Canvas { ctx, canvas in
                let totalW = CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * barGap
                var x = (canvas.width - totalW) / 2
                let baseY = canvas.height

                // Soft bloom beneath the bars — sells the prism on a screenshot.
                ctx.drawLayer { layer in
                    layer.addFilter(.blur(radius: barCount > 20 ? 6 : 4))
                    layer.blendMode = .plusLighter
                    for i in 0..<barCount {
                        let h = heights[i]
                        let rect = CGRect(x: x, y: baseY - h, width: barWidth, height: h)
                        let tint = colors[i % colors.count]
                        layer.fill(
                            Path(roundedRect: rect, cornerRadius: barWidth / 2),
                            with: .color(tint.opacity(0.55 + 0.25 * shimmer))
                        )
                        x += barWidth + barGap
                    }
                }

                x = (canvas.width - totalW) / 2
                for i in 0..<barCount {
                    let h = heights[i]
                    let rect = CGRect(x: x, y: baseY - h, width: barWidth, height: h)
                    let a = colors[i % colors.count]
                    let b = colors[(i + 2) % colors.count]
                    ctx.fill(
                        Path(roundedRect: rect, cornerRadius: barWidth / 2),
                        with: .linearGradient(
                            Gradient(colors: [
                                a.opacity(0.92),
                                b.opacity(0.78 + 0.14 * shimmer),
                            ]),
                            startPoint: CGPoint(x: rect.midX, y: rect.maxY),
                            endPoint: CGPoint(x: rect.midX, y: rect.minY)
                        )
                    )
                    x += barWidth + barGap
                }
            }
            .frame(height: height)
            .drawingGroup(opaque: false)
        }
    }
}

// MARK: - Intentions

/// A single suggested intention: the word seeds the conversation when tapped.
struct OrbitIntention: Identifiable {
    let id = UUID()
    let word: String
    let prompt: String
}

/// Horizontal suggestion strip — no orbit animation, no particle motes.
struct IntentionStrip: View {
    var theme: CloeTheme
    var items: [OrbitIntention]
    var visible: Bool = true
    var onTap: (OrbitIntention) -> Void

    var body: some View {
        HStack(spacing: 10) {
            ForEach(items) { item in
                Button { onTap(item) } label: {
                    Text(item.word)
                        .font(CloeTypography.captionMedium)
                        .foregroundStyle(CloePalette.ink.opacity(0.72))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(CloePalette.surface)
                        .clipShape(Capsule())
                        .overlay {
                            Capsule().strokeBorder(CloePalette.separator, lineWidth: 0.5)
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .opacity(visible ? 1 : 0)
        .offset(y: visible ? 0 : 8)
        .animation(CloeMotion.intentionReveal, value: visible)
    }
}

// MARK: - Previews

#Preview("Hero") {
    ZStack {
        CloeStage(theme: .original)
        VStack(spacing: 24) {
            CloeOrb(theme: .original, state: .thinking, size: 220)
            VoiceWave(theme: .original, active: true)
        }
    }
}

#Preview("Themes") {
    ScrollView {
        VStack(spacing: 32) {
            ForEach(CloeTheme.allCases) { theme in
                ZStack {
                    CloeStage(theme: theme)
                        .frame(height: 160)
                        .clipShape(RoundedRectangle(cornerRadius: 20))
                    HStack(spacing: 20) {
                        CloeOrb(theme: theme, state: .idle, size: 72, halo: false)
                        CloeOrb(theme: theme, state: .listening, size: 72, halo: false)
                        Text(theme.label).font(.caption.bold())
                    }
                }
            }
        }
        .padding()
    }
    .background(.black)
}
