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
    @AppStorage("selectedAppThemeID") var selectedAppThemeID = AppTheme.defaultID
    @AppStorage("usesAppThemeReadouts") var usesAppThemeReadouts = false
    @AppStorage("shutterCount") var shutterCount = 0
    @AppStorage("shutterCountBurst") var shutterCountBurst = 0
    @State var permissionModel = PermissionModel()
    @State var lockedCaptureHapticTrigger = 0
    
    var body: some Scene {
        WindowGroup {
            CaptureView(
                selectedAppThemeID: $selectedAppThemeID,
                usesAppThemeReadouts: $usesAppThemeReadouts,
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

// MARK: - Next Steps
// smoother animations everywhere
// Updated locked camera app pipeline (just update whole codebase)
// selfie switch animation with differnt bg cololr
// customise theme packs
