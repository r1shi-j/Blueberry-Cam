internal import AVFoundation
import Foundation

extension LockedCameraModel {
    func switchLens(to lens: Lens) {
        let lens = switchableLens(for: lens)
        guard !isSwitchingLens else { return }
        guard lens != activeLens else { return }
        guard let previewCamera = lens.captureDevice() else { return }
        let previousLens = activeLens
        
        // 1. Instant UI update to trigger animations and selection state
        isSwitchingLens = true
        self.activeLens = lens
        self.primeResolutionOptions(for: lens, device: previewCamera)
        
        // 2. Capture lens properties before crossing isolation boundary
        let previewCameraUniqueID = previewCamera.uniqueID
        let lensZoomFactor = lens.zoomFactor
        
        // 3. Heavy hardware reconfiguration in background
        sessionQueue.async { [weak self] in
            guard let self else { return }
            
            self.session.beginConfiguration()
            for input in self.session.inputs { self.session.removeInput(input) }
            
            guard let cam = Lens.captureDevice(uniqueID: previewCameraUniqueID) ?? lens.captureDevice(),
                  let input = try? AVCaptureDeviceInput(device: cam),
                  self.session.canAddInput(input) else {
                self.session.commitConfiguration()
                Task { @MainActor in
                    self.activeLens = previousLens
                    self.isSwitchingLens = false
                    self.lensSwitchCompletionCount += 1
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
            
            // Connection properties (Hardware)
            let rotationAngle = Lens.rotationAngle(for: cam, lens: lens)
            let isMirrored = Lens.isMirrored(cam, lens: lens)
            for conn in [self.photoOutput.connection(with: .video),
                         self.videoOutput.connection(with: .video)].compactMap({ $0 }) {
                if conn.isVideoRotationAngleSupported(rotationAngle) {
                    conn.videoRotationAngle = rotationAngle
                }
                conn.isVideoMirrored = isMirrored
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
                self.captureRotationCoordinator = AVCaptureDevice.RotationCoordinator(device: cam, previewLayer: nil)
                self.lensSwitchCompletionCount += 1
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
}
