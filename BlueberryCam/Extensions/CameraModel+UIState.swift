import AVFoundation
import CoreLocation
import Foundation

extension CameraModel {
    // MARK: - UI Controls
    func hideSettings() {
        appView = .standard
    }
    
    func switchLens(to lens: Lens) {
        guard lens != activeLens else { return }
        guard let previewCamera = AVCaptureDevice.default(lens.deviceType, for: .video, position: lens.position) else { return }
        
        self.activeLens = lens
        self.flipRotation = 0
        self.primeResolutionOptions(for: lens, device: previewCamera)
        
        let lensDeviceType = lens.deviceType
        let lensPosition = lens.position
        let lensZoomFactor = lens.zoomFactor
        let lensIsFront = lens.isFront
        
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            
            self.session.beginConfiguration()
            for input in self.session.inputs { self.session.removeInput(input) }
            
            guard let cam = AVCaptureDevice.default(lensDeviceType, for: .video, position: lensPosition),
                  let input = try? AVCaptureDeviceInput(device: cam),
                  self.session.canAddInput(input) else {
                self.session.commitConfiguration()
                return
            }
            self.session.addInput(input)
            
            if lensZoomFactor > 1.0 {
                try? cam.lockForConfiguration()
                cam.videoZoomFactor = lensZoomFactor
                cam.unlockForConfiguration()
            }
            
            // Set orientation on connections (iOS 15 compatible)
            for conn in [self.photoOutput.connection(with: .video),
                         self.videoOutput.connection(with: .video)].compactMap({ $0 }) {
                if conn.isVideoOrientationSupported {
                    conn.videoOrientation = .portrait
                }
                conn.isVideoMirrored = lensIsFront
            }
            
            self.session.commitConfiguration()
            
            Task { @MainActor in
                self.device = cam
                self.configureSubjectAreaMonitoring(for: cam)
                
                self.buildAvailableFormats()
                let previousShutterDuration: CMTime? = (!self.isAutoExposure && self.shutterSpeeds.indices.contains(self.shutterIndex)) ? self.shutterSpeeds[self.shutterIndex] : nil
                self.updateDeviceRanges()
                self.normalizeFlashModeForCurrentDevice()
                self.enforceExposureModeConstraints()
                
                
                self.reapplyManualSettingsAfterLensSwitch(previousShutterDuration: previousShutterDuration)
                
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
                shutterIndex = shutterSpeeds.indices.min { a, b in
                    abs(CMTimeGetSeconds(shutterSpeeds[a]) - prevSecs) < abs(CMTimeGetSeconds(shutterSpeeds[b]) - prevSecs)
                } ?? 0
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
