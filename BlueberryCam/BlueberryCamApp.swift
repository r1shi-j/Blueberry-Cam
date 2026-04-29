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
    @AppStorage("shutterCountBurst") var shutterCountBurst = 0
    @State var permissionModel = PermissionModel()
    
    var body: some Scene {
        WindowGroup {
            CaptureView(
                shutterCount: $shutterCount,
                shutterCountBurst: $shutterCountBurst,
                permissionModel: permissionModel
            )
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

// ProRaw
// Live filter preview
// View outside frame
// Selfie cam horizontal mode and centre stage
// Customisable accent colours (shutter color per state, top bar pickers)

// MARK: - FIXME

// MARK: - Next Steps
// Implement 3rd row on TopBarView: Macro, ***dual cam***, (raw) burst, flash, timer buttons

// customisable background color instead of black, .blue.opacity(0.3)
/// in setttings: have disclosure group of colours as circles, store as an index

// top bar readouts slow to click

// photos on locked camera have xlong file name
// update locked camera
