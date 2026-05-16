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
    @AppStorage("hasUnlockedThemes") var hasUnlockedThemes = false
    @AppStorage("selectedAppThemeID") var selectedAppThemeID = AppTheme.defaultID
    @AppStorage("usesAppThemeReadouts") var usesAppThemeReadouts = false
    @AppStorage("shutterCount") var shutterCount = 0
    @AppStorage("shutterCountBurst") var shutterCountBurst = 0
    @State var permissionModel = PermissionModel()
    @State var lockedCaptureHapticTrigger = 0
    @State private var isShowingUnlockedThemesAlert = false
    
    private func checkThemeUnlock() {
//        hasUnlockedThemes = false
//        selectedAppThemeID = AppTheme.defaultID
        guard !hasUnlockedThemes else { return }
        if self.shutterCount >= 100 && self.shutterCountBurst >= 500 {
            hasUnlockedThemes = true
            isShowingUnlockedThemesAlert = true
        }
    }
    
    var body: some Scene {
        WindowGroup {
            CaptureView(
                hasUnlockedThemes: $hasUnlockedThemes,
                selectedAppThemeID: $selectedAppThemeID,
                usesAppThemeReadouts: $usesAppThemeReadouts,
                shutterCount: $shutterCount,
                shutterCountBurst: $shutterCountBurst,
                permissionModel: permissionModel
            )
            .sensoryFeedback(.impact, trigger: lockedCaptureHapticTrigger)
            .alert("You have reached the criteria to unlock app themes!", isPresented: $isShowingUnlockedThemesAlert, actions: { }, message: {
                Text("Go to settings, and scroll down to app themes to customise the app!")
            })
            .task {
                checkThemeUnlock()
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
// add shutter animation, when proraw taking long to capture add spin animating, or colour leak into the white
// when tap burst, keep white circle enlarger
// theme preview still has incorrect shutter colours

// update app themes
/// [DONE] in app theme, lock tool bar button top right
/// [DONE] clicking on it opens an alert saying to change the app theme, requires 100 photos to be taken - shutter counter >= 100 and 500 burst count, or can enter a password to unlock
/// [DONE] keep deafult ticked, but add a capsule button called preview (matches the accent) on each row, tapping will show the preview below
/// [DONE] if device is iphone 17pro then show options for cosmic orange, deep blue, silver
/// last option is "Custom", tapping opens a disclosure group with background, accent, shutter raw/proraw/burst
/// custom is locked to 1000 shutter count and 1000 burst count
/// [DONE] readout colour is just accent.opacity0.8, standard hsutter is white opacity 0.2, burst capturing is related to burst
/// [DONE] make dividr in middle of screen, and bottom half scrollable as well

/// Paid features: bursts, dualcam, histograms, zebras, clipping, filters, save to files, barcodes and app themes
/// App themes £1.49 add on
/// Full Unlock Subscription contains everything
/// free 1 week trial, £2.99 per month, or £20 per year
