internal import AVFoundation
import Foundation

extension CameraModel {
    func applyManualWhiteBalance() {
        guard let d = device else { return }
        try? d.lockForConfiguration()
        applyManualWhiteBalanceLocked()
        d.unlockForConfiguration()
    }
    
    private func applyManualWhiteBalanceLocked() {
        guard let d = device else { return }
        // Expanded bounding from 2000K (very cool/blue) to 10000K (very warm/orange)
        let kelvin = max(2000, min(10000, whiteBalanceTargetKelvin))
        let tempAndTint = AVCaptureDevice.WhiteBalanceTemperatureAndTintValues(temperature: kelvin, tint: 0)
        let rawGains = d.deviceWhiteBalanceGains(for: tempAndTint)
        
        let maxGain = d.maxWhiteBalanceGain
        let clampedGains = AVCaptureDevice.WhiteBalanceGains(
            redGain: max(1.0, min(maxGain, rawGains.redGain)),
            greenGain: max(1.0, min(maxGain, rawGains.greenGain)),
            blueGain: max(1.0, min(maxGain, rawGains.blueGain))
        )
        
        d.setWhiteBalanceModeLocked(with: clampedGains, completionHandler: nil)
    }
    
    func setAutoWhiteBalance() {
        guard let d = device else { return }
        try? d.lockForConfiguration()
        if d.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
            d.whiteBalanceMode = .continuousAutoWhiteBalance
        }
        d.unlockForConfiguration()
    }
}
