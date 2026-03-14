internal import AVFoundation
import Foundation

extension CameraModel {
    func applyManualFocus() {
        guard let d = device else { return }
        beginManualFocusAdjustment()
        guard d.isLockingFocusWithCustomLensPositionSupported else {
            try? d.lockForConfiguration()
            d.focusMode = .continuousAutoFocus
            d.unlockForConfiguration()
            isAutoFocus = true
            return
        }
        try? d.lockForConfiguration()
        d.setFocusModeLocked(lensPosition: lensPosition) { _ in }
        d.unlockForConfiguration()
    }
    
    func setAutoFocus() {
        guard let d = device else { return }
        endManualFocusAdjustment()
        try? d.lockForConfiguration()
        d.focusMode = .continuousAutoFocus
        d.unlockForConfiguration()
    }
    
    func beginManualFocusAdjustment() {
        guard !isAutoFocus else { return }
        focusPeakingHoldTask?.cancel()
        isAdjustingManualFocus = true
    }
    
    func endManualFocusAdjustment() {
        focusPeakingHoldTask?.cancel()
        focusPeakingHoldTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }
            self.isAdjustingManualFocus = false
        }
    }
}
