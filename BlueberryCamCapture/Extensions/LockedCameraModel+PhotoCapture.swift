internal import AVFoundation
import Foundation

extension LockedCameraModel {
    func changeCapturingState(to new: Bool) {
        isCapturing = new
    }
    
    func cancelTimerCountdown() {
        timerCountdownTask?.cancel()
        timerCountdownTask = nil
        isTimerCountingDown = false
        timerCountdownValue = nil
    }
    
    // MARK: Capturing
    func capturePhoto(onCapture: @escaping @MainActor @Sendable () -> Void) {
        guard timerCountdownTask == nil else { return }
        
        if let totalSeconds = timerMode.seconds {
            isTimerCountingDown = true
            timerCountdownValue = Double(totalSeconds)
            onTimerCountdownSecond?()
            timerCountdownTask = Task { @MainActor [weak self] in
                guard let self else { return }
                let usesDetailedCountdown = self.detailedCountdownTimer
                
                defer {
                    self.isTimerCountingDown = false
                    self.timerCountdownValue = nil
                    self.timerCountdownTask = nil
                }
                
                let endDate = Date().addingTimeInterval(TimeInterval(totalSeconds))
                let updateInterval: Duration = usesDetailedCountdown ? .milliseconds(16) : .milliseconds(100)
                var lastHapticSecond = totalSeconds
                
                while true {
                    let remaining = endDate.timeIntervalSinceNow
                    guard remaining > 0 else { break }
                    
                    let displaySecond = max(0, Int(ceil(remaining)))
                    if displaySecond > 0, displaySecond < lastHapticSecond {
                        lastHapticSecond = displaySecond
                        self.onTimerCountdownSecond?()
                    }
                    
                    self.timerCountdownValue = remaining
                    do {
                        try await Task.sleep(for: updateInterval)
                    } catch {
                        return
                    }
                }
                
                self.performPhotoCapture(onCapture: onCapture)
            }
            return
        }
        
        performPhotoCapture(onCapture: onCapture)
    }
    
    private func performPhotoCapture(onCapture: @escaping @MainActor @Sendable () -> Void) {
        guard cameraModelCanCapture else { return }
        
        exposureDebounceTask?.cancel()
        let requestedCaptureMode = captureMode
        _pendingCaptureModeBox.value = requestedCaptureMode
        // Update orientation based on current physical position
        updateCaptureOrientation()
        
        // For manual exposure, wait for hardware to confirm values are applied before firing.
        // setExposureModeCustom is async — the completionHandler fires once the sensor has
        // actually settled on the requested ISO/shutter, then we fire the shutter.
        if !isAutoExposure, let d = device {
            let duration: CMTime
            if shutterSpeeds.indices.contains(shutterIndex) {
                duration = shutterSpeeds[shutterIndex]
            } else {
                return  // no valid shutter duration available, skip
            }
            let isoValue = max(d.activeFormat.minISO, min(d.activeFormat.maxISO, iso))
            try? d.lockForConfiguration()
            d.setExposureModeCustom(duration: duration, iso: isoValue) { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in
                    guard self.cameraModelCanCapture else { return }
                    
                    let settings = self.buildPhotoSettings(for: requestedCaptureMode)
                    self.registerCaptureContext(for: settings, captureMode: requestedCaptureMode, onCapture: onCapture)
                    self.photoOutput.capturePhoto(with: settings, delegate: self)
                }
            }
            d.unlockForConfiguration()
        } else {
            let settings = buildPhotoSettings(for: requestedCaptureMode)
            registerCaptureContext(for: settings, captureMode: requestedCaptureMode, onCapture: onCapture)
            photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }
    
    private var cameraModelCanCapture: Bool {
        hasPhotosAccess && session.isRunning && device != nil && !isSwitchingLens
    }
    
    private func buildPhotoSettings(for captureMode: CaptureMode) -> AVCapturePhotoSettings {
        let zoomBlocksRAW = (device?.videoZoomFactor ?? 1.0) > 1.0
        let dims = captureDimensions()
        
        switch captureMode {
            case .raw:
                if !zoomBlocksRAW,
                   let fmt = photoOutput.availableRawPhotoPixelFormatTypes.first(where: {
                       !AVCapturePhotoOutput.isAppleProRAWPixelFormat($0)
                   }) ?? photoOutput.availableRawPhotoPixelFormatTypes.first {
                    let s = AVCapturePhotoSettings(rawPixelFormatType: fmt)
                    s.maxPhotoDimensions = dims
                    applyFlashModeIfSupported(to: s)
                    return s
                }
                fallthrough
            case .heif:
                if photoOutput.availablePhotoCodecTypes.contains(.hevc) {
                    let s = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
                    s.maxPhotoDimensions = dims
                    applyFlashModeIfSupported(to: s)
                    return s
                }
                fallthrough
            case .jpeg:
                let s = AVCapturePhotoSettings()
                s.maxPhotoDimensions = dims
                applyFlashModeIfSupported(to: s)
                return s
        }
    }
    
    private func updateCaptureOrientation() {
        guard session.isRunning, let photoConnection = photoOutput.connection(with: .video), photoConnection.isActive else { return }
        
        let (gx, gy, gz) = lastGravity
        let isFront = activeLens.isFront
        
        // Determine rotation based on gravity
        let degrees: CGFloat
        
        if abs(gz) > 0.75 {
            // Device is flat - keep current
            return
        }
        
        if abs(gy) > abs(gx) {
            // Portrait orientation
            if gy < 0 {
                // Normal portrait
                degrees = isFront ? 0 : 90
            } else {
                // Upside down portrait
                degrees = isFront ? 180 : 270
            }
        } else {
            // Landscape orientation
            if gx > 0 {
                // Landscape right (home button on right)
                degrees = isFront ? 270 : 180
            } else {
                // Landscape left (home button on left)
                degrees = isFront ? 90 : 0
            }
        }
        
        // Update the photo connection rotation
        photoConnection.videoRotationAngle = degrees
    }
    
    private func applyFlashModeIfSupported(to settings: AVCapturePhotoSettings) {
        guard isAutoExposure, supportsFlash else {
            settings.flashMode = .off
            return
        }
        if photoOutput.supportedFlashModes.contains(flashMode) {
            settings.flashMode = flashMode
        } else {
            settings.flashMode = .off
        }
    }
    
    private func captureDimensions() -> CMVideoDimensions {
        if let selected = selectedResolution { return selected.dimensions }
        guard let d = device else { return photoOutput.maxPhotoDimensions }
        let outputMax = photoOutput.maxPhotoDimensions
        return d.activeFormat.supportedMaxPhotoDimensions
            .filter { $0.width <= outputMax.width && $0.height <= outputMax.height }
            .max { Int($0.width) * Int($0.height) < Int($1.width) * Int($1.height) }
        ?? outputMax
    }
    
    private func registerCaptureContext(for settings: AVCapturePhotoSettings,
                                        captureMode: CaptureMode,
                                        onCapture: (@MainActor @Sendable () -> Void)? = nil) {
        _captureContextStore.set(
            LockedPhotoCaptureContext(
                captureMode: captureMode,
                onCapture: onCapture
            ),
            for: settings.uniqueID
        )
    }
}
