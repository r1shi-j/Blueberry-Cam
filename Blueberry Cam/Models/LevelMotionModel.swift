import CoreMotion
import Observation
import UIKit

enum LevelDisplayMode: Equatable {
    case hidden // Normal handheld angle — no overlay
    case level // Phone nearly upright (portrait or landscape) — show horizon bar
    case flat // Phone nearly face-up/down — show crosshairs
}

@MainActor @Observable
final class LevelMotionModel {
    
    // MARK: - Published state
    /// Angle (degrees) of gravity projected onto the screen plane.
    /// 0° = portrait level, ±90° = landscape level.
    var tiltAngleDeg: Double = 0
    /// Smoothed gravity X component (for flat-mode crosshair X offset)
    var gravityX: Double = 0
    /// Smoothed gravity Y component (for flat-mode crosshair Y offset)
    var gravityY: Double = 0
    var displayMode: LevelDisplayMode = .hidden
    /// True when the horizon bar is within the snap threshold of a cardinal angle
    var isAligned: Bool = false
    /// True when the phone is nearly perfectly flat (crosshair aligned)
    var isCrosshairAligned: Bool = false
    /// Gravity projected onto the current SCREEN's XY plane (for crosshair offset).
    /// Accounts for device rotation so the crosshair always tracks the correct direction.
    var screenGravityX: Double = 0
    var screenGravityY: Double = 0
    
    // MARK: - Private
    private let motionManager = CMMotionManager()
    private let updateInterval: TimeInterval = 1.0 / 30.0
    private let impactGenerator = UIImpactFeedbackGenerator(style: .light)
    
    /// Phone is "nearly flat" when |gz| > this (cos 25° ≈ 0.906)
    private let flatGZThreshold: Double = 0.85
    /// Phone is "nearly upright" when |gz| < this (sin 25° ≈ 0.42)
    private let uprightGZThreshold: Double = 0.42
    /// Snap-to-level threshold in degrees
    private let snapThreshold: Double = 1.0
    /// Flat crosshair alignment threshold — magnitude of xy-gravity < sin(1.5°)
    private let flatAlignThreshold: Double = 0.026
    /// Low-pass filter weight. Lower = smoother but laggier (0.15 ≈ nice and smooth)
    private let alpha: Double = 0.15
    
    private var prevIsAligned = false
    private var prevIsCrosshairAligned = false
    
    // MARK: - Lifecycle
    func startUpdates() {
        guard motionManager.isDeviceMotionAvailable else { return }
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        impactGenerator.prepare()
        motionManager.deviceMotionUpdateInterval = updateInterval
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }
            self.handleMotion(motion)
        }
    }
    
    func stopUpdates() {
        motionManager.stopDeviceMotionUpdates()
        UIDevice.current.endGeneratingDeviceOrientationNotifications()
    }
    
    // MARK: - Motion Processing
    private func handleMotion(_ motion: CMDeviceMotion) {
        let gx = motion.gravity.x
        let gy = motion.gravity.y
        let gz = motion.gravity.z
        
        // Low-pass filter — smooth out rapid noise
        let rawAngle = atan2(gx, -gy) * 180.0 / .pi
        // Handle angle wrapping near ±180°
        var delta = rawAngle - tiltAngleDeg
        if delta > 180  { delta -= 360 }
        if delta < -180 { delta += 360 }
        tiltAngleDeg += alpha * delta
        
        gravityX = alpha * gx + (1 - alpha) * gravityX
        gravityY = alpha * gy + (1 - alpha) * gravityY
        
        // Map smoothed gravity into current screen-space coordinates.
        // Canvas +X = screen right, canvas +Y = screen down.
        // When the app rotates to landscape the canvas rotates too, so we
        // must also rotate the gravity vector to match.
        let (sGX, sGY) = Self.gravityToScreen(gx: gravityX, gy: gravityY)
        screenGravityX = sGX
        screenGravityY = sGY
        
        // Mode detection: use |gz| to decide how flat vs upright the phone is
        let absGZ = abs(gz)
        let newMode: LevelDisplayMode
        if absGZ > flatGZThreshold {
            newMode = .flat
        } else if absGZ < uprightGZThreshold {
            newMode = .level
        } else {
            newMode = .hidden
        }
        if newMode != displayMode { displayMode = newMode }
        
        // Level alignment: deviation from nearest 0°, 90°, 180°, 270°
        let remainder = tiltAngleDeg.truncatingRemainder(dividingBy: 90.0)
        let deviation = min(abs(remainder), 90.0 - abs(remainder))
        let newIsAligned = displayMode == .level && deviation < snapThreshold
        if newIsAligned && !prevIsAligned { impactGenerator.impactOccurred() }
        prevIsAligned = newIsAligned
        isAligned = newIsAligned
        
        // Flat crosshair alignment: phone very close to perfectly flat
        let xyMag = sqrt(gravityX * gravityX + gravityY * gravityY)
        let newIsCrosshairAligned = displayMode == .flat && xyMag < flatAlignThreshold
        if newIsCrosshairAligned && !prevIsCrosshairAligned { impactGenerator.impactOccurred() }
        prevIsCrosshairAligned = newIsCrosshairAligned
        isCrosshairAligned = newIsCrosshairAligned
    }
    
    // MARK: - Gravity → screen coordinate transform
    /// Maps raw device gravity (device axes) into canvas screen axes,
    /// accounting for the current interface / device orientation.
    private static func gravityToScreen(gx: Double, gy: Double) -> (Double, Double) {
        switch UIDevice.current.orientation {
            case .landscapeLeft: return (-gy, gx) // home on left
            case .landscapeRight: return ( gy, -gx) // home on right
            case .portraitUpsideDown: return (-gx, gy) // upside-down portrait
            default: return ( gx, -gy) // normal portrait: canvas +Y is down, device +Y is up
        }
    }
}
