internal import AVFoundation
import Foundation

extension LockedCameraModel {
    var formattedWhiteBalance: String { "\(Int(whiteBalanceTargetKelvin))K" }
    
    func applyManualWhiteBalance() {
        guard let d = device else { return }
        
        do {
            try d.lockForConfiguration()
        } catch {
            return
        }
        
        applyManualWhiteBalanceLocked()
        d.unlockForConfiguration()
    }
    
    private func applyManualWhiteBalanceLocked() {
        guard let d = device,
              d.isWhiteBalanceModeSupported(.locked) else {
            return
        }
        
        // Expanded bounding from 2000K (very cool/blue) to 10000K (very warm/orange)
        let kelvin = max(LockedCameraModel.minWhiteBalance, min(LockedCameraModel.maxWhiteBalance, whiteBalanceTargetKelvin))
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
    
    func snappedWhiteBalanceKelvin(_ kelvin: Float) -> Float {
        let steppedKelvin = (kelvin / 100).rounded() * 100
        return min(max(steppedKelvin, LockedCameraModel.minWhiteBalance), LockedCameraModel.maxWhiteBalance)
    }
    
    func setWhiteBalanceTargetKelvin(_ kelvin: Float) {
        let clampedKelvin = snappedWhiteBalanceKelvin(kelvin)
        
        guard clampedKelvin != whiteBalanceTargetKelvin || isAutoWhiteBalance else { return }
        
        if isAutoWhiteBalance {
            isAutoWhiteBalance = false
        }
        whiteBalanceTargetKelvin = clampedKelvin
        liveWB = formattedWhiteBalance
    }
}
