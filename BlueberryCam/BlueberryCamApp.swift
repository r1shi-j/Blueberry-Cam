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
// improve selfie switch animation with differnt bg colour
// improve lens switching animation (particulary on selfie cameras)

// MARK: - Next Steps
// update app themes
/// in app theme, lock tool bar button top right
/// clicking on it opens an alert saying to change the app theme, requires 100 photos to be taken - shutter counter >= 100 and 100 burst count, or can enter a password to unlock
/// in list rename default to classic
/// keep deafult ticked, but add a capsule button called preview (matches the accent) on each row, tapping will show the preview below
/// if device is iphone 17pro then show options for cosmic orange, deep blue, silver
/// last option is "Custom", tapping opens a disclosure group with background, accent, shutter raw/proraw/burst
/// readout colour is just accent.opacity0.8, standard hsutter is white opacity 0.2, burst capturing is related to burst
/// custom is locked to 1000 shutter count and 1000 burst count
/// make dividr in middle of screen, and bottom half scrollable as well

/// Paid features: bursts, dualcam, histograms, zebras, clipping, filters, save to files, barcodes and app themes
/// App themes £1.49 add on
/// Full Unlock Subscription contains everything
/// free 1 week trial, £2.99 per month, or £20 per year
