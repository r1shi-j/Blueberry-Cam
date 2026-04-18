import CoreMotion
import UIKit
internal import Combine

enum LevelDisplayMode: Equatable {
    case hidden
    case level
    case flat
}

@MainActor
final class LevelMotionModel: ObservableObject {
    var onGravityUpdate: ((Double, Double, Double) -> Void)?
    
    @Published private(set) var tiltAngleDeg: Double = 0
    @Published private(set) var gravityX: Double = 0
    @Published private(set) var gravityY: Double = 0
    @Published private(set) var displayMode: LevelDisplayMode = .hidden
    @Published private(set) var isAligned: Bool = false
    @Published private(set) var isCrosshairAligned: Bool = false
    @Published private(set) var screenGravityX: Double = 0
    @Published private(set) var screenGravityY: Double = 0
    
    private let motionManager = CMMotionManager()
    private let updateInterval: TimeInterval = 1.0 / 30.0
    private var impactGenerator = UIImpactFeedbackGenerator(style: .light)
    
    private let flatGZThreshold: Double = 0.85
    private let uprightGZThreshold: Double = 0.42
    private let snapThreshold: Double = 1.0
    private let flatAlignThreshold: Double = 0.026
    private let alpha: Double = 0.15
    
    private var prevIsAligned = false
    private var prevIsCrosshairAligned = false
    
    private var isLevelDisplayEnabled: Bool = true
    func setLevelDisplayEnabled(_ enabled: Bool) {
        isLevelDisplayEnabled = enabled
        if !enabled {
            displayMode = .hidden
        }
    }
    
    func startUpdates() {
        guard motionManager.isDeviceMotionAvailable else { return }
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        impactGenerator = UIImpactFeedbackGenerator(style: .light)
        impactGenerator.prepare()
        motionManager.deviceMotionUpdateInterval = updateInterval
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self = self, let motion = motion else { return }
            self.handleMotion(motion)
        }
    }
    
    func stopUpdates() {
        motionManager.stopDeviceMotionUpdates()
        UIDevice.current.endGeneratingDeviceOrientationNotifications()
    }
    
    private func handleMotion(_ motion: CMDeviceMotion) {
        let gx = motion.gravity.x
        let gy = motion.gravity.y
        let gz = motion.gravity.z
        
        onGravityUpdate?(gx, gy, gz)
        
        guard isLevelDisplayEnabled else {
            if displayMode != .hidden {
                displayMode = .hidden
            }
            return
        }
        
        let rawAngle = atan2(gx, -gy) * 180.0 / .pi
        var delta = rawAngle - tiltAngleDeg
        if delta >  180 { delta -= 360 }
        if delta < -180 { delta += 360 }
        tiltAngleDeg += alpha * delta
        
        gravityX = alpha * gx + (1 - alpha) * gravityX
        gravityY = alpha * gy + (1 - alpha) * gravityY
        
        let (sGX, sGY) = Self.gravityToScreen(gx: gravityX, gy: gravityY)
        screenGravityX = sGX
        screenGravityY = sGY
        
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
        
        let remainder = tiltAngleDeg.truncatingRemainder(dividingBy: 90.0)
        let deviation = min(abs(remainder), 90.0 - abs(remainder))
        let newIsAligned = displayMode == .level && deviation < snapThreshold
        if newIsAligned && !prevIsAligned { impactGenerator.impactOccurred() }
        prevIsAligned = newIsAligned
        isAligned = newIsAligned
        
        let xyMag = sqrt(gravityX * gravityX + gravityY * gravityY)
        let newIsCrosshairAligned = displayMode == .flat && xyMag < flatAlignThreshold
        if newIsCrosshairAligned && !prevIsCrosshairAligned { impactGenerator.impactOccurred() }
        prevIsCrosshairAligned = newIsCrosshairAligned
        isCrosshairAligned = newIsCrosshairAligned
    }
    
    private static func gravityToScreen(gx: Double, gy: Double) -> (Double, Double) {
        switch UIDevice.current.orientation {
            case .landscapeLeft:  return (-gy,  gx)
            case .landscapeRight: return ( gy, -gx)
            case .portraitUpsideDown: return (-gx, gy)
            default: return (gx, -gy)
        }
    }
}
