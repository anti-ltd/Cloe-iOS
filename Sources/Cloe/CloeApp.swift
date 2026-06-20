import SwiftUI
import iUXiOS

@main
struct CloeApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(model.settings)
                .onOpenURL { model.handleDeepLink($0) }
        }
        .onChange(of: scenePhase) { _, phase in
            // A Control Center "Talk to Cloe" tap brings us active — pick up the request.
            if phase == .active { model.consumePendingIntent() }
        }
    }
}
