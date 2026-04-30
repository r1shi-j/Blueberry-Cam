internal import AVFoundation
internal import CoreLocation
import Foundation

extension CameraModel {
    // MARK: - UI Controls
    var showSimpleView: Bool {
        appView == .clean || appView == .settings || isBurstCapturing || (isTimerCountingDown && shouldHideUIWhileCountingDown)
    }
    
    func hideSettings() {
        appView = .standard
    }
    
    func switchLens(to lens: Lens) {
        let lens = switchableLens(for: lens)
        guard !isSwitchingLens else { return }
        guard lens != activeLens else { return }
        guard let previewCamera = AVCaptureDevice.default(lens.deviceType, for: .video, position: lens.position) else { return }
        let previousLens = activeLens
        
        // 1. Instant UI update to trigger animations and selection state
        isSwitchingLens = true
        self.activeLens = lens
        self.flipRotation = 0
        self.primeResolutionOptions(for: lens, device: previewCamera)
        
        // 2. Capture lens properties before crossing isolation boundary
        let lensDeviceType = lens.deviceType
        let lensPosition = lens.position
        let lensZoomFactor = lens.zoomFactor
        let lensIsFront = lens.isFront
        
        // 3. Heavy hardware reconfiguration in background
        sessionQueue.async { [weak self] in
            guard let self else { return }
            
            self.session.beginConfiguration()
            for input in self.session.inputs { self.session.removeInput(input) }
            
            guard let cam = AVCaptureDevice.default(lensDeviceType, for: .video, position: lensPosition),
                  let input = try? AVCaptureDeviceInput(device: cam),
                  self.session.canAddInput(input) else {
                self.session.commitConfiguration()
                Task { @MainActor in
                    self.activeLens = previousLens
                    self.isSwitchingLens = false
                }
                return
            }
            self.session.addInput(input)
            
            // Internal state that is non-observable can be set here
            // But 'device' and others are @Observable, so move to MainActor Task
            
            // Zoom Factor (Hardware)
            if lensZoomFactor > 1.0 {
                try? cam.lockForConfiguration()
                cam.videoZoomFactor = lensZoomFactor
                cam.unlockForConfiguration()
            }
            self.enableLensSmudgeDetectionIfSupported(on: cam)
            
            // Connection properties (Hardware)
            let rotationAngle: CGFloat = lensIsFront ? 0 : 90
            for conn in [self.photoOutput.connection(with: .video),
                         self.videoOutput.connection(with: .video)].compactMap({ $0 }) {
                if conn.isVideoRotationAngleSupported(rotationAngle) {
                    conn.videoRotationAngle = rotationAngle
                }
                conn.isVideoMirrored = lensIsFront
            }
            
            self.session.commitConfiguration()
            if self.photoOutput.connection(with: .video) != nil,
               let largest = cam.activeFormat.supportedMaxPhotoDimensions.max(by: {
                   Int($0.width) * Int($0.height) < Int($1.width) * Int($1.height)
               }) {
                self.photoOutput.maxPhotoDimensions = largest
            }
            
            // 4. Final synchronization back to UI state
            Task { @MainActor in
                self.device = cam
                self.lensSwitchCompletionCount += 1
                self.configureLensSmudgeDetection(for: cam)
                self.configureSubjectAreaMonitoring(for: cam)
                
                self.buildAvailableFormats()
                let previousShutterDuration: CMTime? = (!self.isAutoExposure && self.shutterSpeeds.indices.contains(self.shutterIndex)) ? self.shutterSpeeds[self.shutterIndex] : nil
                self.updateDeviceRanges()
                self.normalizeFlashModeForCurrentDevice()
                self.enforceExposureModeConstraints()
                
                if self.isMacroEnabled && lens != .ultraWide {
                    self.isMacroEnabled = false
                }
                if self.isMacroEnabled && lens == .ultraWide {
                    self.applyMacroMode()
                }
                
                self.reapplyManualSettingsAfterLensSwitch(previousShutterDuration: previousShutterDuration)
                self.setupCameraControls()
                
                if !cam.isLockingFocusWithCustomLensPositionSupported {
                    self.isAutoFocus = true
                }
                self.applyPendingCaptureModeAfterLensSwitch()
                self.isSwitchingLens = false
            }
        }
    }
    
