internal import AVFoundation
import Foundation

extension CameraModel {
    var supportsFlash: Bool {
        guard device?.hasFlash == true else { return false }
        return !photoOutput.supportedFlashModes.isEmpty
    }
    
    var supportsMacro: Bool {
        guard !isDualCameraEnabled else { return false }
        guard let ultraWide = Lens.ultraWide.captureDevice() else { return false }
        return ultraWide.minimumFocusDistance > 0 && ultraWide.minimumFocusDistance <= 150
    }
    
    var supportsManualFocus: Bool {
        guard !isDualCameraEnabled else { return false }
        return device?.isLockingFocusWithCustomLensPositionSupported ?? false
    }
    
    var shouldShowResolutionPicker: Bool {
        guard !isDualCameraEnabled,
              !isConfiguringDualCamera,
              !isDetachingPreviewForReconfiguration else { return false }
        return !activeLens.isFront && availableResolutions.count > 1
    }
    
    var shouldUseDualCameraFormatSet: Bool {
        isDualCameraEnabled ||
        isConfiguringDualCamera ||
        isDetachingPreviewForReconfiguration
    }
    
    var supportsSelfieToggle: Bool {
        guard !ProcessInfo.processInfo.isiOSAppOnMac else { return false }
        return Lens.supportsAlternateFacing(from: activeLens)
    }
    
    var canToggleSelfie: Bool {
        guard supportsSelfieToggle else { return false }
        if isDualCameraEnabled {
            return secondaryLens != nil && !isConfiguringDualCamera
        }
        
        let targetLens: Lens = activeLens.isFront ? .wide : (captureMode == .raw ? .frontUltraWide : .front)
        guard let currentDevice = device, let targetDevice = targetLens.captureDevice() else { return false }
        
        return currentDevice.uniqueID != targetDevice.uniqueID
    }
    
    var availableLensOptions: [Lens] {
        let baseLenses = activeLens.isFront
        ? [Lens.frontUltraWide, .front]
        : [.ultraWide, .wide, .tele2x, .tele4x, .tele8x]
        
        let hardwareLenses = baseLenses.filter { $0 == activeLens || $0.captureDevice() != nil }
        let compatibleLenses = isDualCameraEnabled ? hardwareLenses.filter { canUseDualCamera(mainLens: $0) } : hardwareLenses
        
        return compatibleLenses
    }
    
    var hasSwitchableLenses: Bool {
        availableLensOptions.contains { $0 != activeLens }
    }
    
    var preferredFilteredCaptureMode: CaptureMode? {
        preferredProcessedCaptureMode(in: shownAvailableFormats(includeRaw: false))
    }
    
    var formatPreferenceOptions: [CaptureMode] {
        let sourceFormats = availableFormats.isEmpty ? CaptureMode.allCases : availableFormats
        return CaptureMode.allCases.filter { mode in
            if mode.isRawLike {
                return sourceFormats.contains(mode) || shownCaptureFormats.contains(mode)
            }
            
            return sourceFormats.contains(mode)
        }
    }
    
    var defaultFileFormatOptions: [CaptureMode] {
        let options = formatPreferenceOptions.filter { shownCaptureFormats.contains($0) }
        return options.isEmpty ? shownCaptureFormats : options
    }
    
    var shouldShowDefaultFileFormatPicker: Bool {
        defaultFileFormatOptions.count > 1
    }
    
    var shownCaptureFormatsSummary: String {
        let selectedFormats = formatPreferenceOptions.filter { shownCaptureFormats.contains($0) }
        return selectedFormats.map(\.rawValue).joined(separator: ", ")
    }
    
    func isShownCaptureFormat(_ mode: CaptureMode) -> Bool {
        shownCaptureFormats.contains(mode)
    }
    
    func canToggleShownCaptureFormat(_ mode: CaptureMode) -> Bool {
        guard mode != .raw, formatPreferenceOptions.contains(mode) else { return false }
        guard shownCaptureFormats.contains(mode), mode.isProcessed else { return true }
        return shownCaptureFormats.filter(\.isProcessed).count > 1
    }
    
    func toggleShownCaptureFormat(_ mode: CaptureMode) {
        guard mode != .raw, formatPreferenceOptions.contains(mode) else { return }
        
        var formats = shownCaptureFormats
        if formats.contains(mode) {
            guard canToggleShownCaptureFormat(mode) else { return }
            formats.removeAll { $0 == mode }
        } else {
            formats.append(mode)
        }
        
        setShownCaptureFormats(formats)
    }
    
    func setShownCaptureFormats(_ formats: [CaptureMode]) {
        normalizeShownCaptureFormats(formats, availableModes: formatPreferenceOptions)
        repairDefaultFileFormatForShownFormats()
        buildAvailableFormats()
    }
    
