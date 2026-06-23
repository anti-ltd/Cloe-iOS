import SwiftUI

/// Cloe's type system — editorial, restrained. No decorative fonts or glow tricks.
enum CloeTypography {
    static var hero: Font { .system(size: 34, weight: .light, design: .default) }
    static var title: Font { .system(size: 17, weight: .semibold) }
    static var body: Font { .system(size: 17, weight: .regular) }
    static var bodyMedium: Font { .system(size: 17, weight: .medium) }
    static var caption: Font { .system(size: 13, weight: .regular) }
    static var captionMedium: Font { .system(size: 13, weight: .medium) }
    static var footnote: Font { .system(size: 12, weight: .regular) }
}
