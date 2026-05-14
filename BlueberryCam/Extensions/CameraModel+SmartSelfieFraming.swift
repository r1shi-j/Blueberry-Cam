internal import AVFoundation
import CoreGraphics
import Foundation

extension CameraModel {
    func refreshSmartSelfieFraming() {
        let available = smartSelfieFramingHardwareAvailable
        if isSmartSelfieFramingAvailable != available {
            isSmartSelfieFramingAvailable = available
        }
        
        guard available else {
            stopSmartSelfieFramingMonitoring()
            if isSmartSelfieFramingEnabled {
                isSmartSelfieFramingEnabled = false
            }
            return
        }
        
        guard isSmartSelfieFramingEnabled,
              activeLens.isFront,
              !isDualCameraEnabled,
              !isConfiguringDualCamera,
              !isDetachingPreviewForReconfiguration,
              !isTimerCountingDown,
              !isBurstCapturing,
              let camera = device else {
            stopSmartSelfieFramingMonitoring()
            return
        }
        
        refreshSmartSelfieCenterStage(for: camera)
        
        guard camera.activeFormat.isSmartFramingSupported,
              let monitor = camera.smartFramingMonitor else {
            stopSmartSelfieFramingMonitor()
            return
        }
        
        startSmartSelfieFramingMonitoring(monitor)
    }
    
    private var smartSelfieFramingHardwareAvailable: Bool {
        [Lens.frontUltraWide, .front]
            .compactMap { $0.captureDevice() }
            .contains { camera in
                camera.smartFramingMonitor != nil || camera.formats.contains { $0.isCenterStageSupported }
            }
    }
    
    private var canApplySmartSelfieFramingRecommendation: Bool {
        isSmartSelfieFramingEnabled &&
        isCaptureSessionRunning &&
        isSmartSelfieFramingMonitoring &&
        activeLens.isFront &&
        !isDualCameraEnabled &&
        !isConfiguringDualCamera &&
        !isDetachingPreviewForReconfiguration &&
        !isTimerCountingDown &&
        !isBurstCapturing &&
        !isSwitchingLens &&
        !isCaptureAspectRatioTransitioning
    }
    
    private var canContinueSmartSelfieFramingApplication: Bool {
        isSmartSelfieFramingEnabled &&
        isCaptureSessionRunning &&
        activeLens.isFront &&
        !isDualCameraEnabled &&
        !isConfiguringDualCamera &&
        !isDetachingPreviewForReconfiguration &&
        !isTimerCountingDown &&
        !isBurstCapturing &&
        !isSwitchingLens
    }
    
    private func refreshSmartSelfieCenterStage(for camera: AVCaptureDevice) {
        guard captureMode != .raw else {
            stopSmartSelfieCenterStage()
            return
        }
        
        guard camera.activeFormat.isCenterStageSupported else {
            stopSmartSelfieCenterStage()
            return
        }
        
        enableSmartSelfieGeometricDistortionCorrectionIfNeeded(for: camera)
        configureSmartSelfieCenterStageActiveObservation(for: camera)
        
        AVCaptureDevice.centerStageControlMode = .cooperative
        if !AVCaptureDevice.isCenterStageEnabled {
            AVCaptureDevice.isCenterStageEnabled = true
        }
        didEnableSmartSelfieCenterStage = true
        
        let active = camera.isCenterStageActive
        if isSmartSelfieCenterStageActive != active {
            isSmartSelfieCenterStageActive = active
        }
    }
    
    private func enableSmartSelfieGeometricDistortionCorrectionIfNeeded(for camera: AVCaptureDevice) {
        guard camera.isGeometricDistortionCorrectionSupported,
              !camera.isGeometricDistortionCorrectionEnabled else { return }
        
        do {
            try camera.lockForConfiguration()
            camera.isGeometricDistortionCorrectionEnabled = true
            camera.unlockForConfiguration()
        } catch {
            return
        }
    }
    
