import SwiftUI
import iUXiOS

@main
struct SageApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(model.settings)
        }
    }
}
