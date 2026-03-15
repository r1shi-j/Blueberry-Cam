//
//  Blueberry_CamApp.swift
//  Blueberry Cam
//
//  Created by Rishi Jansari on 07/03/2026.
//

import LockedCameraCapture
import Photos
import SwiftUI

@main
struct Blueberry_CamApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("shutterCount") var shutterCount = 0
    
    var body: some Scene {
        WindowGroup {
            ContentView(shutterCount: $shutterCount)
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
// Improve memory/cpu usage, quicker camera switching
// Move lens picker to bottom right?
// Click on any readout -> shows vertical slider right side screen like halide
/// slider shows the auto value constantly updating, manually changing it turns on manual mode, for ss/iso have left iso right ss?
// Multiple graphs at once
/// Hold bottom graph to disappear, hold top graph to disappear
/// When no graph top, button owl be show to show a graph
/// To show graph at bottom go in settings?
// Show proper selfie cameras
// Tap to focus with focus EV
// Front and rear photos simultaneously
// Macro
// QR codes - shake to open
