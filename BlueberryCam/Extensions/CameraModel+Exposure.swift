import AVFoundation
import Foundation

extension CameraModel {
    private var tapPointExposureBiasLimit: Float { 2.0 }
    private var tapPointExposureHandleTravel: CGFloat { 40 }
    private var tapPointDragPointsPerEV: CGFloat { tapPointExposureHandleTravel / CGFloat(tapPointExposureBiasLimit) }
    
    func applyManualExposure() {
        clearTapPointInteraction(resetDeviceState: false)
        if manualShutterDenominator > 0 {
            applyManualExposureWithDenominator(manualShutterDenominator)
            return
        }
        exposureDebounceTask?.cancel()
        exposureDebounceTask = Task {
            try? await Task.sleep(nanoseconds: 50_000_000)
            guard !Task.isCancelled, let d = self.device, self.shutterSpeeds.indices.contains(self.shutterIndex) else { return }
            try? d.lockForConfiguration()
            let clampedISO = max(d.activeFormat.minISO, min(d.activeFormat.maxISO, self.iso))
            d.setExposureModeCustom(duration: self.shutterSpeeds[self.shutterIndex], iso: clampedISO, completionHandler: nil)
            d.unlockForConfiguration()
        }
    }
    
    func applyManualExposureWithDenominator(_ denom: Int) {
        let duration = CMTimeMake(value: 1, timescale: CMTimeScale(max(1, denom)))
        clearTapPointInteraction(resetDeviceState: false)
        exposureDebounceTask?.cancel()
        exposureDebounceTask = Task {
            try? await Task.sleep(nanoseconds: 50_000_000)
            guard !Task.isCancelled, let d = self.device else { return }
            try? d.lockForConfiguration()
            let clampedISO = max(d.activeFormat.minISO, min(d.activeFormat.maxISO, self.iso))
            d.setExposureModeCustom(duration: duration, iso: clampedISO, completionHandler: nil)
            d.unlockForConfiguration()
        }
    }
    
    func setAutoExposure() {
        guard let d = device else { return }
        clearTapPointInteraction(resetDeviceState: false)
        try? d.lockForConfiguration()
        d.exposureMode = .continuousAutoExposure
        d.unlockForConfiguration()
        applyExposureBias()
    }
    
    func applyExposureBias() {
        guard let d = device else { return }
        let requestedBias = exposureBias + ((tapFocusIndicatorPoint != nil && isAutoExposure) ? tapExposureBias : 0)
        let clamped = max(minExposureBias, min(maxExposureBias, requestedBias))
        try? d.lockForConfiguration()
        d.setExposureTargetBias(clamped, completionHandler: nil)
        d.unlockForConfiguration()
    }
    
    func applyAutoExposureMetering(at devicePoint: CGPoint) {
        guard let d = device else { return }
        try? d.lockForConfiguration()
        if d.isExposurePointOfInterestSupported {
            d.exposurePointOfInterest = devicePoint
        }
        if d.isExposureModeSupported(.continuousAutoExposure) {
            d.exposureMode = .continuousAutoExposure
        }
        d.unlockForConfiguration()
        applyExposureBias()
    }
    
    func updateTapExposureBias(from startBias: Float, verticalDrag: CGFloat) {
        guard canAdjustTapPointExposureBias else { return }
        let deltaEV = Float(-verticalDrag / tapPointDragPointsPerEV)
        let lowerBound = max(minExposureBias, -tapPointExposureBiasLimit)
        let upperBound = min(maxExposureBias, tapPointExposureBiasLimit)
        let clamped = max(lowerBound, min(upperBound, startBias + deltaEV))
        if abs(tapExposureBias - clamped) > 0.01 {
            tapExposureBias = clamped
            applyExposureBias()
        }
        updateTapFocusIndicatorOffset(forExposureBias: clamped)
    }
    
    func updateTapFocusIndicatorOffset(forExposureBias bias: Float) {
        let clamped = max(-tapPointExposureBiasLimit, min(tapPointExposureBiasLimit, bias))
        let normalized = CGFloat(clamped / tapPointExposureBiasLimit)
        updateTapFocusIndicatorOffset(-normalized * tapPointExposureHandleTravel)
    }
}

