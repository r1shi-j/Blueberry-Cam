import WidgetKit
import SwiftUI
import AppIntents

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
                Label("Blueberry Cam", systemImage: "camera.aperture")
            }
        }
        .displayName("Blueberry Cam")
        .description("Open Blueberry Cam to capture RAW photos.")
    }
}
