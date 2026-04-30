internal import AVFoundation
import Foundation

extension CameraModel {
    nonisolated func enableLensSmudgeDetectionIfSupported(on camera: AVCaptureDevice) {
        guard camera.activeFormat.isCameraLensSmudgeDetectionSupported else { return }
        try? camera.lockForConfiguration()
        camera.setCameraLensSmudgeDetectionEnabled(true, detectionInterval: CMTime(seconds: 30, preferredTimescale: 1))
        camera.unlockForConfiguration()
    }
    
    func configureLensSmudgeDetection(for camera: AVCaptureDevice) {
        lensSmudgeStatusObservation?.invalidate()
        lensSmudgeStatusObservation = nil
        
        guard camera.activeFormat.isCameraLensSmudgeDetectionSupported else {
            lensSmudgeDetectionStatus = .disabled
            shouldShowLensCleaningHint = false
            didDismissLensCleaningHint = false
            return
        }
        
        lensSmudgeDetectionStatus = camera.cameraLensSmudgeDetectionStatus
        updateLensCleaningHint(for: lensSmudgeDetectionStatus)
        
        lensSmudgeStatusObservation = camera.observe(\.cameraLensSmudgeDetectionStatus, options: [.initial, .new]) { [weak self] _, change in
            guard let status = change.newValue else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.lensSmudgeDetectionStatus = status
                self.updateLensCleaningHint(for: status)
            }
        }
    }
    
    func dismissLensCleaningHint() {
        didDismissLensCleaningHint = true
        shouldShowLensCleaningHint = false
    }
    
    private func updateLensCleaningHint(for status: AVCaptureCameraLensSmudgeDetectionStatus) {
        switch status {
            case .smudged:
                shouldShowLensCleaningHint = !didDismissLensCleaningHint
            case .smudgeNotDetected, .unknown, .disabled:
                shouldShowLensCleaningHint = false
                didDismissLensCleaningHint = false
            @unknown default:
                shouldShowLensCleaningHint = false
                didDismissLensCleaningHint = false
        }
    }
}
