import SwiftUI

/// Cloe's prism palette — the Siri-spectrum colours everything is drawn from.
enum CloePalette {
    static let green  = Color(red: 0.22, green: 0.90, blue: 0.55)
    static let white  = Color(red: 0.97, green: 0.98, blue: 1.00)
    static let blue   = Color(red: 0.32, green: 0.58, blue: 1.00)
    static let pink   = Color(red: 1.00, green: 0.28, blue: 0.55)
    static let orange = Color(red: 1.00, green: 0.58, blue: 0.24)
    static let violet = Color(red: 0.64, green: 0.40, blue: 1.00)
    static let cyan   = Color(red: 0.20, green: 0.88, blue: 0.95)
    static let indigo = Color(red: 0.38, green: 0.22, blue: 0.92)

    // Presence ink — text reads as light lit from the orb's source, never
    // pure-white-on-card. Used for dialogue on the void.
    static let ink      = Color(red: 0.957, green: 0.949, blue: 0.984) // #F4F2FB
    static let inkMuted = Color.white.opacity(0.55)
    static let hairline = Color.white.opacity(0.12)
}

/// Orb colour themes — each is a distinct liquid palette that tints the orb,
/// stage ambient glow, waveforms, and brand accents across the whole app.
enum CloeTheme: String, CaseIterable, Identifiable, Codable {
    case original, ocean, sunset, aurora, night

    var id: String { rawValue }

    var label: String {
        switch self {
        case .original: "Original"
        case .ocean:    "Ocean"
        case .sunset:   "Sunset"
        case .aurora:   "Aurora"
        case .night:    "Night"
        }
    }

    /// Molten blob colours for the orb liquid layer.
    var blobColors: [Color] {
        switch self {
        case .original:
            [CloePalette.violet, CloePalette.blue, CloePalette.pink,
             CloePalette.green, CloePalette.orange, CloePalette.white]
        case .ocean:
            [CloePalette.cyan, CloePalette.blue, Color(red: 0.10, green: 0.55, blue: 0.95),
             Color(red: 0.05, green: 0.75, blue: 0.82), CloePalette.white, CloePalette.indigo]
        case .sunset:
            [CloePalette.orange, CloePalette.pink, Color(red: 1.0, green: 0.35, blue: 0.30),
             Color(red: 0.95, green: 0.20, blue: 0.55), CloePalette.violet, CloePalette.white]
        case .aurora:
            [CloePalette.green, CloePalette.cyan, CloePalette.blue,
             CloePalette.violet, Color(red: 0.15, green: 0.95, blue: 0.70), CloePalette.white]
        case .night:
            [CloePalette.indigo, CloePalette.violet, Color(red: 0.28, green: 0.12, blue: 0.62),
             CloePalette.blue, Color(red: 0.45, green: 0.25, blue: 0.85), CloePalette.white]
        }
    }

    /// Primary + secondary for halos, stage blooms, and brand gradients.
    var primary: Color { blobColors[0] }
    var secondary: Color { blobColors[1] }
    var tertiary: Color { blobColors[2] }

    var brand: LinearGradient {
        LinearGradient(colors: [primary, secondary],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    // MARK: Presence — drawn-light UI tokens

    /// The breathing presence word + orbiting intentions — orb light, never solid.
    var presence: Color { primary.opacity(0.35) }
    /// Cloe's dialogue: ink lit from the same source as the orb.
    var dialogueCloe: Color { CloePalette.ink.opacity(0.92) }
    /// The user's dialogue: the theme's own light, so turns read by colour not bubbles.
    var dialogueUser: Color { primary.opacity(0.88) }

    /// Full-perimeter spectrum for the Alive edge glow — warm yellow through cool
    /// blue, each theme keeping its own accent family.
    var aliveSpectrum: [Color] {
        switch self {
        case .original:
            [
                Color(red: 1.00, green: 0.95, blue: 0.18),
                CloePalette.orange,
                Color(red: 1.00, green: 0.18, blue: 0.22),
                CloePalette.pink,
                Color(red: 0.98, green: 0.22, blue: 0.72),
                CloePalette.violet,
                CloePalette.blue,
                Color(red: 0.12, green: 0.38, blue: 1.00),
                CloePalette.cyan,
                Color(red: 1.00, green: 0.95, blue: 0.18),
            ]
        case .ocean:
            [
                CloePalette.cyan,
                CloePalette.blue,
                Color(red: 0.10, green: 0.55, blue: 0.95),
                CloePalette.indigo,
                Color(red: 0.05, green: 0.75, blue: 0.82),
                CloePalette.cyan,
                CloePalette.blue,
                CloePalette.indigo,
                CloePalette.cyan,
            ]
        case .sunset:
            [
                Color(red: 1.00, green: 0.95, blue: 0.18),
                CloePalette.orange,
                Color(red: 1.00, green: 0.35, blue: 0.30),
                CloePalette.pink,
                Color(red: 0.95, green: 0.20, blue: 0.55),
                CloePalette.violet,
                CloePalette.orange,
                CloePalette.pink,
                Color(red: 1.00, green: 0.95, blue: 0.18),
            ]
        case .aurora:
            [
                CloePalette.green,
                CloePalette.cyan,
                CloePalette.blue,
                CloePalette.violet,
                Color(red: 0.15, green: 0.95, blue: 0.70),
                CloePalette.green,
                CloePalette.cyan,
                CloePalette.violet,
                CloePalette.green,
            ]
        case .night:
            [
                CloePalette.indigo,
                CloePalette.violet,
                Color(red: 0.28, green: 0.12, blue: 0.62),
                CloePalette.blue,
                Color(red: 0.45, green: 0.25, blue: 0.85),
                CloePalette.indigo,
                CloePalette.violet,
                CloePalette.blue,
                CloePalette.indigo,
            ]
        }
    }

    /// Ambient stage bloom colours (top, trailing, leading).
    var stageBlooms: (top: Color, trailing: Color, leading: Color) {
        switch self {
        case .original: (CloePalette.violet, CloePalette.blue, CloePalette.pink)
        case .ocean:    (CloePalette.cyan, CloePalette.blue, CloePalette.indigo)
        case .sunset:   (CloePalette.orange, CloePalette.pink, CloePalette.violet)
        case .aurora:   (CloePalette.green, CloePalette.cyan, CloePalette.violet)
        case .night:    (CloePalette.indigo, CloePalette.violet, CloePalette.blue)
        }
    }
}
