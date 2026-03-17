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

// Move lens picker to bottom right?
// Click on any readout -> shows vertical slider right side screen like halide
/// slider shows the auto value constantly updating, manually changing it turns on manual mode, for ss/iso have left iso right ss?

// Front and rear photos simultaneously
// Show proper selfie cameras
// Tap to focus with focus EV

// Focus Loupe
// ProRaw
// Burst
// Timer
// Photographic styles
// Portraits
// Digital zoom
// View outside frame
