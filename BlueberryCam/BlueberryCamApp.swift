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
    @AppStorage("shutterCount") var shutterCount = 0
    @State var permissionModel = PermissionModel()
    
    var body: some Scene {
        WindowGroup {
            CaptureView(shutterCount: $shutterCount, permissionModel: permissionModel)
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
// Add tips, welcome screen and tutorials

// Implement 3rd row on TopBarView: Macro, dual cam, burst, flash, timer buttons
// Raw burst
// Selfie cam horizontal mode and centre stage, photographic styles
// Improve lens picker UI (liquid glass sliding), move to bottom right?
// Click on any readout -> shows vertical slider right side screen like halide (and add animations to knock on effects)
/// slider shows the auto value constantly updating, manually changing it turns on manual mode, for ss/iso have left iso right ss?
// View outside frame
// ProRaw

// MARK: - FIXME
// Some situations where photos taken in locked camera not being detected
