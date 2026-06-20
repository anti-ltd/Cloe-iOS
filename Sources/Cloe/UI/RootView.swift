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
                // A downloaded model sits idle on launch; load it from disk so we
                // skip the setup screen instead of making the user tap Download again.
                .task {
                    if case .idle = mlx.loadState, mlx.isDownloaded {
                        await mlx.prepare()
                    }
                }
        } else {
            ChatView()
        }
    }
}
