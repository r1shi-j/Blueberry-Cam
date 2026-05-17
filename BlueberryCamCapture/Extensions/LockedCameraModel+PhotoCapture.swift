internal import AVFoundation
import CoreMotion
import Foundation

extension LockedCameraModel {
    func changeCapturingState(to new: Bool) {
        isCapturing = new
    }
    
    func startCaptureOrientationUpdates() {
        guard captureMotionManager.isDeviceMotionAvailable else { return }
        guard !captureMotionManager.isDeviceMotionActive else { return }
        
        captureMotionManager.deviceMotionUpdateInterval = 1.0 / 30.0
        captureMotionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let motion else { return }
            
            let gravity = motion.gravity
            Task { @MainActor [weak self] in
                self?.updateCaptureRotationOffset(
                    gravityX: gravity.x,
                    gravityY: gravity.y,
                    gravityZ: gravity.z
                )
            }
        }
    }
    
    func stopCaptureOrientationUpdates() {
        guard captureMotionManager.isDeviceMotionActive else { return }
        
        captureMotionManager.stopDeviceMotionUpdates()
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
                    guard self.cameraModelCanCapture, let settings = self.buildPhotoSettings(for: requestedCaptureMode) else { return }
                    self.processingPhotoCount += 1
                    self.registerCaptureContext(for: settings, captureMode: requestedCaptureMode, onCapture: onCapture)
                    self.photoOutput.capturePhoto(with: settings, delegate: self)
                }
            }
            d.unlockForConfiguration()
        } else {
            guard let settings = buildPhotoSettings(for: requestedCaptureMode) else { return }
            processingPhotoCount += 1
            registerCaptureContext(for: settings, captureMode: requestedCaptureMode, onCapture: onCapture)
            photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }
    
    private var cameraModelCanCapture: Bool {
        hasPhotosAccess && session.isRunning && device != nil && !isSwitchingLens
    }
    
    private func preferredProcessedCaptureModeForPhotoSettings() -> CaptureMode? {
        preferredProcessedCaptureMode(in: enabledFormats) ??
        preferredProcessedCaptureMode(in: shownAvailableFormats(includeRaw: false))
    }
    
    private func buildPhotoSettings(for captureMode: CaptureMode) -> AVCapturePhotoSettings? {
        let zoomBlocksRAW = (device?.videoZoomFactor ?? 1.0) > 1.0
        guard let dims = captureDimensions() else { return nil }
        
        switch captureMode {
            case .raw:
                if !zoomBlocksRAW,
                   let settings = makeRawPhotoSettings(preferAppleProRAW: false, dimensions: dims) {
                    return settings
                }
                guard let processedMode = preferredProcessedCaptureModeForPhotoSettings() else { return nil }
                return makeProcessedPhotoSettings(for: processedMode, dimensions: dims)
            case .proRaw:
                if let settings = makeRawPhotoSettings(preferAppleProRAW: true, dimensions: dims) {
                    return settings
                }
                guard let processedMode = preferredProcessedCaptureModeForPhotoSettings() else { return nil }
                return makeProcessedPhotoSettings(for: processedMode, dimensions: dims)
            case .heif:
                return makeProcessedPhotoSettings(for: .heif, dimensions: dims)
            case .jpeg:
                return makeProcessedPhotoSettings(for: .jpeg, dimensions: dims)
        }
    }
    
    private func makeRawPhotoSettings(preferAppleProRAW: Bool, dimensions: CMVideoDimensions) -> AVCapturePhotoSettings? {
        let rawPixelFormatTypes = photoOutput.availableRawPhotoPixelFormatTypes
        let predicate = preferAppleProRAW ? AVCapturePhotoOutput.isAppleProRAWPixelFormat : AVCapturePhotoOutput.isBayerRAWPixelFormat
        guard let format = rawPixelFormatTypes.first(where: predicate) else { return nil }
        
        let settings = AVCapturePhotoSettings(rawPixelFormatType: format)
        settings.maxPhotoDimensions = dimensions
        if AVCapturePhotoOutput.isBayerRAWPixelFormat(format) {
            settings.photoQualityPrioritization = .speed
        } else {
            settings.photoQualityPrioritization = .quality
            applyProRawFileFormat(to: settings, rawPixelFormatType: format)
        }
        applyFlashModeIfSupported(to: settings)
        return settings
    }
    
    private func applyProRawFileFormat(to settings: AVCapturePhotoSettings, rawPixelFormatType: OSType) {
        guard photoOutput.availableRawPhotoFileTypes.contains(.dng),
              photoOutput.availableRawPhotoCodecTypes.contains(proRawFileFormat.codecType) else { return }
        
        let supportedCodecs = photoOutput.supportedRawPhotoCodecTypes(
            forRawPhotoPixelFormatType: rawPixelFormatType,
            fileType: .dng
        )
        guard supportedCodecs.contains(proRawFileFormat.codecType) else { return }
        
        settings.rawFileFormat = proRawFileFormat.rawFileFormat()
    }
    
    private func makeProcessedPhotoSettings(for mode: CaptureMode, dimensions: CMVideoDimensions) -> AVCapturePhotoSettings {
        let settings: AVCapturePhotoSettings
        if mode == .heif, photoOutput.availablePhotoCodecTypes.contains(.hevc) {
            settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
        } else {
            settings = AVCapturePhotoSettings()
        }
        settings.maxPhotoDimensions = dimensions
        settings.photoQualityPrioritization = .quality
        applyFlashModeIfSupported(to: settings)
        return settings
    }
    
    func updateCaptureOrientation() {
        guard session.isRunning,
              let device,
              let photoConnection = photoOutput.connection(with: .video),
              photoConnection.isActive else { return }
        
        let coordinator = captureRotationCoordinator(for: device)
        let preferredDegrees = coordinator.videoRotationAngleForHorizonLevelCapture
        let sensorBaselineDegrees = Lens.rotationAngle(for: device, lens: activeLens)
        updateCaptureRotationOffsetFromLatestMotion()
        let requestedDegrees = captureRotationAngle(
            preferredDegrees: preferredDegrees,
            sensorBaselineDegrees: sensorBaselineDegrees,
        )
        let requestedSupportedDegrees = supportedCaptureRotationAngle(requestedDegrees, for: photoConnection)
        let preferredSupportedDegrees = supportedCaptureRotationAngle(preferredDegrees, for: photoConnection)
        
        if let captureDegrees = requestedSupportedDegrees ?? preferredSupportedDegrees {
            photoConnection.videoRotationAngle = captureDegrees
        }
        if photoConnection.isVideoMirroringSupported {
            photoConnection.isVideoMirrored = Lens.isMirrored(device, lens: activeLens)
        }
    }
    
    private func captureRotationCoordinator(for device: AVCaptureDevice) -> AVCaptureDevice.RotationCoordinator {
        if let captureRotationCoordinator,
           captureRotationCoordinator.device?.uniqueID == device.uniqueID {
            return captureRotationCoordinator
        }
        
        let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil)
        captureRotationCoordinator = coordinator
        return coordinator
    }
    
    private func captureRotationAngle(preferredDegrees: CGFloat,
                                      sensorBaselineDegrees: CGFloat) -> CGFloat {
        if let captureMotionRotationOffset {
            return sensorBaselineDegrees + captureMotionRotationOffset
        }
        
        if normalizedRotationAngle(preferredDegrees) == 0,
           normalizedRotationAngle(sensorBaselineDegrees) != 0 {
            return sensorBaselineDegrees
        }
        
        return preferredDegrees
    }
    
    private func updateCaptureRotationOffsetFromLatestMotion() {
        guard let motion = captureMotionManager.deviceMotion else { return }
        
        updateCaptureRotationOffset(
            gravityX: motion.gravity.x,
            gravityY: motion.gravity.y,
            gravityZ: motion.gravity.z
        )
    }
    
    private func updateCaptureRotationOffset(gravityX: Double,
                                             gravityY: Double,
                                             gravityZ: Double) {
        let flatThreshold = 0.85
        guard abs(gravityZ) < flatThreshold else { return }
        
        let rawAngle = atan2(gravityX, -gravityY) * 180.0 / .pi
        captureMotionRotationOffset = nearestRightAngle(CGFloat(rawAngle))
    }
    
    private func supportedCaptureRotationAngle(_ degrees: CGFloat,
                                               for connection: AVCaptureConnection) -> CGFloat? {
        let normalized = normalizedRotationAngle(degrees)
        if connection.isVideoRotationAngleSupported(normalized) {
            return normalized
        }
        
        let nearestRightAngle = normalizedRotationAngle((normalized / 90).rounded() * 90)
        if connection.isVideoRotationAngleSupported(nearestRightAngle) {
            return nearestRightAngle
        }
        
        return nil
    }
    
    private func normalizedRotationAngle(_ degrees: CGFloat) -> CGFloat {
        let remainder = degrees.truncatingRemainder(dividingBy: 360)
        return remainder >= 0 ? remainder : remainder + 360
    }
    
    private func nearestRightAngle(_ degrees: CGFloat) -> CGFloat {
        normalizedRotationAngle((degrees / 90).rounded() * 90)
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
    
    private func captureDimensions() -> CMVideoDimensions? {
        guard let d = device else { return nil }
        let outputMax = photoOutput.maxPhotoDimensions
        let supportedDimensions = d.activeFormat.supportedMaxPhotoDimensions
            .filter { $0.width <= outputMax.width && $0.height <= outputMax.height }
        
        if let selected = selectedResolution?.dimensions,
           supportedDimensions.contains(where: { $0.width == selected.width && $0.height == selected.height }) {
            return selected
        }
        
        return supportedDimensions.max {
            Int($0.width) * Int($0.height) < Int($1.width) * Int($1.height)
        }
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
