import SwiftUI

/// Flat dark backdrop — zero animation cost. A single soft wash of the theme colour
/// at the top is enough; everything else is typography and the orb.
struct CloeStage: View {
    var theme: CloeTheme = .original

    var body: some View {
        ZStack {
            CloePalette.canvas.ignoresSafeArea()
            LinearGradient(
                colors: [
                    theme.primary.opacity(0.07),
                    theme.secondary.opacity(0.03),
                    .clear,
                ],
                startPoint: .top,
                endPoint: UnitPoint(x: 0.5, y: 0.45)
            )
            .ignoresSafeArea()
        }
        .allowsHitTesting(false)
    }
}
