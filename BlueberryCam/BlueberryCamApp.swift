//
//  Blueberry_CamApp.swift
//  Blueberry Cam
//
//  Created by Rishi Jansari on 07/03/2026.
//

import ConfettiSwiftUI
import SwiftUI

@main
struct BlueberryCamApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var appSettings = AppSettings()
    @State private var permissionModel = PermissionModel()
    @State private var lockedCaptureHapticTrigger = 0
    @State private var isShowingUnlockedThemesAlert = false
    @State private var isShowingUnlockedThemesCustomAlert = false
    @State private var confettiCannonsTrigger = 0
    
    private func checkThemesUnlock() {
        switch appSettings.nextThemeUnlockMilestone() {
            case .standard:
                confettiCannonsTrigger += 1
                isShowingUnlockedThemesAlert = true
            case .custom:
                confettiCannonsTrigger += 1
                isShowingUnlockedThemesCustomAlert = true
            case nil:
                break
        }
    }
    
    func recordLockedCaptureCount(_ count: Int) {
        appSettings.shutterCount += count
        lockedCaptureHapticTrigger += 1
    }
    
    var body: some Scene {
        WindowGroup {
            ZStack {
                CaptureView(appSettings: appSettings, permissionModel: permissionModel)
                confettiCannons()
            }
            .sensoryFeedback(.impact, trigger: lockedCaptureHapticTrigger)
            .alert("You have reached the criteria to unlock app themes!", isPresented: $isShowingUnlockedThemesAlert, actions: { }, message: {
                Text("Go to settings, and scroll down to app themes to customise the app!")
            })
            .alert("You have reached the ultimate criteria to unlock custom app themes!", isPresented: $isShowingUnlockedThemesCustomAlert, actions: { }, message: {
                Text("Go to settings, scroll down to app themes and select custom!")
            })
            .task {
                //                for (key, value) in UserDefaults.standard.dictionaryRepresentation() {
                //                    print("\(key): \(value)")
                //                }
                checkThemesUnlock()
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
            .onChange(of: appSettings.shutterCount, checkThemesUnlock)
            .onChange(of: appSettings.shutterCountBurst, checkThemesUnlock)
            .onContinueUserActivity("\(BundleIDs.fullBundleID).opencamera") { _ in
                Task { await scanExistingSessions() }
            }
        }
        .handlesExternalEvents(matching: ["*"])
    }
    
    private func confettiCannons() -> some View {
        HStack {
            ConfettiCannon(
                trigger: $confettiCannonsTrigger,
                num: 50,
                confettis: ConfettiObjects.themesLeft,
                confettiSize: 12,
                rainHeight: 800,
                openingAngle: .degrees(45),
                closingAngle: .degrees(75),
                radius: 350
            )
            .allowsHitTesting(false)
            
            ConfettiCannon(
                trigger: $confettiCannonsTrigger,
                num: 50,
                confettis: ConfettiObjects.themesRight,
                confettiSize: 12,
                rainHeight: 800,
                openingAngle: .degrees(105),
                closingAngle: .degrees(135),
                radius: 350
            )
            .allowsHitTesting(false)
        }
    }
}

// MARK: - TODO
// Localise for all iPhones iOS 26+
// Improve iPad/Mac Support
// Add tips, welcome screen and tutorials

// MARK: - FIXME
// improve selfie switch animation with differnt bg colour
// improve lens switching animation (particulary on selfie cameras)
// issues with photos taken on locked camera not being detected

// MARK: - Next Steps
// add shutter animation, when proraw taking long to capture add spin animating, or colour leak into the white
// when tap burst (not holding), keep white circle enlarged to hide outer circle like when hold
// theme preview still has incorrect shutter colours

// update app themes
/// [DONE] in app theme, lock tool bar button top right
/// [DONE] clicking on it opens an alert saying to change the app theme, requires 100 photos to be taken - shutter counter >= 100 and 500 burst count, or can enter a password to unlock
/// [DONE] keep deafult ticked, but add a capsule button called preview (matches the accent) on each row, tapping will show the preview below
/// [DONE] if device is iphone 17pro then show options for cosmic orange, deep blue, silver
/// [DONE] last option is "Custom", tapping opens a disclosure group with background, accent, shutter raw/proraw/burst
/// [DONE] custom is locked to 1000 shutter count and 1000 burst count
/// [DONE] readout colour is just accent.opacity0.8, standard hsutter is white opacity 0.2, burst capturing is related to burst
/// [DONE] make dividr in middle of screen, and bottom half scrollable as well

/// Paid features: bursts, dualcam, histograms, zebras, clipping, filters, save to files, barcodes and app themes
/// App themes £1.49 add on, £2.49 for themes + custom
/// Full Unlock Subscription contains everything
/// free 1 week trial, £2.99 per month, or £20 per year
