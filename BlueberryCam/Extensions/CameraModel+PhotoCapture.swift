internal import AVFoundation
import Foundation

extension CameraModel {
    // MARK: Bursts
    static let burstIntervalMin = 0.2
    static let burstIntervalMax = 5.0
    static let burstFrameLimitMin = 1
    static let burstFrameLimitMax = 100
    private static let shutterHoldBurstDelay: Duration = .seconds(1)
    
    func changeCapturingState(to new: Bool) {
        isCapturing = new
    }
    
    func toggleBurstMode() {
        guard !isBurstCapturing else {
            stopBurstCapture()
            return
        }
        
        isBurstModeEnabled.toggle()
    }
    
    func handleShutterButton(onCapture: @escaping @MainActor @Sendable () -> Void,
                             onBurstPhotoCaptured: @escaping @MainActor @Sendable () -> Void = {}) {
        if isBurstModeEnabled {
            if isBurstCapturing {
                stopBurstCapture()
            } else {
                guard canCapturePhotoInCurrentState else { return }
                startBurstCapture(onBurstPhotoCaptured: onBurstPhotoCaptured)
            }
            return
        }
        
        guard canUseShutterButton else { return }
        
        capturePhoto(onCapture: onCapture)
    }
    
    func handleShutterPressBegan(onBurstPhotoCaptured: @escaping @MainActor @Sendable () -> Void = {}) {
        guard shutterHoldCaptureTask == nil,
              !isBurstCapturing,
              shouldEnableQuickBurstFromShutterControls,
              canUseShutterButton else { return }
        
        shutterHoldCaptureTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: Self.shutterHoldBurstDelay)
            } catch {
                return
            }
            
            guard let self, !Task.isCancelled else { return }
            self.shutterHoldCaptureTask = nil
            self.startShutterHoldBurst(onBurstPhotoCaptured: onBurstPhotoCaptured)
        }
    }
    
    func handleShutterPressEnded(onCapture: @escaping @MainActor @Sendable () -> Void,
                                 onBurstPhotoCaptured: @escaping @MainActor @Sendable () -> Void = {}) {
        if let shutterHoldCaptureTask {
            shutterHoldCaptureTask.cancel()
            self.shutterHoldCaptureTask = nil
            handleShutterButton(onCapture: onCapture, onBurstPhotoCaptured: onBurstPhotoCaptured)
            return
        }
        
        guard shutterHoldBurstSnapshot != nil else {
            handleShutterButton(onCapture: onCapture, onBurstPhotoCaptured: onBurstPhotoCaptured)
            return
        }
        
        stopShutterHoldBurst()
    }
    
    func handleShutterPressCancelled() {
        shutterHoldCaptureTask?.cancel()
        shutterHoldCaptureTask = nil
        
        if shutterHoldBurstSnapshot != nil {
            stopShutterHoldBurst()
        }
    }
    
    func cancelTimerCountdown() {
        timerCountdownTask?.cancel()
        timerCountdownTask = nil
        isTimerCountingDown = false
        timerCountdownValue = nil
    }
    
    private func startShutterHoldBurst(onBurstPhotoCaptured: @escaping @MainActor @Sendable () -> Void) {
        guard canUseBurstButton,
              !isBurstCapturing,
              shutterHoldBurstSnapshot == nil else { return }
        
        let snapshot = ShutterHoldBurstSnapshot(
            wasBurstModeEnabled: isBurstModeEnabled,
            burstIntervalSeconds: burstIntervalSeconds,
            burstFrameLimit: burstFrameLimit,
            flashMode: flashMode
        )
        shutterHoldBurstSnapshot = snapshot
        
        if !isBurstModeEnabled {
            isBurstModeEnabled = true
            burstIntervalSeconds = nil
            burstFrameLimit = nil
        }
        
        startBurstCapture(onBurstPhotoCaptured: onBurstPhotoCaptured)
        
        if !isBurstCapturing {
            restoreShutterHoldBurstSnapshot()
        }
    }
    
    private func stopShutterHoldBurst() {
        stopBurstCapture()
        restoreShutterHoldBurstSnapshot()
    }
    
    private func restoreShutterHoldBurstSnapshot() {
        guard let snapshot = shutterHoldBurstSnapshot else { return }
        shutterHoldBurstSnapshot = nil
        
        guard !snapshot.wasBurstModeEnabled else { return }
        isBurstModeEnabled = false
        burstIntervalSeconds = snapshot.burstIntervalSeconds
        burstFrameLimit = snapshot.burstFrameLimit
        flashMode = snapshot.flashMode
    }
    
    private func startBurstCapture(onBurstPhotoCaptured: @escaping @MainActor @Sendable () -> Void) {
        guard burstCaptureTask == nil else { return }
        guard canStartBurstCapture else {
            if !isAutoExposure && !manualExposureIsFastEnoughForBurst {
                errorMessage = "Raw Bursts in manual exposure require shutter speed of 1/100s or faster."
                showError = true
            }
            return
        }
        
        flashMode = .off
        cancelTimerCountdown()
        burstCapturedCount = 0
        burstIntervalRemainingSeconds = nil
        burstSessionCounter += 1
        let burstSessionID = burstSessionCounter
        activeBurstSessionID = burstSessionID
        burstSaveStatsBySession[burstSessionID] = BurstSaveStats(captureMode: captureMode, frameLimit: burstFrameLimit)
        isBurstCapturing = true
        
        let startDate = Date()
        burstCaptureTask = Task { @MainActor [weak self] in
            guard let self else { return }
            
            defer {
                let elapsed = Date().timeIntervalSince(startDate)
                let fps = elapsed > 0 ? Double(self.burstCapturedCount) / elapsed : 0
                let summary = "\(self.burstCapturedCount) photos in \(elapsed.formatted(.number.precision(.fractionLength(2))))s (\(fps.formatted(.number.precision(.fractionLength(2)))) fps)"
                self.showBurstFeedback(summary)
                self.isBurstCapturing = false
                self.burstIntervalRemainingSeconds = nil
                self.burstCaptureTask = nil
                self.finishBurstSession(burstSessionID)
            }
            
            await self.waitForSessionQueueIdle()
            await self.settleManualWhiteBalanceBeforeBurst()
            guard !Task.isCancelled, self.isBurstModeEnabled else { return }
            
            while !Task.isCancelled, self.isBurstModeEnabled {
                guard self.canContinueBurstCapture else { break }
                self.exposureDebounceTask?.cancel()
                self._pendingCaptureModeBox.value = self.captureMode
                self._pendingPhotoFilterBox.value = self.selectedPhotoFilter
                self._pendingSaveLocationBox.value = self.saveLocation
                self.updateCaptureOrientation()
                let completionGate = self.burstCaptureCompletionGate
                let processingLimit = self.burstProcessingLimit
                
                await self._burstCaptureTracker.waitForProcessingCapacity(limit: processingLimit)
                guard !Task.isCancelled, self.canContinueBurstCapture else { break }
                guard let settings = await self.buildNextBurstPhotoSettings() else { break }
                self.registerCaptureContext(for: settings, isBurst: true, burstSessionID: burstSessionID)
                let success = await self._burstCaptureTracker.waitForCapture(uniqueID: settings.uniqueID, gate: completionGate) { [photoOutput = self.photoOutput, weak self] in
                    guard let self else { return }
                    photoOutput.capturePhoto(with: settings, delegate: self)
                }
                
                if success {
                    self._captureContextStore.markCaptureCounted(for: settings.uniqueID)
                    self.burstCapturedCount += 1
                    self.recordBurstSensorCapture(sessionID: burstSessionID)
                    onBurstPhotoCaptured()
                }
                
                if let burstFrameLimit = self.burstFrameLimit, self.burstCapturedCount >= burstFrameLimit {
                    self.markBurstSessionFrameLimitReached(burstSessionID)
                    self.stopBurstCapture()
                    break
                }
                
                if let burstIntervalSeconds = self.burstIntervalSeconds {
                    if !(await self.waitForBurstInterval(seconds: burstIntervalSeconds)) {
                        break
                    }
                }
                
                await Task.yield()
            }
        }
    }
    
    func stopBurstCapture() {
        if let activeBurstSessionID {
            markBurstSessionStopping(activeBurstSessionID)
        }
        isBurstCapturing = false
        burstIntervalRemainingSeconds = nil
        burstCaptureTask?.cancel()
    }
    
    private var canStartBurstCapture: Bool {
        guard canCapturePhotoInCurrentState, !isTimerCountingDown else { return false }
        guard isAutoExposure || manualExposureIsFastEnoughForBurst else { return false }
        return true
    }
    
    private var canContinueBurstCapture: Bool {
        canStartBurstCapture && isBurstCapturing
    }
    
    private var manualExposureIsFastEnoughForBurst: Bool {
        guard !isAutoExposure else { return true }
        guard let duration = currentManualExposureDuration else { return false }
        return CMTimeGetSeconds(duration) <= 0.01
    }
    
    private var currentManualExposureDuration: CMTime? {
        if shutterSpeeds.indices.contains(shutterIndex) {
            return shutterSpeeds[shutterIndex]
        } else {
            return nil
        }
    }
    
    private var burstCaptureCompletionGate: BurstCaptureCompletionGate {
        guard shouldPrioritizeBurstSpeed, captureMode != .raw else { return .processing }
        return .sensorCapture
    }
    
    private var burstProcessingLimit: Int {
        guard shouldPrioritizeBurstSpeed, captureMode != .raw else { return 1 }
        return 4
    }
    
    var burstIntervalLabel: String {
        if let burstIntervalSeconds {
            "\(burstIntervalSeconds.formatted(.number.precision(.fractionLength(1))))s"
        } else {
            "A"
        }
    }
    
    var burstFrameLimitLabel: String {
        if let burstFrameLimit {
            "#\(burstFrameLimit)"
        } else {
            "#∞"
        }
    }
    
    var burstCaptureStatusLabel: String {
        if let burstFrameLimit {
            "\(burstCapturedCount)/\(burstFrameLimit) photos captured"
        } else {
            "\(burstCapturedCount) photos captured"
        }
    }
    
    var shouldShowBurstIntervalCountdown: Bool {
        guard isBurstCapturing, let burstIntervalSeconds else { return false }
        return burstIntervalSeconds >= 1.0
    }
    
    var burstIntervalCountdownLabel: String {
        let remaining = max(0, burstIntervalRemainingSeconds ?? 0)
        return "Next photo in \(remaining.formatted(.number.precision(.fractionLength(1))))s"
    }
    
    func setBurstInterval(seconds: Double?) {
        if let seconds {
            burstIntervalSeconds = min(CameraModel.burstIntervalMax, max(CameraModel.burstIntervalMin, seconds))
        } else {
            burstIntervalSeconds = nil
        }
    }
    
    func setBurstFrameLimit(_ limit: Int?) {
        if let limit {
            burstFrameLimit = min(CameraModel.burstFrameLimitMax, max(CameraModel.burstFrameLimitMin, limit))
        } else {
            burstFrameLimit = nil
        }
    }
    
    private func waitForBurstInterval(seconds: Double) async -> Bool {
        guard seconds >= 1.0 else {
            do {
                try await Task.sleep(for: .milliseconds(Int((seconds * 1000).rounded())))
                return !Task.isCancelled && canContinueBurstCapture
            } catch {
                return false
            }
        }
        
        let endDate = Date().addingTimeInterval(seconds)
        burstIntervalRemainingSeconds = seconds
        
        while true {
            let remaining = endDate.timeIntervalSinceNow
            guard remaining > 0 else { break }
            burstIntervalRemainingSeconds = remaining
            
            do {
                let sleepMilliseconds = max(1, min(100, Int((remaining * 1000).rounded())))
                try await Task.sleep(for: .milliseconds(sleepMilliseconds))
            } catch {
                burstIntervalRemainingSeconds = nil
                return false
            }
        }
        
        burstIntervalRemainingSeconds = nil
        return !Task.isCancelled && canContinueBurstCapture
    }
    
    func showBurstFeedback(_ message: String) {
        guard shouldShowBurstFeedback else { return }
        burstFeedbackTask?.cancel()
        burstFeedbackMessage = message
        burstFeedbackTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .seconds(4))
                self?.burstFeedbackMessage = nil
                self?.burstFeedbackTask = nil
            } catch {
                return
            }
        }
    }
    
    private func requestConfettiCannons() {
        guard shouldShowConfettiCannons else { return }
        confettiCannonTrigger += 1
    }
    
    private func registerCaptureContext(for settings: AVCapturePhotoSettings,
                                        isBurst: Bool,
                                        burstSessionID: Int? = nil,
                                        onCapture: (@MainActor @Sendable () -> Void)? = nil) {
        _captureContextStore.set(
            PhotoCaptureContext(
                captureMode: captureMode,
                photoFilter: selectedPhotoFilter,
                saveLocation: saveLocation,
                isBurst: isBurst,
                burstSessionID: burstSessionID,
                isDualCameraCapture: isDualCameraEnabled,
                dualCameraPipPlacement: dualCameraPipPlacement,
                dualCameraPipRotationAngle: dualCameraPipRotationAngle,
                onCapture: onCapture
            ),
            for: settings.uniqueID
        )
    }
    
    private func recordBurstSensorCapture(sessionID: Int) {
        guard var stats = burstSaveStatsBySession[sessionID] else { return }
        stats.sensorCaptureCount += 1
        burstSaveStatsBySession[sessionID] = stats
    }
    
    func recordBurstPhotoDataProduced(context: PhotoCaptureContext) {
        guard let sessionID = context.burstSessionID,
              var stats = burstSaveStatsBySession[sessionID] else { return }
        stats.expectedSaveCount += 1
        burstSaveStatsBySession[sessionID] = stats
        printBurstDrainSummaryIfReady(for: sessionID)
    }
    
    func recordBurstCaptureFailure(context: PhotoCaptureContext) {
        guard let sessionID = context.burstSessionID,
              var stats = burstSaveStatsBySession[sessionID] else { return }
        stats.captureFailureCount += 1
        burstSaveStatsBySession[sessionID] = stats
        printBurstDrainSummaryIfReady(for: sessionID)
    }
    
    func shouldIgnoreBurstCaptureFailure(context: PhotoCaptureContext, uniqueID: Int64) -> Bool {
        guard let sessionID = context.burstSessionID,
              let stats = burstSaveStatsBySession[sessionID],
              !_captureContextStore.hasCountedCapture(for: uniqueID) else {
            return false
        }
        
        return stats.isStopping || stats.sensorCaptureCount > 0
    }
    
    func shouldSuppressGenericCaptureErrorAsBurstTail() -> Bool {
        let now = Date()
        return burstSaveStatsBySession.values.contains { stats in
            if !stats.didPrintDrainSummary {
                return stats.isStopping
            }
            guard let drainSummaryDate = stats.drainSummaryDate else { return false }
            return now.timeIntervalSince(drainSummaryDate) < 5
        }
    }
    
    func recordBurstSaveSuccess(context: PhotoCaptureContext) {
        guard let sessionID = context.burstSessionID,
              var stats = burstSaveStatsBySession[sessionID] else { return }
        stats.savedCount += 1
        burstSaveStatsBySession[sessionID] = stats
        printBurstDrainSummaryIfReady(for: sessionID)
    }
    
    func recordBurstSaveFailure(context: PhotoCaptureContext) {
        guard let sessionID = context.burstSessionID,
              var stats = burstSaveStatsBySession[sessionID] else { return }
        stats.saveFailureCount += 1
        burstSaveStatsBySession[sessionID] = stats
        printBurstDrainSummaryIfReady(for: sessionID)
    }
    
    private func finishBurstSession(_ sessionID: Int) {
        if activeBurstSessionID == sessionID {
            activeBurstSessionID = nil
        }
        guard var stats = burstSaveStatsBySession[sessionID] else { return }
        stats.isCapturing = false
        burstSaveStatsBySession[sessionID] = stats
        printBurstDrainSummaryIfReady(for: sessionID)
    }
    
    private func markBurstSessionStopping(_ sessionID: Int) {
        guard var stats = burstSaveStatsBySession[sessionID] else { return }
        stats.isStopping = true
        burstSaveStatsBySession[sessionID] = stats
    }
    
    private func markBurstSessionFrameLimitReached(_ sessionID: Int) {
        guard var stats = burstSaveStatsBySession[sessionID] else { return }
        stats.didReachFrameLimit = true
        burstSaveStatsBySession[sessionID] = stats
    }
    
    private func printBurstDrainSummaryIfReady(for sessionID: Int) {
        guard var stats = burstSaveStatsBySession[sessionID],
              !stats.isCapturing,
              !stats.didPrintDrainSummary else { return }
        
        let resolvedCaptureCount = stats.expectedSaveCount + stats.captureFailureCount
        let completedSaveCount = stats.savedCount + stats.saveFailureCount
        guard resolvedCaptureCount >= stats.sensorCaptureCount,
              completedSaveCount >= stats.expectedSaveCount else { return }
        
        stats.didPrintDrainSummary = true
        stats.drainSummaryDate = Date()
        burstSaveStatsBySession[sessionID] = stats
        
        if let frameLimit = stats.frameLimit,
           stats.didReachFrameLimit,
           stats.sensorCaptureCount >= frameLimit,
           stats.savedCount >= stats.sensorCaptureCount,
           stats.captureFailureCount == 0,
           stats.saveFailureCount == 0 {
            requestConfettiCannons()
        }
        
    }
    
    func refreshFastCapturePrioritizationForBurstMode() {
        guard photoOutput.isFastCapturePrioritizationSupported else { return }
        photoOutput.isFastCapturePrioritizationEnabled = isBurstModeEnabled && shouldPrioritizeBurstSpeed && captureMode != .raw
    }
    
    // MARK: Capturing
    private func capturePhoto(onCapture: @escaping @MainActor @Sendable () -> Void) {
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
                
                self.performPhotoCapture(onCapture: onCapture, requestsConfettiAfterCapture: true)
            }
            return
        }
        
        performPhotoCapture(onCapture: onCapture)
    }
    
    private func performPhotoCapture(onCapture: @escaping @MainActor @Sendable () -> Void,
                                     requestsConfettiAfterCapture: Bool = false) {
        guard canCapturePhotoInCurrentState else { return }
        
        exposureDebounceTask?.cancel()
        _pendingCaptureModeBox.value = captureMode
        _pendingPhotoFilterBox.value = selectedPhotoFilter
        _pendingSaveLocationBox.value = saveLocation
        
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
                    guard self.canCapturePhotoInCurrentState,
                          let settings = self.buildPhotoSettings() else { return }
                    self.registerCaptureContext(for: settings, isBurst: false, onCapture: onCapture)
                    self.photoOutput.capturePhoto(with: settings, delegate: self)
                    if requestsConfettiAfterCapture {
                        self.requestConfettiCannons()
                    }
                }
            }
            d.unlockForConfiguration()
        } else {
            guard let settings = buildPhotoSettings() else { return }
            registerCaptureContext(for: settings, isBurst: false, onCapture: onCapture)
            photoOutput.capturePhoto(with: settings, delegate: self)
            if requestsConfettiAfterCapture {
                requestConfettiCannons()
            }
        }
    }
    
    private func buildPhotoSettings() -> AVCapturePhotoSettings? {
        let zoomBlocksRAW = (device?.videoZoomFactor ?? 1.0) > 1.0
        guard let dims = captureDimensions() else { return nil }
        
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
                guard let processedMode = preferredProcessedCaptureModeForPhotoSettings() else { return nil }
                return makeProcessedPhotoSettings(for: processedMode, dimensions: dims)
            case .heif:
                return makeProcessedPhotoSettings(for: .heif, dimensions: dims)
            case .jpeg:
                return makeProcessedPhotoSettings(for: .jpeg, dimensions: dims)
        }
    }
    
    private func preferredProcessedCaptureModeForPhotoSettings() -> CaptureMode? {
        preferredProcessedCaptureMode(in: enabledFormats) ??
        preferredProcessedCaptureMode(in: shownAvailableFormats(includeRaw: false))
    }
    
    private func makeProcessedPhotoSettings(for mode: CaptureMode, dimensions: CMVideoDimensions) -> AVCapturePhotoSettings {
        let settings: AVCapturePhotoSettings
        if mode == .heif, photoOutput.availablePhotoCodecTypes.contains(.hevc) {
            settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
        } else {
            settings = AVCapturePhotoSettings()
        }
        settings.maxPhotoDimensions = dimensions
        applyFlashModeIfSupported(to: settings)
        return settings
    }
    
    private func buildNextBurstPhotoSettings() async -> AVCapturePhotoSettings? {
        if !isAutoExposure {
            guard let duration = currentManualExposureDuration,
                  let d = device else { return nil }
            let isoValue = max(d.activeFormat.minISO, min(d.activeFormat.maxISO, iso))
            
            await withCheckedContinuation { continuation in
                try? d.lockForConfiguration()
                d.setExposureModeCustom(duration: duration, iso: isoValue) { _ in
                    continuation.resume()
                }
                d.unlockForConfiguration()
            }
        }
        
        guard let settings = buildPhotoSettings() else { return nil }
        settings.flashMode = .off
        if shouldPrioritizeBurstSpeed, captureMode != .raw {
            settings.photoQualityPrioritization = .speed
        }
        return settings
    }
    
    func updateCaptureOrientation() {
        guard activeCaptureSession.isRunning,
              let device,
              let photoConnection = photoOutput.connection(with: .video),
              photoConnection.isActive else { return }
        
        let coordinator = captureRotationCoordinator(for: device)
        let preferredDegrees = coordinator.videoRotationAngleForHorizonLevelCapture
        let captureDegrees = supportedCaptureRotationAngle(preferredDegrees, for: photoConnection)
        
        if let coordinatorDegrees = captureDegrees {
            photoConnection.videoRotationAngle = coordinatorDegrees
        }
        updateDualCameraPipRotationAngle(from: captureDegrees ?? preferredDegrees, device: device)
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
    
    private func updateDualCameraPipRotationAngle(from captureAngle: CGFloat,
                                                  device: AVCaptureDevice) {
        let mainPreviewAngle = Lens.rotationAngle(for: device, lens: activeLens)
        let delta = normalizedRotationAngle(captureAngle - mainPreviewAngle)
        dualCameraPipRotationAngle = nearestRightAngle(delta)
    }
    
    private func nearestRightAngle(_ degrees: CGFloat) -> CGFloat {
        normalizedRotationAngle((degrees / 90).rounded() * 90)
    }
    
    private func applyFlashModeIfSupported(to settings: AVCapturePhotoSettings) {
        guard !isBurstModeEnabled, isAutoExposure, supportsFlash else {
            settings.flashMode = .off
            return
        }
        if photoOutput.supportedFlashModes.contains(flashMode) {
            settings.flashMode = flashMode
        } else {
            settings.flashMode = .off
        }
    }
    
    private var canCapturePhotoInCurrentState: Bool {
        guard isCaptureSessionRunning,
              activeCaptureSession.isRunning,
              device != nil,
              photoOutput.connection(with: .video)?.isActive == true else { return false }
        
        return !isSwitchingLens &&
        !isConfiguringDualCamera &&
        !isDetachingPreviewForReconfiguration &&
        !isDualCameraPreviewSettling &&
        !shouldShowDualCameraTransitionCurtain
    }
    
    var canUseShutterButton: Bool {
        guard !isTimerCountingDown else { return false }
        return isBurstCapturing || canCapturePhotoInCurrentState
    }
    
    var canUseBurstButton: Bool {
        timerMode == .off && !isTimerCountingDown
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
}