    private func configureSmartSelfieCenterStageActiveObservation(for camera: AVCaptureDevice) {
        guard smartSelfieCenterStageDeviceUniqueID != camera.uniqueID else { return }
        
        smartSelfieCenterStageDeviceUniqueID = camera.uniqueID
        smartSelfieCenterStageActiveObservation = camera.observe(\.isCenterStageActive, options: [.initial, .new]) { [weak self] camera, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                
                let active = camera.isCenterStageActive
                if self.isSmartSelfieCenterStageActive != active {
                    self.isSmartSelfieCenterStageActive = active
                }
            }
        }
    }
    
    private func stopSmartSelfieCenterStage() {
        smartSelfieCenterStageActiveObservation = nil
        smartSelfieCenterStageDeviceUniqueID = nil
        if isSmartSelfieCenterStageActive {
            isSmartSelfieCenterStageActive = false
        }
        
        guard didEnableSmartSelfieCenterStage else { return }
        
        if AVCaptureDevice.centerStageControlMode == .user {
            AVCaptureDevice.centerStageControlMode = .cooperative
        }
        if AVCaptureDevice.isCenterStageEnabled {
            AVCaptureDevice.isCenterStageEnabled = false
        }
        AVCaptureDevice.centerStageControlMode = .user
        didEnableSmartSelfieCenterStage = false
    }
    
    private func startSmartSelfieFramingMonitoring(_ monitor: AVCaptureSmartFramingMonitor) {
        let enabledFramings = enabledSmartSelfieFramings(from: monitor)
        guard !enabledFramings.isEmpty else {
            stopSmartSelfieFramingMonitoring()
            return
        }
        
        if smartSelfieFramingMonitor !== monitor {
            stopSmartSelfieFramingMonitoring()
            smartSelfieFramingMonitor = monitor
            smartSelfieFramingRecommendationObservation = monitor.observe(\.recommendedFraming, options: [.new]) { [weak self] monitor, _ in
                guard let framing = monitor.recommendedFraming,
                      let aspectRatio = CaptureAspectRatioOption(dynamicAspectRatio: framing.aspectRatio) else { return }
                
                let recommendation = SmartSelfieFramingRecommendation(aspectRatio: aspectRatio,
                                                                      zoomFactor: CGFloat(framing.zoomFactor))
                Task { @MainActor [weak self] in
                    self?.handleSmartSelfieFramingRecommendation(recommendation)
                }
            }
        }
        
        monitor.enabledFramings = enabledFramings
        do {
            if !monitor.isMonitoring {
                try monitor.startMonitoring()
            }
            if !isSmartSelfieFramingMonitoring {
                isSmartSelfieFramingMonitoring = true
            }
            if let framing = monitor.recommendedFraming,
               let aspectRatio = CaptureAspectRatioOption(dynamicAspectRatio: framing.aspectRatio) {
                let recommendation = SmartSelfieFramingRecommendation(aspectRatio: aspectRatio,
                                                                      zoomFactor: CGFloat(framing.zoomFactor))
                handleSmartSelfieFramingRecommendation(recommendation)
            }
        } catch {
            isSmartSelfieFramingMonitoring = false
        }
    }
    
    func stopSmartSelfieFramingMonitoring() {
        stopSmartSelfieFramingMonitor()
        stopSmartSelfieCenterStage()
    }
    
    private func stopSmartSelfieFramingMonitor() {
        smartSelfieFramingApplyTask?.cancel()
        smartSelfieFramingApplyTask = nil
        smartSelfieFramingRecommendationObservation = nil
        if let monitor = smartSelfieFramingMonitor {
            monitor.stopMonitoring()
            monitor.enabledFramings = []
        }
        smartSelfieFramingMonitor = nil
        if isSmartSelfieFramingMonitoring {
            isSmartSelfieFramingMonitoring = false
        }
        lastAppliedSmartSelfieFramingRecommendation = nil
    }
    
    private func enabledSmartSelfieFramings(from monitor: AVCaptureSmartFramingMonitor) -> [AVCaptureFraming] {
        monitor.supportedFramings.filter { framing in
            CaptureAspectRatioOption(dynamicAspectRatio: framing.aspectRatio) != nil
        }
    }
    
    private func handleSmartSelfieFramingRecommendation(_ recommendation: SmartSelfieFramingRecommendation) {
        guard canApplySmartSelfieFramingRecommendation,
              availableCaptureAspectRatios.contains(recommendation.aspectRatio) else { return }
        
        let shouldApplyAspectRatio = selectedCaptureAspectRatio != recommendation.aspectRatio
        let shouldApplyZoom = shouldApplySmartSelfieZoom(recommendation.zoomFactor)
        guard shouldApplyAspectRatio || shouldApplyZoom else {
            lastAppliedSmartSelfieFramingRecommendation = recommendation
            return
        }
        guard lastAppliedSmartSelfieFramingRecommendation?.isApproximatelyEqual(to: recommendation) != true else { return }
        
        smartSelfieFramingApplyTask?.cancel()
        smartSelfieFramingApplyTask = Task { @MainActor [weak self] in
            guard let self,
                  self.canApplySmartSelfieFramingRecommendation else { return }
            
            if shouldApplyAspectRatio {
                self.selectCaptureAspectRatio(recommendation.aspectRatio,
                                              zoomFactor: self.captureMode == .raw ? nil : recommendation.zoomFactor)
            }
            
            if self.captureMode != .raw, shouldApplyZoom {
                if shouldApplyAspectRatio {
                    try? await Task.sleep(for: .milliseconds(140))
                }
                guard !Task.isCancelled,
                      self.canContinueSmartSelfieFramingApplication else { return }
                self.applySmartSelfieZoom(recommendation.zoomFactor)
            }
            
            self.lastAppliedSmartSelfieFramingRecommendation = recommendation
        }
    }
    
    private func shouldApplySmartSelfieZoom(_ zoomFactor: CGFloat) -> Bool {
        guard captureMode != .raw,
              let camera = device else { return false }
        
        let targetLens = smartSelfieLens(for: zoomFactor)
        return activeLens != targetLens || abs(camera.videoZoomFactor - zoomFactor) >= 0.04
    }
    
    private func applySmartSelfieZoom(_ zoomFactor: CGFloat) {
        guard captureMode != .raw,
              activeLens.isFront,
              let camera = device else { return }
        
        let cameraUniqueID = camera.uniqueID
        let targetLens = smartSelfieLens(for: zoomFactor)
        if let targetDevice = targetLens.captureDevice(),
           targetDevice.uniqueID != cameraUniqueID {
            switchLens(to: targetLens)
            return
        }
        
        sessionQueue.async { [weak self] in
            guard let self,
                  let camera = Lens.captureDevice(uniqueID: cameraUniqueID) else { return }
            
            let clampedZoom = min(camera.maxAvailableVideoZoomFactor,
                                  max(camera.minAvailableVideoZoomFactor, zoomFactor))
            do {
                try camera.lockForConfiguration()
                camera.videoZoomFactor = clampedZoom
                camera.unlockForConfiguration()
                
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if self.activeLens != targetLens {
                        self.activeLens = targetLens
                    }
                    self.buildAvailableFormats()
                    self.setupCameraControls()
                }
            } catch {
                Task { @MainActor [weak self] in
                    self?.refreshSmartSelfieFraming()
                }
            }
        }
    }
    
    private func smartSelfieLens(for zoomFactor: CGFloat) -> Lens {
        let midpoint = (Lens.frontUltraWide.zoomFactor + Lens.front.zoomFactor) / 2
        let preferredLens: Lens = zoomFactor >= midpoint ? .front : .frontUltraWide
        return preferredLens.captureDevice() == nil ? activeLens : preferredLens
    }
}