    private func reapplyManualSettingsAfterLensSwitch(previousShutterDuration: CMTime?) {
        if !isAutoExposure {
            if let prevDuration = previousShutterDuration, !shutterSpeeds.isEmpty {
                let prevSecs = CMTimeGetSeconds(prevDuration)
                isUpdatingHardwareControl = true
                shutterIndex = shutterSpeeds.indices.min { a, b in
                    abs(CMTimeGetSeconds(shutterSpeeds[a]) - prevSecs) < abs(CMTimeGetSeconds(shutterSpeeds[b]) - prevSecs)
                } ?? 0
                isUpdatingHardwareControl = false
            }
            applyManualExposure()
        } else {
            setAutoExposure()
        }
        
        if !isAutoFocus {
            applyManualFocus()
        } else {
            setAutoFocus()
        }
        
        if !isAutoWhiteBalance {
            applyManualWhiteBalance()
        } else {
            setAutoWhiteBalance()
        }
    }
    
    func toggleSelfie() {
        let target: Lens = activeLens.isFront ? .wide : (captureMode == .raw ? .frontUltraWide : .front)
        switchLens(to: target)
    }
    
    func toggleClipping() { showClipping.toggle() }
    
    func toggleZebraStripes() { showZebraStripes.toggle() }
    
    func cycleHistogramMode(mode: inout HistogramMode, size: HistogramSize? = nil) {
        switch mode {
            case .luminance:
                mode = .color
            case .color:
                mode = .waveform
            case .waveform:
                mode = .parade
            case .parade:
                mode = .luminance
            case .none:
                if size == .small {
                    mode = defaultHistogramSmall == .none ? .waveform : defaultHistogramSmall
                } else if size == .large {
                    mode = defaultHistogramLarge == .none ? .luminance : defaultHistogramLarge
                } else {
                    mode = .luminance
                }
        }
    }
    
    func hideHistogram(for mode: HistogramSize) {
        mode == .small ? (histogramModeSmall = .none) : (histogramModeLarge = .none)
    }
    
    func resetEV() {
        exposureBias = 0.0
    }
    
    func setCustomShutter(to val: Int) {
        shutterIndex = val
    }
    
    func resetControl(for control: ManualControl) {
        switch control {
            case .ev:
                if isAutoExposure {
                    resetEV()
                    applyExposureBias()
                }
            case .iso:
                isAutoExposure = true
                setAutoExposure()
            case .ss:
                isAutoExposure = true
                setAutoExposure()
            case .f:
                isAutoFocus = true
                setAutoFocus()
            case .wb:
                isAutoWhiteBalance = true
        }
    }
    
    func syncAutoRulerValues(
        iso liveISO: Float,
        exposureDuration: CMTime,
        whiteBalanceTemperature: Float,
        lensPosition liveLensPosition: Float
    ) {
        if isAutoExposure {
            let nextISO = nearestISOStop(to: liveISO)
            if abs(iso - nextISO) > 0.1 {
                iso = nextISO
            }
            
            if let nextShutterIndex = nearestShutterIndex(to: exposureDuration),
               shutterIndex != nextShutterIndex {
                shutterIndex = nextShutterIndex
            }
        }
        
        if isAutoWhiteBalance {
            let nextWhiteBalance = snappedWhiteBalanceKelvin(whiteBalanceTemperature)
            if abs(whiteBalanceTargetKelvin - nextWhiteBalance) >= 50 {
                whiteBalanceTargetKelvin = nextWhiteBalance
            }
        }
        
        if isAutoFocus {
            let nextLensPosition = snappedFocusPosition(liveLensPosition)
            if abs(lensPosition - nextLensPosition) >= 0.005 {
                lensPosition = nextLensPosition
            }
        }
    }
    
