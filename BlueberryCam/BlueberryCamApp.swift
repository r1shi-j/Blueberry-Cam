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
    
    private func printUserDefaultsData() {
        for (key, value) in UserDefaults.standard.dictionaryRepresentation() {
            print("\(key): \(value)")
        }
    }
    
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
                //                printUserDefaultsData()
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
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Paid Features Plan
/// Paid features: bursts, dualcam, histograms, zebras, clipping, filters, save to files, barcodes and app themes
/// One time purchases: App themes £1.49, App Themes + Custom £2.49
/// Subscriptions: Full Unlock free 1 week trial, £2.99 per month, or £20 per year, includes all app themes at no extra cost

// MARK: - Future Features
// Localise for all iPhones iOS 26+
// Improve iPad/Mac Support
// Add tips, welcome screen and tutorials

// FIXME: - Bugs
// improve selfie switch animation with differnt bg colour
// improve lens switching animation (particulary on selfie cameras)

// TODO: - Next Steps
// add shutter animation, when proraw taking long to capture add spin animating, or colour leak into the white
// when tap burst (not holding), keep white circle enlarged to hide outer circle like when hold

// [PRIORITY] issues with photos taken on locked camera not being detected
// [PRIORITY] restrict custom theme colours so that UI is visible
// [PRIORITY] theme preview still has incorrect shutter colours
