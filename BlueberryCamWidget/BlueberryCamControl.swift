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
            kind: "com.blueberrycam.cameracontrol"
        ) {
            ControlWidgetButton(action: BlueberryCamCaptureIntent()) {
                Label("Blueberry Cam", image: "camera.blueberry.reversed")
            }
        }
        .displayName("Blueberry Cam")
        .description("Open Blueberry Cam to capture RAW photos.")
    }
}
