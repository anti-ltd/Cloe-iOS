import SwiftUI

/// Shared motion vocabulary — one physics language across orb, wave, dialogue, and chrome.
enum CloeMotion {
    /// Hero morphs: orb rise, rest ↔ conversation.
    static let hero = Animation.smooth(duration: 0.65)

    /// Presence word + state captions.
    static let presence = Animation.smooth(duration: 0.5)

    /// Orb press bloom.
    static let orbPress = Animation.spring(response: 0.28, dampingFraction: 0.58)

    /// Perimeter rim swell on listen / think / speak.
    static let rimSwell = Animation.spring(response: 0.62, dampingFraction: 0.78)

    /// New dialogue lines entering the void.
    static let dialogueEnter = Animation.spring(response: 0.52, dampingFraction: 0.80)

    /// Toolbar glass controls.
    static let glassPress = Animation.spring(response: 0.24, dampingFraction: 0.68)

    /// Orbiting intention motes fading in.
    static let intentionReveal = Animation.easeOut(duration: 1.1)

    /// Input bar send mote.
    static let sendMote = Animation.spring(response: 0.32, dampingFraction: 0.74)

    /// Input bar focus bloom.
    static let inputFocus = Animation.smooth(duration: 0.42)

    /// Each orbiting intention mote, staggered after the ring appears.
    static func intentionStagger(index: Int) -> Animation {
        .spring(response: 0.62, dampingFraction: 0.78)
            .delay(0.12 + Double(index) * 0.14)
    }

    /// Intention mote press.
    static let intentionPress = Animation.spring(response: 0.26, dampingFraction: 0.62)

    /// Hold-to-speak discoverability pulse.
    static let holdHint = Animation.easeInOut(duration: 2.0).repeatForever(autoreverses: true)
}
