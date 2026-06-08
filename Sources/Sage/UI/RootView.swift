import SwiftUI
import iUXiOS

#Preview("Chat") {
    let model = AppModel()
    return RootView()
        .environment(model)
        .environment(model.settings)
}

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let mlx = model.mlxBackend, model.needsMLXSetup {
            ModelSetupView(mlx: mlx)
        } else {
            ChatView()
        }
    }
}
