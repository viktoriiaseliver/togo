import WidgetKit
import SwiftUI

@main
struct TogoWidgetBundle: WidgetBundle {
    var body: some Widget {
        TodayWidget()
        WalkLiveActivity()
    }
}
