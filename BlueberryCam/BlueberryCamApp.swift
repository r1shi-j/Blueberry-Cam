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

// lens cleaning hint, same structure as barcode link
// Macro, portrait, dual cam, burst, flash, timer buttons new line
// Tap to focus with focus EV
// Show proper selfie cameras

// Improve lens picker UI (liquid glass sliding), move to bottom right?
// Click on any readout -> shows vertical slider right side screen like halide
/// slider shows the auto value constantly updating, manually changing it turns on manual mode, for ss/iso have left iso right ss?

// Focus Loupe
// ProRaw
// Photographic styles
// Digital zoom
// View outside frame
