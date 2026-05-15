internal import AVFoundation
import Foundation

extension LockedCameraModel {
    var supportsFlash: Bool {
        guard device?.hasFlash == true else { return false }
        return !photoOutput.supportedFlashModes.isEmpty
    }
    
    var supportsMacro: Bool {
        guard let ultraWide = Lens.ultraWide.captureDevice() else { return false }
        return ultraWide.minimumFocusDistance > 0 && ultraWide.minimumFocusDistance <= 150
    }
    
    var supportsManualFocus: Bool {
        device?.isLockingFocusWithCustomLensPositionSupported ?? false
    }
    
    var availableLensOptions: [Lens] {
        let baseLenses: [Lens] = [.ultraWide, .wide, .tele2x, .tele4x, .tele8x]
        
        let hardwareLenses = baseLenses.filter { $0 == activeLens || $0.captureDevice() != nil }
        
        // Filter out lenses incompatible with current capture mode / resolution
        let modeFilteredLenses = hardwareLenses.filter { lens in
            // Always keep the active lens visible
            if lens == activeLens { return true }
            // RAW requires lenses that preserve RAW capture
            if captureMode == .raw { return lens.preservesRawCaptureMode }
            // 48MP requires lenses that preserve high-resolution capture
            if isHighResolutionSelected { return lens.preservesHighResolutionCapture }
            return true
        }
        
        return modeFilteredLenses
    }
    
    func shownAvailableFormats(includeRaw: Bool = true) -> [CaptureMode] {
        let sourceFormats = availableFormats.isEmpty ? CaptureMode.allCases : availableFormats
        return sourceFormats.filter { mode in
            (includeRaw || !mode.isRawLike)
        }
    }
    
    func preferredProcessedCaptureMode(in modes: [CaptureMode]) -> CaptureMode? {
        let processedModes = modes.filter(\.isProcessed)
        if defaultFileFormat.isProcessed, processedModes.contains(defaultFileFormat) {
            return defaultFileFormat
        }
        
        return CaptureMode.processedFallbackOrder.first { processedModes.contains($0) }
    }
    
    func buildAvailableFormats() {
        // We only enforce this logic if the device is ready.
        guard device != nil else { return }
        
        let rawPixelFormatTypes = photoOutput.availableRawPhotoPixelFormatTypes
        
        var visibleModes: [CaptureMode] = []
        if photoOutput.availablePhotoCodecTypes.contains(.hevc) {
            visibleModes.append(.heif)
        }
        visibleModes.append(.jpeg)
        if rawPixelFormatTypes.contains(where: AVCapturePhotoOutput.isBayerRAWPixelFormat) {
            visibleModes.append(.raw)
        }
        if rawPixelFormatTypes.contains(where: AVCapturePhotoOutput.isAppleProRAWPixelFormat) {
            visibleModes.append(.proRaw)
        }
        if availableFormats != visibleModes {
            availableFormats = visibleModes
        }
        
        let modes: [CaptureMode]
        if isAutoExposure {
            modes = visibleModes.filter { mode in
                switch mode {
                    case .jpeg, .heif:
                        return true
                    case .raw:
                        return canSelectBayerRawForCurrentState
                    case .proRaw:
                        return canSelectAppleProRawForCurrentState
                }
            }
        } else {
            modes = visibleModes.filter { $0 == .raw }
        }
        if enabledFormats != modes {
            enabledFormats = modes
        }
        
        // SMART SWITCH: Keep the current selection if valid, else fallback to preference, else base fallback.
        if let targetMode = preferredCaptureMode(in: modes), captureMode != targetMode {
            captureMode = targetMode
        }
        
        let isCropLens = activeLens == .tele2x || activeLens == .tele8x
        
        let visibleOptions: [ResolutionOption]
        
        let outputMax = photoOutput.maxPhotoDimensions
        let allDims = (device?.activeFormat.supportedMaxPhotoDimensions ?? [])
            .filter { $0.width <= outputMax.width && $0.height <= outputMax.height }
            .sorted { Int($0.width) * Int($0.height) < Int($1.width) * Int($1.height) }
        
        var deduped: [ResolutionOption] = []
        for dim in allDims {
            let opt = ResolutionOption(width: dim.width, height: dim.height)
            if !deduped.contains(where: { abs($0.id - opt.id) < 2_000_000 }) {
                deduped.append(opt)
            }
        }
        // Always show 12MP + 48MP for back optical lenses
        let smallest = deduped.first
        let largest = deduped.last
        if let s = smallest, let l = largest, s.id != l.id {
            visibleOptions = [s, l]
        } else {
            visibleOptions = deduped
        }
        
        
        let enabledOptions: [ResolutionOption]
        if requiresLowResolutionForCurrentState(isCropLens: isCropLens) {
            enabledOptions = visibleOptions.first.map { [$0] } ?? []
        } else {
            enabledOptions = visibleOptions
        }
        
        let sameVisibleOptions = availableResolutions.count == visibleOptions.count &&
        zip(availableResolutions, visibleOptions).allSatisfy { $0.id == $1.id }
        if !sameVisibleOptions {
            availableResolutions = visibleOptions
        }
        
        let sameEnabledOptions = enabledResolutions.count == enabledOptions.count &&
        zip(enabledResolutions, enabledOptions).allSatisfy { $0.id == $1.id }
        if !sameEnabledOptions {
            enabledResolutions = enabledOptions
        }
        
        // Try current selection first, then the cached selection for this lens, then default
        let cachedSelection = cachedResolutionOptionsByLens[activeLens]?.selectedOption
        let candidates = [selectedResolution, cachedSelection].compactMap { $0 }
        
        if let match = candidates.first(where: { candidate in
            enabledOptions.contains(where: { $0.id == candidate.id })
        }) {
            if selectedResolution?.id != match.id {
                selectedResolution = match
            }
        } else {
            selectedResolution = defaultResolution == .max ? enabledOptions.last : enabledOptions.first
        }
        
        cacheResolutionOptions(for: activeLens,
                               availableOptions: visibleOptions,
                               enabledOptions: enabledOptions)
    }
    
