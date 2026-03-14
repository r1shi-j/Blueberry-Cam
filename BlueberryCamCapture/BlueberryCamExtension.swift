import ExtensionKit
import LockedCameraCapture
import SwiftUI

@main
struct BlueberryCamExtension: LockedCameraCaptureExtension {
    var body: some LockedCameraCaptureExtensionScene {
        LockedCameraCaptureUIScene { session in
            LockedCaptureView(lockedSession: session)
        }
    }
}
