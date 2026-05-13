//
//  Blueberry_CamApp.swift
//  Blueberry Cam
//
//  Created by Rishi Jansari on 07/03/2026.
//

import SwiftUI

@main
struct BlueberryCamApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("appBackgroundColorIndex") var appBackgroundColorIndex = 0
    @AppStorage("shutterCount") var shutterCount = 0
    @AppStorage("shutterCountBurst") var shutterCountBurst = 0
    @State var permissionModel = PermissionModel()
    @State var lockedCaptureHapticTrigger = 0
    
    var body: some Scene {
        WindowGroup {
            CaptureView(
                appBackgroundColorIndex: $appBackgroundColorIndex,
                shutterCount: $shutterCount,
                shutterCountBurst: $shutterCountBurst,
                permissionModel: permissionModel
            )
            .sensoryFeedback(.impact, trigger: lockedCaptureHapticTrigger)
            .task {
                await permissionModel.checkAndRequest()
                await scanExistingSessions()
                await detectLockedCaptureSessions()
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    Task { await permissionModel.checkAndRequest() }
                    Task { await scanExistingSessions() }
                }
            }
            .onContinueUserActivity("\(BundleIDs.fullBundleID).opencamera") { _ in
                // App was opened via the locked-app shortcut button.
                // scenePhase will also fire .active, but that races with the
                // session being written — scan again explicitly here to be safe.
                Task { await scanExistingSessions() }
            }
        }
        .handlesExternalEvents(matching: ["*"])
    }
}

// MARK: - TODO
// Localise for all iPhones iOS 26+
// Improve iPad/Mac Support
// Add tips, welcome screen and tutorials

// MARK: - FIXME
// locked app fix photo orientation
// with custom background colour, can see top/small histogram width is too long, x -> x *= 45%
// burst capture/info use same corner radius (visible from custom background colour), or maybe add glass effect
// burst shutter button bit too orange (in green background view)

// MARK: - Next Steps
// ProRaw
// Photographic styles
// Selfie cam horizontal mode and centre stage