    func primeResolutionOptions(for lens: Lens, device _: AVCaptureDevice) {
        let cachedSnapshot = cachedResolutionOptionsByLens[lens]
        let fallbackSnapshot = cachedResolutionOptionsByLens[.wide] ?? cachedResolutionOptionsByLens.values.first
        guard let sourceSnapshot = cachedSnapshot ?? fallbackSnapshot else { return }
        let snapshot = resolutionOptionsSnapshot(for: lens,
                                                 availableOptions: sourceSnapshot.availableOptions)
        applyResolutionOptionsSnapshot(snapshot)
    }
    
    private func cacheResolutionOptions(for lens: Lens,
                                        availableOptions: [ResolutionOption],
                                        enabledOptions: [ResolutionOption]) {
        guard !lens.isFront else { return }
        cachedResolutionOptionsByLens[lens] = .init(availableOptions: availableOptions,
                                                    enabledOptions: enabledOptions,
                                                    selectedOption: selectedResolution)
    }
    
    private func resolutionOptionsSnapshot(for lens: Lens,
                                           availableOptions: [ResolutionOption]) -> ResolutionOptionsSnapshot {
        let isCropLens = lens == .tele2x || lens == .tele8x
        let enabledOptions: [ResolutionOption]
        if requiresLowResolutionForCurrentState(isCropLens: isCropLens) {
            enabledOptions = availableOptions.first.map { [$0] } ?? []
        } else {
            enabledOptions = availableOptions
        }
        
        // Try current selection first, then the cached selection for this lens, then default
        let cachedSelection = cachedResolutionOptionsByLens[lens]?.selectedOption
        let candidates = [selectedResolution, cachedSelection].compactMap { $0 }
        
        let selectedOption: ResolutionOption?
        if enabledOptions.isEmpty {
            selectedOption = nil
        } else if let match = candidates.first(where: { candidate in
            enabledOptions.contains(where: { $0.id == candidate.id })
        }) {
            selectedOption = match
        } else {
            selectedOption = defaultResolution == .max ? enabledOptions.last : enabledOptions.first
        }
        
        return .init(availableOptions: availableOptions,
                     enabledOptions: enabledOptions,
                     selectedOption: selectedOption)
    }
    
    private func applyResolutionOptionsSnapshot(_ snapshot: ResolutionOptionsSnapshot) {
        if availableResolutions != snapshot.availableOptions {
            availableResolutions = snapshot.availableOptions
        }
        if enabledResolutions != snapshot.enabledOptions {
            enabledResolutions = snapshot.enabledOptions
        }
        if selectedResolution != snapshot.selectedOption {
            selectedResolution = snapshot.selectedOption
        }
    }
    
    func normalizeFlashModeForCurrentDevice() {
        guard supportsFlash else {
            flashMode = .off
            return
        }
        if !photoOutput.supportedFlashModes.contains(flashMode) {
            flashMode = photoOutput.supportedFlashModes.contains(.auto) ? .auto : .off
        }
        if !isAutoExposure {
            flashMode = .off
        }
    }
    
    func enforceExposureModeConstraints() {
        if !isAutoExposure {
            flashMode = .off
            if isMacroEnabled {
                isMacroEnabled = false
            }
            if captureMode != .raw || !activeLens.preservesRawCaptureMode {
                switchToRawCaptureMode(.raw)
            }
        }
    }
    
