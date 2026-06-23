import SwiftUI
import iUXiOS

/// Premium glass surfaces — Liquid Glass on iOS 26 with Cloe's lit rim, inner
/// highlight, and optional theme tint. The recipe that makes cards feel like
/// frosted lenses floating on the dark stage.
struct CloeGlassSurface: ViewModifier {
    var cornerRadius: CGFloat
    var tint: Color?
    var shadow: Bool

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    func body(content: Content) -> some View {
        content
            .background { glassFill }
            .overlay { litRim }
            .overlay { innerHighlight }
            .modifier(CloeGlassShadow(enabled: shadow))
    }

    @ViewBuilder
    private var glassFill: some View {
        if #available(iOS 26.0, *) {
            if let tint {
                Color.clear.glassEffect(.regular.tint(tint.opacity(0.22)), in: shape)
            } else {
                Color.clear.glassEffect(.regular, in: shape)
            }
        } else {
            ZStack {
                shape.fill(.white.opacity(0.04))
                shape.fill(.ultraThinMaterial)
                if let tint {
                    shape.fill(
                        LinearGradient(
                            colors: [tint.opacity(0.18), .clear],
                            startPoint: .topLeading, endPoint: .center
                        )
                    )
                }
            }
        }
    }

    private var litRim: some View {
        shape.strokeBorder(
            LinearGradient(
                colors: [
                    .white.opacity(0.38),
                    .white.opacity(0.10),
                    .white.opacity(0.04),
                ],
                startPoint: .top, endPoint: .bottom
            ),
            lineWidth: 0.75
        )
    }

    /// A soft top sheen — sells the curved lens without fighting `.glassEffect`.
    private var innerHighlight: some View {
        shape.fill(
            LinearGradient(
                colors: [.white.opacity(0.14), .white.opacity(0.03), .clear],
                startPoint: .top, endPoint: .center
            )
        )
        .allowsHitTesting(false)
    }
}

private struct CloeGlassShadow: ViewModifier {
    let enabled: Bool
    func body(content: Content) -> some View {
        if enabled {
            content.shadow(color: .black.opacity(0.35), radius: 20, y: 10)
        } else {
            content
        }
    }
}

extension View {
    /// Wrap content in Cloe's signature glass card.
    func cloeGlass(cornerRadius: CGFloat = 24, tint: Color? = nil, shadow: Bool = false) -> some View {
        modifier(CloeGlassSurface(cornerRadius: cornerRadius, tint: tint, shadow: shadow))
    }

    /// Small circular glass control (toolbar buttons).
    func cloeGlassCircle(tint: Color? = nil) -> some View {
        modifier(CloeGlassSurface(cornerRadius: 999, tint: tint, shadow: false))
    }
}

/// Spring press for glass controls — shared across chat toolbar and glass rows.
struct CloeGlassPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .opacity(configuration.isPressed ? 0.78 : 1)
            .animation(CloeMotion.glassPress, value: configuration.isPressed)
    }
}