    func shownAvailableFormats(includeRaw: Bool = true) -> [CaptureMode] {
        let sourceFormats = availableFormats.isEmpty ? CaptureMode.allCases : availableFormats
        return sourceFormats.filter { mode in
            (includeRaw || !mode.isRawLike) && shownCaptureFormats.contains(mode)
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
        
        let isFront = activeLens.isFront
        let rawPixelFormatTypes = photoOutput.availableRawPhotoPixelFormatTypes
        
        var visibleModes: [CaptureMode] = []
        if photoOutput.availablePhotoCodecTypes.contains(.hevc) {
            visibleModes.append(.heif)
        }
        visibleModes.append(.jpeg)
        if !isDualCameraEnabled, rawPixelFormatTypes.contains(where: AVCapturePhotoOutput.isBayerRAWPixelFormat) {
            visibleModes.append(.raw)
        }
        if !isDualCameraEnabled, rawPixelFormatTypes.contains(where: AVCapturePhotoOutput.isAppleProRAWPixelFormat) {
            visibleModes.append(.proRaw)
        }
        if availableFormats != visibleModes {
            availableFormats = visibleModes
        }
        normalizeShownCaptureFormats(shownCaptureFormats, availableModes: visibleModes)
        repairDefaultFileFormatForShownFormats()
        let visibleUserModes = visibleModes.filter { shownCaptureFormats.contains($0) }
        
        let modes: [CaptureMode]
        if isDualCameraEnabled {
            modes = visibleUserModes.filter { !$0.isRawLike }
        } else if isFilterRestrictingCaptureOptions {
            modes = visibleUserModes.filter { !$0.isRawLike }
        } else if isAutoExposure {
            modes = visibleUserModes.filter { mode in
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
            modes = visibleUserModes.filter { $0 == .raw }
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
        if isFront {
            visibleOptions = []
        } else {
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
        }
        
        let enabledOptions: [ResolutionOption]
        if isFront {
            enabledOptions = []
        } else if requiresLowResolutionForCurrentState(isCropLens: isCropLens) {
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
        
        if let current = selectedResolution,
           enabledOptions.contains(where: { $0.id == current.id }) {
            // Keep the user's current resolution when flash or other constraints only re-enable options.
        } else {
            selectedResolution = defaultResolution == .max ? enabledOptions.last : enabledOptions.first
        }
        
        cacheResolutionOptions(for: activeLens,
                               availableOptions: visibleOptions,
                               enabledOptions: enabledOptions)
        updateLiveFilterPreviewReferenceSize()
    }
    
    func primeResolutionOptions(for lens: Lens, device _: AVCaptureDevice) {
        guard !lens.isFront else {
            applyResolutionOptionsSnapshot(.init(availableOptions: [],
                                                 enabledOptions: [],
                                                 selectedOption: nil))
            return
        }
        
        let cachedSnapshot = cachedResolutionOptionsByLens[lens]
        let fallbackSnapshot = cachedResolutionOptionsByLens[.wide] ?? cachedResolutionOptionsByLens.values.first
        guard let sourceSnapshot = cachedSnapshot ?? fallbackSnapshot else { return }
        let snapshot = resolutionOptionsSnapshot(for: lens,
                                                 availableOptions: sourceSnapshot.availableOptions)
        applyResolutionOptionsSnapshot(snapshot)
        updateLiveFilterPreviewReferenceSize()
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
        
        let selectedOption: ResolutionOption?
        if enabledOptions.isEmpty {
            selectedOption = nil
        } else if let current = selectedResolution,
                  enabledOptions.contains(where: { $0.id == current.id }) {
            selectedOption = current
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
        
        // Update EV slider value (EV bounds are fixed -4...4 so this never crashes)
        syncEVToHardware()
        
        // ISO and shutter control values are seeded when setupCameraControls() rebuilds
        // controls after launch or lens switches. Setting them here can use stale bounds.
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
    
    static func formatCameraControlShutter(_ time: CMTime) -> String {
        let secs = CMTimeGetSeconds(time)
        guard secs.isFinite && secs > 0 else { return "—" }
        if secs >= 1.0 { return secs.formatted(.number.precision(.fractionLength(1))) }
        return "1/\(Int(round(1.0 / secs)))"
    }
    
    static func formatISO(_ iso: Float) -> String {
        Double(iso).formatted(.number.precision(.fractionLength(0)))
    }
    
    // MARK: - Capture Settings
    func isFormatEnabled(_ mode: CaptureMode) -> Bool {
        guard shownCaptureFormats.contains(mode) else { return false }
        
        if mode == .raw {
            guard !isFilterRestrictingCaptureOptions else { return false }
            return canSelectRawCaptureMode
        }
        
        if mode == .proRaw {
            guard !isFilterRestrictingCaptureOptions else { return false }
            return canSelectAppleProRawCaptureMode
        }
        
        return enabledFormats.contains(mode)
    }
    
    var canSelectRawCaptureMode: Bool {
        guard !isDualCameraEnabled else { return false }
        guard !isFilterRestrictingCaptureOptions else { return false }
        guard availableFormats.contains(.raw) else { return false }
        guard !isHighResolutionSelected else { return false }
        return canSelectBayerRawForCurrentState
    }
    
    var canSelectAppleProRawCaptureMode: Bool {
        guard !isDualCameraEnabled else { return false }
        guard !isFilterRestrictingCaptureOptions else { return false }
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
    
    private func normalizeShownCaptureFormats(_ formats: [CaptureMode], availableModes: [CaptureMode]) {
        let availableModes = availableModes.isEmpty ? CaptureMode.allCases : availableModes
        let selectedProcessedFormats = CaptureMode.processedFallbackOrder.filter { mode in
            formats.contains(mode) && availableModes.contains(mode)
        }
        
        var normalizedFormats: [CaptureMode] = []
        if selectedProcessedFormats.isEmpty {
            if let fallback = CaptureMode.processedFallbackOrder.first(where: { availableModes.contains($0) }) {
                normalizedFormats.append(fallback)
            }
        } else {
            normalizedFormats.append(contentsOf: selectedProcessedFormats)
        }
        normalizedFormats.append(.raw)
        if formats.contains(.proRaw) {
            normalizedFormats.append(.proRaw)
        }
        
        let orderedFormats = CaptureMode.allCases.filter { normalizedFormats.contains($0) }
        if shownCaptureFormats != orderedFormats {
            shownCaptureFormats = orderedFormats
        }
    }
    
    private func repairDefaultFileFormatForShownFormats() {
        guard !shownCaptureFormats.contains(defaultFileFormat) else { return }
        defaultFileFormat = .raw
    }
}