    func updateDeviceRanges() {
        guard let d = device else { return }
        minISO = d.activeFormat.minISO
        maxISO = d.activeFormat.maxISO
        isoStops = availableISOStops
        
        let shutterOptions = generateShutterStops(for: d)
        shutterSpeeds = shutterOptions.map(\.duration)
        shutterIndex = shutterSpeeds.indices.min(by: {
            abs(CMTimeGetSeconds(shutterSpeeds[$0]) - 1.0/60.0) <
                abs(CMTimeGetSeconds(shutterSpeeds[$1]) - 1.0/60.0)
        }) ?? 0
        
        liveISO = d.iso
        liveShutter = Self.formatShutter(d.exposureDuration)
        minExposureBias = d.minExposureTargetBias
        maxExposureBias = d.maxExposureTargetBias
        
        // Always clamp iso to the new device's valid range (handles lens switches where minISO changes)
        let newISO = max(minISO, min(maxISO, iso))
        if newISO != iso { iso = newISO }
    }
    
    private func generateShutterStops(for device: AVCaptureDevice) -> [(denominator: Int, duration: CMTime)] {
        let fmt = device.activeFormat
        let minSecs = CMTimeGetSeconds(fmt.minExposureDuration)
        let maxSecs = CMTimeGetSeconds(fmt.maxExposureDuration)
        
        return preferredShutterDenominators.compactMap { denominator in
            let seconds = 1.0 / Double(denominator)
            guard seconds >= minSecs - 1e-9 && seconds <= maxSecs + 1e-9 else { return nil }
            return (denominator, CMTimeMake(value: 1, timescale: CMTimeScale(denominator)))
        }
    }
    
    static func formatShutter(_ time: CMTime) -> String {
        let secs = CMTimeGetSeconds(time)
        guard secs.isFinite && secs > 0 else { return "—" }
        if secs >= 1.0 { return "\(secs.formatted(.number.precision(.fractionLength(1))))s" }
        return "1/\(Int(round(1.0 / secs)))s"
    }
    
    static func formatISO(_ iso: Float) -> String {
        Double(iso).formatted(.number.precision(.fractionLength(0)))
    }
    
    // MARK: - Capture Settings
    func isFormatEnabled(_ mode: CaptureMode) -> Bool {
        if mode == .raw {
            return canSelectRawCaptureMode
        }
        
        if mode == .proRaw {
            return canSelectAppleProRawCaptureMode
        }
        
        return enabledFormats.contains(mode)
    }
    
    var canSelectRawCaptureMode: Bool {
        guard availableFormats.contains(.raw) else { return false }
        guard !isHighResolutionSelected else { return false }
        return canSelectBayerRawForCurrentState
    }
    
    var canSelectAppleProRawCaptureMode: Bool {
        guard availableFormats.contains(.proRaw) else { return false }
        if isHighResolutionSelected {
            guard canSelectHighResolution else { return false }
        }
        return canSelectAppleProRawForCurrentState
    }
    
    private var canSelectBayerRawForCurrentState: Bool {
        guard activeLens.preservesRawCaptureMode else { return false }
        if !isAutoExposure { return true }
        guard !isMacroEnabled else { return false }
        return (device?.videoZoomFactor ?? 1.0) == 1.0
    }
    
    private var canSelectAppleProRawForCurrentState: Bool {
        guard isAutoExposure else { return false }
        guard activeLens.preservesProRawCaptureMode else { return false }
        return true
    }
    
    func isResolutionEnabled(_ option: ResolutionOption) -> Bool {
        if isHighResolutionOption(option) {
            return canSelectHighResolution
        }
        
        return enabledResolutions.contains(where: { $0.id == option.id })
    }
    
    var isHighResolutionSelected: Bool {
        guard let selectedResolution else { return false }
        return isHighResolutionOption(selectedResolution)
    }
    
    var canSelectHighResolution: Bool {
        guard !activeLens.isFront,
              captureMode != .raw,
              isAutoExposure,
              !isMacroEnabled,
              highResolutionOption != nil else { return false }
        if captureMode == .proRaw, flashMode != .off {
            return false
        }
        return activeLens.preservesHighResolutionCapture
    }
    
    private var highResolutionOption: ResolutionOption? {
        guard availableResolutions.count > 1 else { return nil }
        return availableResolutions.last
    }
    
    private func requiresLowResolutionForCurrentState(isCropLens: Bool) -> Bool {
        isCropLens ||
        isMacroEnabled ||
        (captureMode == .proRaw && flashMode != .off) ||
        !isAutoExposure ||
        captureMode == .raw
    }
    
    func isHighResolutionOption(_ option: ResolutionOption) -> Bool {
        highResolutionOption?.id == option.id
    }
    
    private func preferredCaptureMode(in modes: [CaptureMode]) -> CaptureMode? {
        if modes.contains(captureMode) {
            return captureMode
        }
        
        if modes.contains(defaultFileFormat) {
            return defaultFileFormat
        }
        
        return preferredProcessedCaptureMode(in: modes) ?? modes.first
    }
}
