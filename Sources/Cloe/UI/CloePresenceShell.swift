import SwiftUI

/// Dark sheet chrome — flat background, native lists inside. No animated stage.
struct CloeSheetChrome<Content: View>: View {
    var title: String
    var dismiss: () -> Void
    @ViewBuilder var content: () -> Content

    var body: some View {
        NavigationStack {
            content()
                .background(CloePalette.canvas)
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done", action: dismiss)
                    }
                }
        }
        .preferredColorScheme(.dark)
    }
}

/// Divider between rows inside a grouped list card.
struct CloeGlassDivider: View {
    var inset: CGFloat = 16

    var body: some View {
        Rectangle()
            .fill(CloePalette.separator)
            .frame(height: 0.5)
            .padding(.leading, inset)
    }
}
