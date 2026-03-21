import CoreMotion
import UIKit

@MainActor @Observable
final class LockedLevelMotionModel {
    var onGravityUpdate: ((Double, Double, Double) -> Void)?
    
    // MARK: - Private
    private let motionManager = CMMotionManager()
    private let updateInterval: TimeInterval = 1.0 / 30.0
    
    // MARK: - Lifecycle
    func startUpdates() {
        guard motionManager.isDeviceMotionAvailable else { return }
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
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
        
        // Publish gravity for camera orientation
        onGravityUpdate?(gx, gy, gz)
    }
}
