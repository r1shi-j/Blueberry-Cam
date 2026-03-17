internal import AVFoundation
import Foundation

extension LockedCameraModel {
    func applyManualExposure() {
        if manualShutterDenominator > 0 {
            applyManualExposureWithDenominator(manualShutterDenominator)
            return
        }
        exposureDebounceTask?.cancel()
        exposureDebounceTask = Task {
            try? await Task.sleep(nanoseconds: 50_000_000)
            guard !Task.isCancelled, let d = device, shutterSpeeds.indices.contains(shutterIndex) else { return }
            try? d.lockForConfiguration()
            let clampedISO = max(d.activeFormat.minISO, min(d.activeFormat.maxISO, iso))
            d.setExposureModeCustom(duration: shutterSpeeds[shutterIndex], iso: clampedISO, completionHandler: nil)
            d.unlockForConfiguration()
        }
    }
    
    func applyManualExposureWithDenominator(_ denom: Int) {
        let duration = CMTimeMake(value: 1, timescale: CMTimeScale(max(1, denom)))
        exposureDebounceTask?.cancel()
        exposureDebounceTask = Task {
            try? await Task.sleep(nanoseconds: 50_000_000)
            guard !Task.isCancelled, let d = device else { return }
            try? d.lockForConfiguration()
            let clampedISO = max(d.activeFormat.minISO, min(d.activeFormat.maxISO, iso))
            d.setExposureModeCustom(duration: duration, iso: clampedISO, completionHandler: nil)
            d.unlockForConfiguration()
        }
    }
    
    func setAutoExposure() {
        guard let d = device else { return }
        try? d.lockForConfiguration()
        d.exposureMode = .continuousAutoExposure
        d.unlockForConfiguration()
        applyExposureBias()
    }
    
    func applyExposureBias() {
        guard let d = device else { return }
        let clamped = max(minExposureBias, min(maxExposureBias, exposureBias))
        try? d.lockForConfiguration()
        d.setExposureTargetBias(clamped, completionHandler: nil)
        d.unlockForConfiguration()
    }
}
