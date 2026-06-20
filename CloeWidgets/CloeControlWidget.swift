import AppIntents
import SwiftUI
import WidgetKit

/// Control Center / Lock Screen / Action Button tile (Roadmap Item 2). Tapping it
/// runs `TalkToCloeControlIntent` → opens Cloe and starts hands-free voice. Unlike
/// the Live Activity, a control is permanent. (iOS shows a Face ID / Touch ID glance
/// before a control opens an app, so there's one auth step in the path.)
struct CloeTalkControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "ltd.anti.cloe.talk") {
            ControlWidgetButton(action: TalkToCloeControlIntent()) {
                Label("Talk to Cloe", systemImage: "mic.fill")
            }
        }
        .displayName("Talk to Cloe")
        .description("Open Cloe and start talking.")
    }
}
