internal import AVFoundation
import Foundation

extension CameraModel {
    private var tapPointExposureBiasLimit: Float { 2.0 }
    private var tapPointExposureHandleTravel: CGFloat { 40 }
    private var tapPointDragPointsPerEV: CGFloat { 96 }
    private var tapPointExposureBiasStep: Float { 0.025 }
    
    var formattedISO: String { Self.formatISO(iso) }
    var isoStopIndex: Float {
        let stops = availableISOStops
        guard let nearestIndex = stops.indices.min(by: {
            abs(Float(stops[$0]) - iso) < abs(Float(stops[$1]) - iso)
        }) else { return 0 }
        return Float(nearestIndex)
    }
    var availableISOStops: [Float] {
        let filteredStops = preferredISOStops.filter { stop in
            stop >= minISO && stop <= maxISO
        }
        let boundedStops = ([minISO] + filteredStops + [maxISO]).sorted()
        
        var dedupedStops: [Float] = []
        for stop in boundedStops {
            guard dedupedStops.last.map({ abs($0 - stop) < 0.5 }) != true else { continue }
            dedupedStops.append(stop)
        }
        
        return dedupedStops
    }
    var maxISOStopIndex: Float { Float(max(0, availableISOStops.count - 1)) }
    var maxShutterIndex: Float { Float(max(0, shutterSpeeds.count - 1)) }
    var formattedShutterSpeed: String {
        guard shutterSpeeds.indices.contains(shutterIndex) else { return "--" }
        return Self.formatShutter(shutterSpeeds[shutterIndex])
    }
    
    func applyManualExposure() {
        clearTapPointInteraction(resetDeviceState: false)
        exposureDebounceTask?.cancel()
        exposureDebounceTask = Task {
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled, let d = device, shutterSpeeds.indices.contains(shutterIndex) else { return }
            try? d.lockForConfiguration()
            let clampedISO = max(d.activeFormat.minISO, min(d.activeFormat.maxISO, iso))
            d.setExposureModeCustom(duration: shutterSpeeds[shutterIndex], iso: clampedISO, completionHandler: nil)
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
        
        sessionQueue.async { Task { @MainActor in
            self.updateCameraControlsMode()
        }}
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
        let stepped = ((startBias + deltaEV) / tapPointExposureBiasStep).rounded() * tapPointExposureBiasStep
        let clamped = max(lowerBound, min(upperBound, stepped))
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
    
    func nearestISOStop(to value: Float) -> Float {
        let stops = availableISOStops
        guard let nearestIndex = nearestISOStopIndex(in: stops, to: value) else {
            return max(minISO, min(maxISO, value))
        }
        return stops[nearestIndex]
    }
    
    func nearestISOStopIndex(in stops: [Float], to value: Float) -> Int? {
        stops.indices.min {
            abs(stops[$0] - value) < abs(stops[$1] - value)
        }
    }
    
    func nearestShutterIndex(to duration: CMTime) -> Int? {
        let seconds = CMTimeGetSeconds(duration)
        guard seconds.isFinite && seconds > 0 else { return nil }
        
        return shutterSpeeds.indices.min {
            abs(CMTimeGetSeconds(shutterSpeeds[$0]) - seconds) < abs(CMTimeGetSeconds(shutterSpeeds[$1]) - seconds)
        }
    }
    
    func setExposureBias(_ bias: Float) {
        guard isAutoExposure else { return }
        
        let steppedBias = (bias / 0.1).rounded() * 0.1
        let lowerBound = max(minExposureBias, CameraModel.minEV)
        let upperBound = min(maxExposureBias, CameraModel.maxEV)
        let clampedBias = min(max(steppedBias, lowerBound), upperBound)
        
        guard clampedBias != exposureBias else { return }
        
        exposureBias = clampedBias
        applyExposureBias()
    }
    
    func setManualISOStopIndex(_ value: Float) {
        let stops = availableISOStops
        guard !stops.isEmpty else { return }
        
        let clampedIndex = min(max(Int(value.rounded()), 0), stops.count - 1)
        let nextISO = stops[clampedIndex]
        
        guard nextISO != iso || isAutoExposure else { return }
        
        if isAutoExposure {
            isAutoExposure = false
        }
        exposureBias = 0
        iso = nextISO
        liveISO = nextISO
        applyManualExposure()
    }
    
    func setManualShutterIndex(_ value: Float) {
        let clampedIndex = min(max(Int(value.rounded()), 0), shutterSpeeds.count - 1)
        
        guard shutterSpeeds.indices.contains(clampedIndex),
              clampedIndex != shutterIndex || isAutoExposure else { return }
        
        if isAutoExposure {
            isAutoExposure = false
        }
        exposureBias = 0
        shutterIndex = clampedIndex
        liveShutter = formattedShutterSpeed
        applyManualExposure()
    }
    
    func resetEV() {
        exposureBias = 0.0
    }
}
