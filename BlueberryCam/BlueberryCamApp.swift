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

// Implement 3rd row on TopBarView: Macro, ***dual cam***, (raw) burst, flash, timer buttons
// ProRaw
// View outside frame
// Selfie cam horizontal mode and centre stage
// Customisable accent colours (shutter color per state, top bar pickers)

// MARK: - FIXME

// MARK: - Next Steps
// image rotation bugs still
// maunal manual burst and manual exposure, if MBurst is ever 0.25 seconds but MExposure is 0.5 seconds then a problem
