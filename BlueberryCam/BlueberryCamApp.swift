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
/// using manual controls
/// raw / formats / resolutions
/// geotag/flash
/// qr code / z / p / focus loupe / level / histograms
/// remove focus peaking toggle?
