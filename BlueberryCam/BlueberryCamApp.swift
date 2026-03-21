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
    
    var body: some Scene {
        WindowGroup {
            CaptureView(shutterCount: $shutterCount)
                .task { await detectLockedCaptureSessions() }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        Task { await detectLockedCaptureSessions() }
                    }
                }
        }
        .handlesExternalEvents(matching: ["*"])
    }
}

// MARK: - TODO
// Localise for all iPhones iOS 26+
// Add tips and welcome screen with tutorials
// Improve memory/cpu usage, quicker camera switching
// Swift 6
// Update identifier (variable/function) names

// Macro, portrait, dual cam, burst, flash, timer buttons: 3rd row on TopBarView
// Show proper selfie cameras
// Improve lens picker UI (liquid glass sliding), move to bottom right?
// Click on any readout -> shows vertical slider right side screen like halide (and add animations to knock on effects)
/// slider shows the auto value constantly updating, manually changing it turns on manual mode, for ss/iso have left iso right ss?
// Focus Loupe, option to disable green dots in focus peaking/manual focus
// View outside frame
// ProRaw

// MARK: - FIXME
// improve locked cam add to album