    func selectResolution(_ opt: ResolutionOption) {
        guard isResolutionEnabled(opt) else { return }
        if isHighResolutionOption(opt), !activeLens.preservesHighResolutionCapture {
            switchLens(to: activeLens.highResolutionFallbackLens)
        }
        
        selectedResolution = opt
    }
    
    func changeCaptureFormat(to mode: CaptureMode) {
        guard isFormatEnabled(mode) else { return }
        if mode == .raw {
            switchToRawCaptureMode()
            return
        }
        
        captureMode = mode
    }
    
    func switchToRawCaptureMode() {
        guard canSelectRawCaptureMode else { return }
        
        if !activeLens.preservesRawCaptureMode {
            pendingCaptureModeAfterLensSwitch = .raw
            switchLens(to: activeLens.rawFallbackLens)
            return
        }
        captureMode = .raw
    }
    
    private func applyPendingCaptureModeAfterLensSwitch() {
        guard let pendingMode = pendingCaptureModeAfterLensSwitch else { return }
        pendingCaptureModeAfterLensSwitch = nil
        guard isFormatEnabled(pendingMode) else { return }
        captureMode = pendingMode
    }
    
    private func switchableLens(for lens: Lens) -> Lens {
        if captureMode == .raw {
            return lens.rawFallbackLens
        }
        
        if isHighResolutionSelected {
            return lens.highResolutionFallbackLens
        }
        
        return lens
    }
    
    func cycleFlashMode() {
        guard supportsFlash, isAutoExposure else {
            flashMode = .off
            return
        }
        
        let supported = photoOutput.supportedFlashModes
        let order: [AVCaptureDevice.FlashMode] = [.off, .auto, .on]
        let currentIndex = order.firstIndex(of: flashMode) ?? 0
        
        for offset in 1...order.count {
            let candidate = order[(currentIndex + offset) % order.count]
            if supported.contains(candidate) {
                flashMode = candidate
                return
            }
        }
        
        flashMode = .off
    }
    
    func toggleMacroMode() {
        guard supportsMacro, isAutoExposure else { return }
        
        if !isMacroEnabled {
            // Enabling macro: switch to Ultra Wide first
            if activeLens != .ultraWide {
                switchLens(to: .ultraWide)
            }
            isMacroEnabled = true
        } else {
            // Disabling macro
            isMacroEnabled = false
        }
    }
    
    func applyMacroMode() {
        if isMacroEnabled {
            guard let d = device else { return }
            try? d.lockForConfiguration()
            
            // 2. Apply "Macro" zoom (typically 2.0x on UW to match 1x FOV)
            if activeLens == .ultraWide {
                d.videoZoomFactor = 2.0
            }
            
            // 3. Optimize focus for near objects if supported
            if d.isAutoFocusRangeRestrictionSupported {
                d.autoFocusRangeRestriction = .near
            }
            
            d.unlockForConfiguration()
        } else {
            guard let d = device else { return }
            try? d.lockForConfiguration()
            if d.isAutoFocusRangeRestrictionSupported {
                d.autoFocusRangeRestriction = .none
            }
            // Reset zoom if we were in the macro-zoom state
            if activeLens == .ultraWide && d.videoZoomFactor == 2.0 {
                d.videoZoomFactor = 1.0
            }
            d.unlockForConfiguration()
        }
    }
    
    func cycleTimerMode() {
        if isBurstModeEnabled {
            isBurstModeEnabled = false
        }
        
        switch timerMode {
            case .off:
                timerMode = .threeSeconds
            case .threeSeconds:
                timerMode = .fiveSeconds
            case .fiveSeconds:
                timerMode = .tenSeconds
            case .tenSeconds:
                timerMode = .off
        }
    }
    
    func cycleFocusAssistMode() {
        if showFocusPeaking {
            showFocusPeaking = false
            showFocusLoupe = true
        } else if showFocusLoupe {
            showFocusLoupe = false
            showFocusPeaking = false
        } else {
            showFocusPeaking = true
            showFocusLoupe = false
        }
    }
    
    func changePhotoFilter(to filter: PhotoFilter) {
        selectedPhotoFilter = filter
    }
}
