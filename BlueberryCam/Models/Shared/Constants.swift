import SwiftUI

let backgroundColors: [Color] = [.black, .blue.opacity(0.3), .green.opacity(0.3), .pink.opacity(0.3)]

enum Colors {
    static let buttonBackground: Color = .white.opacity(0.15)
    static let buttonText: Color = .white.opacity(0.7)
    static let manualLabel: Color = .white.opacity(0.5)
}

enum Fonts {
    static let manualLabel: Font = .system(size: 10, weight: .bold, design: .monospaced)
    static let manualValue: Font = .system(size: 12, weight: .medium, design: .monospaced)
}

enum Alerts {
    static let ok = "OK"
    static let cancel = "Cancel"
    static let auto = "Auto"
    static let error = "Error"
    static let reset = "Reset"
    static let infinityString = "Infinity"
    static let resetSettingsTitle = "Are you sure you want to reset all custom settings?"
    static let burstIntervalTitle = "Burst Interval"
    static let burstIntervalMessage = "Minimum time (seconds) between frame starts.\nRange: 0.20 to 5.00.\nMay not be guaranteed for smaller intervals. Auto shoots as fast as safely possible."
    static let burstFramesTitle = "Burst Frames"
    static let burstFramesMessage = "Number of frames to capture.\nRange: 1 to 100.\nAuto keeps shooting until you tap the shutter button again."
}

enum Animations {
    static let easeInOut: Animation = .easeInOut(duration: 0.2)
    static let bouncy: Animation = .bouncy
    static let viewFinderShown: Animation = .easeInOut
    static let levelShown: Animation = .easeInOut(duration: 0.25)
    static let timerShown: Animation = .spring(response: 0.45, dampingFraction: 0.8)
    static let timerCountdown: Animation = .easeInOut(duration: 0.12)
    static let manualControlShown: Animation = .smooth(duration: 0.34)
    static let captureFlash: Animation = .easeOut(duration: 0.15)
    static let permissionsShown: Animation = .easeInOut(duration: 0.4)
    static let manualControlSnap: Animation = .snappy
    static let pipSnap: Animation = .spring(response: 0.34, dampingFraction: 0.66)
    static let readoutShown: Animation = .smooth(duration: 0.34)
    static let selfieToggled: Animation = .easeInOut(duration: 0.28)
}

enum Durations {
    static let shutter: Duration = .milliseconds(150)
}
