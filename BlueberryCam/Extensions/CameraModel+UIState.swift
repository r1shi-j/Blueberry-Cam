internal import AVFoundation
internal import CoreLocation
import Foundation

extension CameraModel {
    // MARK: - UI Controls
    func hideSettings() {
        appView = .standard
    }
    
    func switchLens(to lens: Lens) {
        guard lens != activeLens else { return }
        guard let previewCamera = AVCaptureDevice.default(lens.deviceType, for: .video, position: lens.position) else { return }
        
        // 1. Instant UI update to trigger animations and selection state
        self.activeLens = lens
        self.flipRotation = 0
        self.primeResolutionOptions(for: lens, device: previewCamera)
        
        // 2. Heavy hardware reconfiguration in background
        sessionQueue.async { [weak self] in
            guard let self else { return }
            
            self.session.beginConfiguration()
            for input in self.session.inputs { self.session.removeInput(input) }
            
            guard let cam = AVCaptureDevice.default(lens.deviceType, for: .video, position: lens.position),
                  let input = try? AVCaptureDeviceInput(device: cam),
                  self.session.canAddInput(input) else {
                self.session.commitConfiguration()
                return
            }
            self.session.addInput(input)
            
            // Internal state that is non-observable can be set here
            // But 'device' and others are @Observable, so move to MainActor Task
            
            // Zoom Factor (Hardware)
            if lens.zoomFactor > 1.0 {
                try? cam.lockForConfiguration()
                cam.videoZoomFactor = lens.zoomFactor
                cam.unlockForConfiguration()
            }
            self.enableLensSmudgeDetectionIfSupported(on: cam)
            
            // Connection properties (Hardware)
            let isFront = lens.isFront
            let rotationAngle: CGFloat = isFront ? 0 : 90
            for conn in [self.photoOutput.connection(with: .video),
                         self.videoOutput.connection(with: .video)].compactMap({ $0 }) {
                if conn.isVideoRotationAngleSupported(rotationAngle) {
                    conn.videoRotationAngle = rotationAngle
                }
                conn.isVideoMirrored = isFront
            }
            
            self.session.commitConfiguration()
            
            // 3. Final synchronization back to UI state
            Task { @MainActor in
                self.device = cam
                self.rotationCoordinator = AVCaptureDevice.RotationCoordinator(device: cam, previewLayer: nil)
                self.configureLensSmudgeDetection(for: cam)
                self.configureSubjectAreaMonitoring(for: cam)
                
                if let largest = cam.activeFormat.supportedMaxPhotoDimensions.max(by: {
                    Int($0.width) * Int($0.height) < Int($1.width) * Int($1.height)
                }) {
                    self.photoOutput.maxPhotoDimensions = largest
                }
                
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
                self.lensSwitchCompletionCount += 1
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
        let target: Lens = activeLens.isFront ? .wide : .front
        switchLens(to: target)
    }
    
    func resetEV() {
        exposureBias = 0.0
    }
    
    func setCustomShutter(to val: Int) {
        manualShutterDenominator = 0
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
    
    func selectResolution(_ opt: ResolutionOption) {
        guard isResolutionEnabled(opt) else { return }
        selectedResolution = opt
    }
    
    func changeCaptureFormat(to mode: CaptureMode) {
        guard isFormatEnabled(mode) else { return }
        captureMode = mode
    }

    func changePhotoFilter(to filter: PhotoFilter) {
        selectedPhotoFilter = filter
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
}
