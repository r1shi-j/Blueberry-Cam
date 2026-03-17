internal import AVFoundation
import Foundation

extension LockedCameraModel {
    func applyManualFocus() {
        guard let d = device else { return }
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
        try? d.lockForConfiguration()
        d.focusMode = .continuousAutoFocus
        d.unlockForConfiguration()
    }
}
