import SwiftUI
import WidgetKit

@main
struct CloeWidgetBundle: WidgetBundle {
    var body: some Widget {
        CloeLauncherWidget()
        CloeQuickAccessActivity()
        CloeTalkControl()
    }
}
