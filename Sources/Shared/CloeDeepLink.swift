import Foundation

/// `cloe://` deep links shared by the app (which handles them in `onOpenURL`) and
/// the widget extension (which opens them from widget taps). Lives in
/// `Sources/Shared` so both targets compile the same constants.
enum CloeDeepLink {
    static let chat = URL(string: "cloe://chat")!
    static let voice = URL(string: "cloe://voice")!
}
