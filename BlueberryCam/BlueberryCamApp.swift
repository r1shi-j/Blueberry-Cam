import SwiftUI

@main
struct BlueberryCamApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("shutterCount") var shutterCount = 0
    @StateObject var permissionModel = PermissionModel()
    
    var body: some Scene {
        WindowGroup {
            CaptureView(shutterCount: $shutterCount, permissionModel: permissionModel)
                .task {
                    await permissionModel.checkAndRequest()
                }
                .onChange(of: scenePhase) { newPhase in
                    if newPhase == .active {
                        Task { await permissionModel.checkAndRequest() }
                    }
                }
        }
    }
}

// TODO:
/// app icon
/// using manual controls: ss at slowest?

/// What changed:
/// Removed focus peaking, heif format, other lens and resolutions, blurred lens detection
/// Top bar / status bar merged, small histogram moved
/// Added clean UI and settings buttons to top bar
/// No macro, camera control, filters, haptics (added vibration when qr code detected)
/// Moved shutter count to bottom right
