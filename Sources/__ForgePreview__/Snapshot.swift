import XCTest
import SwiftUI
@testable import Cloe

final class ForgePreviewSnapshot: XCTestCase {
    @MainActor func testForgeRender() {
        let controller = UIHostingController(rootView: AnyView({

    let model = AppModel()
    return ChatView()
        .environment(model)
        .environment(model.settings)

}()).environment(\.colorScheme, .dark))
        controller.overrideUserInterfaceStyle = .dark
        controller.view.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        controller.view.backgroundColor = .systemBackground
        let window = UIWindow(frame: controller.view.frame)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))

        let renderer = UIGraphicsImageRenderer(bounds: controller.view.bounds)
        let image = renderer.image { _ in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }
        guard let data = image.pngData() else { return }
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("forge-preview.png")
        try? data.write(to: url)
    }
}