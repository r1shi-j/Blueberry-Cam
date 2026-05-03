internal import AVFoundation
import Foundation

extension CameraModel {
    var supportsFlash: Bool {
        guard device?.hasFlash == true else { return false }
        return !photoOutput.supportedFlashModes.isEmpty
    }
    
    var supportsMacro: Bool {
        // Macro is typically supported on Pro models with AF on Ultra Wide.
        // We look for a back camera that can focus closer than 15cm (150mm).
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInUltraWideCamera, .builtInWideAngleCamera],
            mediaType: .video,
            position: .back
        )
        return discovery.devices.contains { $0.minimumFocusDistance > 0 && $0.minimumFocusDistance <= 150 }
    }
    
    var supportsManualFocus: Bool {
        device?.isLockingFocusWithCustomLensPositionSupported ?? false
    }
    
    func buildAvailableFormats() {
        // We only enforce this logic if the device is ready.
        guard device != nil else { return }
        
        let zoomBlocksRAW = (device?.videoZoomFactor ?? 1.0) > 1.0
        let isFront = activeLens.isFront
        
        var visibleModes: [CaptureMode] = []
        if photoOutput.availablePhotoCodecTypes.contains(.hevc) {
            visibleModes.append(.heif)
        }
        visibleModes.append(.jpeg)
        if !photoOutput.availableRawPhotoPixelFormatTypes.isEmpty {
            visibleModes.append(.raw)
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
                        return !zoomBlocksRAW && !isMacroEnabled
                }
            }
        } else {
            modes = visibleModes.filter { $0 == .raw }
        }
        if enabledFormats != modes {
            enabledFormats = modes
        }
        
        // SMART SWITCH: Keep the current selection if valid, else fallback to preference, else base fallback.
        let targetMode: CaptureMode
        if modes.contains(captureMode) {
            targetMode = captureMode
        } else if modes.contains(defaultFileFormat) {
            targetMode = defaultFileFormat
        } else {
            targetMode = modes.contains(.heif) ? .heif : .jpeg
        }
        
        if captureMode != targetMode {
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
        } else if isCropLens || isMacroEnabled || captureMode == .raw {
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
        
        if !sameEnabledOptions {
            // Options change (Format or Lens switch): re-apply resolution preference
            selectedResolution = defaultResolution == .max ? enabledOptions.last : enabledOptions.first
        } else if let current = selectedResolution, !enabledOptions.contains(where: { $0.id == current.id }) {
            // Current selection became invalid
            selectedResolution = defaultResolution == .max ? enabledOptions.last : enabledOptions.first
        }
    }
    
    func primeResolutionOptions(for lens: Lens, device: AVCaptureDevice) {
        let visibleOptions: [ResolutionOption]
        if lens.isFront {
            visibleOptions = []
        } else {
            let outputMax = device.activeFormat.supportedMaxPhotoDimensions.max(by: {
                Int($0.width) * Int($0.height) < Int($1.width) * Int($1.height)
            }) ?? photoOutput.maxPhotoDimensions
            let allDims = device.activeFormat.supportedMaxPhotoDimensions
                .filter { $0.width <= outputMax.width && $0.height <= outputMax.height }
                .sorted { Int($0.width) * Int($0.height) < Int($1.width) * Int($1.height) }
            
            var deduped: [ResolutionOption] = []
            for dim in allDims {
                let opt = ResolutionOption(width: dim.width, height: dim.height)
                if !deduped.contains(where: { abs($0.id - opt.id) < 2_000_000 }) {
                    deduped.append(opt)
                }
            }
            
            let smallest = deduped.first
            let largest = deduped.last
            if let s = smallest, let l = largest, s.id != l.id {
                visibleOptions = [s, l]
            } else {
                visibleOptions = deduped
            }
        }
        
        let isCropLens = lens == .tele2x || lens == .tele8x
        let enabledOptions: [ResolutionOption]
        if lens.isFront {
            enabledOptions = []
        } else if isCropLens || isMacroEnabled || captureMode == .raw {
            enabledOptions = visibleOptions.first.map { [$0] } ?? []
        } else {
            enabledOptions = visibleOptions
        }
        
        availableResolutions = visibleOptions
        enabledResolutions = enabledOptions
        
        if enabledOptions.isEmpty {
            selectedResolution = nil
        } else if let current = selectedResolution, enabledOptions.contains(where: { $0.id == current.id }) {
            return
        } else {
            selectedResolution = defaultResolution == .max ? enabledOptions.last : enabledOptions.first
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
            if captureMode != .raw {
                captureMode = .raw
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
        if mode == .raw {
            return canSelectRawCaptureMode
        }
        
        return enabledFormats.contains(mode)
    }
    
    var canSelectRawCaptureMode: Bool {
        guard availableFormats.contains(.raw) else { return false }
        guard !isHighResolutionSelected else { return false }
        guard isAutoExposure, !isMacroEnabled else { return enabledFormats.contains(.raw) }
        return hasRawCapableLensForCurrentFacing
    }
    
    private var hasRawCapableLensForCurrentFacing: Bool {
        Lens.allCases.contains { lens in
            lens.isFront == activeLens.isFront &&
            lens.preservesRawCaptureMode &&
            AVCaptureDevice.default(lens.deviceType, for: .video, position: lens.position) != nil
        }
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
              !isMacroEnabled,
              highResolutionOption != nil else { return false }
        return hasHighResolutionCapableBackLens
    }
    
    private var highResolutionOption: ResolutionOption? {
        guard availableResolutions.count > 1 else { return nil }
        return availableResolutions.last
    }
    
    func isHighResolutionOption(_ option: ResolutionOption) -> Bool {
        highResolutionOption?.id == option.id
    }
    
    private var hasHighResolutionCapableBackLens: Bool {
        Lens.allCases.contains { lens in
            !lens.isFront &&
            lens.preservesHighResolutionCapture &&
            AVCaptureDevice.default(lens.deviceType, for: .video, position: .back) != nil
        }
    }
}
