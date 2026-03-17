import AppIntents
import SwiftUI
import WidgetKit

@main
struct BlueberryCamWidgetBundle: WidgetBundle {
    var body: some Widget {
        BlueberryCamControl()
    }
}

struct BlueberryCamControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(
            kind: "\(BundleIDs.appID).cameracontrol"
        ) {
            ControlWidgetButton(action: BlueberryCamCaptureIntent()) {
                Label(BundleIDs.appName, image: BundleIDs.appSymbolReversedName)
            }
        }
        .displayName("Blueberry Cam")
        .description("Open Blueberry Cam to capture RAW photos.")
    }
}
