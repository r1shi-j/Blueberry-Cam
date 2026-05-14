internal import AVFoundation
import Foundation

extension CameraModel {
    func configure() {
        loadSettings()
        toggleLocationGeotag()
        setupSession()
    }
    
    func startSession() {
        let shouldUseDualSession = isDualCameraEnabled
        sessionQueue.async { [weak self] in
            guard let self else { return }
            let captureSession = shouldUseDualSession ? self.dualSession ?? self.session : self.session
            if !captureSession.isRunning {
                captureSession.startRunning()
            }
            let sessionIsRunning = captureSession.isRunning
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isCaptureSessionRunning = sessionIsRunning
                self.updateCaptureOrientation()
                if let device {
                    self.refreshCaptureAspectRatioOptions(for: device)
                    self.refreshSmartSelfieFraming()
                }
            }
        }
    }
    
    func stopSession() {
        cancelTimerCountdown()
        isCaptureSessionRunning = false
        sessionQueue.async {
            if self.session.isRunning {
                self.session.stopRunning()
            }
            if let dualSession = self.dualSession, dualSession.isRunning {
                dualSession.stopRunning()
            }
        }
        stopSmartSelfieFramingMonitoring()
    }
    
    func waitForSessionQueueIdle() async {
        await withCheckedContinuation { continuation in
            sessionQueue.async {
                continuation.resume()
            }
        }
    }
    
    private func setupSession() {
        let metadataTypes = supportedMetadataTypes
        let isMetadataEnabled = recognizeBarcodes && !isTimerCountingDown && !isBurstCapturing
        
        sessionQueue.async { [weak self] in
            guard let self else { return }
            
            self.session.beginConfiguration()
            self.configureSupportedPhotoSessionPreset()
            
            guard let initialCamera = Lens.initialCaptureDevice(),
                  let input = try? AVCaptureDeviceInput(device: initialCamera.device),
                  self.session.canAddInput(input) else {
                self.session.commitConfiguration()
                Task { @MainActor in
                    self.errorMessage = "No available camera was found."
                    self.showError = true
                }
                return
            }
            
            let initialLens = initialCamera.lens
            let cam = initialCamera.device
            self.session.addInput(input)
            
            if self.session.canAddOutput(self.photoOutput) {
                self.session.addOutput(self.photoOutput)
            }
            
            self.videoOutput.alwaysDiscardsLateVideoFrames = true
            self.videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            if self.session.canAddOutput(self.videoOutput) {
                self.session.addOutput(self.videoOutput)
            }
            
            if self.session.canAddOutput(self.metadataOutput) {
                self.session.addOutput(self.metadataOutput)
                self.metadataOutput.setMetadataObjectsDelegate(self, queue: .main)
                let available = self.metadataOutput.availableMetadataObjectTypes
                let toSet = metadataTypes.filter { available.contains($0) }
                self.metadataOutput.metadataObjectTypes = isMetadataEnabled ? toSet : []
            }
            
            self.enableLensSmudgeDetectionIfSupported(on: cam)
            
            // Keep analysis output orientation aligned with preview from first launch.
            let rotationAngle = Lens.rotationAngle(for: cam, lens: initialLens)
            let isMirrored = Lens.isMirrored(cam, lens: initialLens)
            for conn in [self.photoOutput.connection(with: .video),
                         self.videoOutput.connection(with: .video)].compactMap({ $0 }) {
                if conn.isVideoRotationAngleSupported(rotationAngle) {
                    conn.videoRotationAngle = rotationAngle
                }
                conn.isVideoMirrored = isMirrored
            }
            
            self.session.commitConfiguration()
            
            self.videoOutput.setSampleBufferDelegate(self, queue: self.analysisQueue)
            
            if let largest = cam.activeFormat.supportedMaxPhotoDimensions.max(by: {
                Int($0.width) * Int($0.height) < Int($1.width) * Int($1.height)
            }) {
                self.photoOutput.maxPhotoDimensions = largest
            }
            
            Task { @MainActor in
                if self.session.supportsControls {
                    self.session.setControlsDelegate(self, queue: DispatchQueue.main)
                }
                
                // Match initial flip to lens
                self.activeLens = initialLens
                self.flipRotation = initialLens.isFront ? 180 : 0
                
                // Restoration of hardware defaults and state
                self.device = cam
                self.captureRotationCoordinator = AVCaptureDevice.RotationCoordinator(device: cam, previewLayer: nil)
                self.refreshCaptureAspectRatioOptions(for: cam)
                self.configureLensSmudgeDetection(for: cam)
                self.configureSubjectAreaMonitoring(for: cam)
                self.buildAvailableFormats()
                self.updateDeviceRanges()
                self.normalizeFlashModeForCurrentDevice()
                self.enforceExposureModeConstraints()
                self.setupCameraControls()
                self.refreshSmartSelfieFraming()
                self.startSession()
            }
        }
    }
    
    private func loadSettings() {
        let defaults = UserDefaults.standard
        
        if let location = defaults.string(forKey: "saveLocation"),
           let saveLocation = SaveLocation(rawValue: location) {
            self.saveLocation = saveLocation
        }
        self.refreshFileSaveLocationDisplay()
        self.validateFilesSaveLocation()
        
        if let storedFormats = defaults.stringArray(forKey: "shownCaptureFormats") {
            setShownCaptureFormats(storedFormats.compactMap { CaptureMode(rawValue: $0) })
        } else {
            setShownCaptureFormats(CaptureMode.defaultShownFormats)
        }
        
        if let format = defaults.string(forKey: "defaultFileFormat"), let mode = CaptureMode(rawValue: format) {
            self.defaultFileFormat = mode
            // Prime the active mode immediately so the UI reflects the saved state during launch.
            self.captureMode = mode
        }
        if !shownCaptureFormats.contains(defaultFileFormat) {
            defaultFileFormat = .raw
        }
        
        if let res = defaults.string(forKey: "defaultResolution"), let rPref = ResolutionPreference(rawValue: res) {
            self.defaultResolution = rPref
        }
        
        if let filter = defaults.string(forKey: "defaultPhotoFilter"),
           let defaultPhotoFilter = PhotoFilter(rawValue: filter) {
            self.defaultPhotoFilter = defaultPhotoFilter
        }
        self.selectedPhotoFilter = defaultPhotoFilter
        
        if let histSmall = defaults.string(forKey: "defaultHistogramSmall"), let hMode = HistogramMode(rawValue: histSmall) {
            self.defaultHistogramSmall = hMode
        }
        
        if let histLarge = defaults.string(forKey: "defaultHistogramLarge"), let hMode = HistogramMode(rawValue: histLarge) {
            self.defaultHistogramLarge = hMode
        }
        
        self.shouldGeotagLocation = defaults.object(forKey: "shouldGeotagLocation") as? Bool ?? false
        self.shouldPrioritizeBurstSpeed = defaults.object(forKey: "shouldPrioritizeBurstSpeed") as? Bool ?? true
        self.shouldShowBurstFeedback = defaults.object(forKey: "shouldShowBurstFeedback") as? Bool ?? false
        self.detailedCountdownTimer = defaults.object(forKey: "detailedCountdownTimer") as? Bool ?? false
        self.shouldHideUIWhileCountingDown = defaults.object(forKey: "shouldHideUIWhileCountingDown") as? Bool ?? true
        self.shouldShowConfettiCannons = defaults.object(forKey: "shouldShowConfettiCannons") as? Bool ?? true
        self.shouldShowGrid = defaults.object(forKey: "shouldShowGrid") as? Bool ?? false
        self.shouldShowLevel = defaults.object(forKey: "shouldShowLevel") as? Bool ?? false
        self.recognizeBarcodes = defaults.object(forKey: "recognizeBarcodes") as? Bool ?? false
        self.isSmartSelfieFramingEnabled = defaults.object(forKey: "isSmartSelfieFramingEnabled") as? Bool ?? false
    }
    
    nonisolated func configureSupportedPhotoSessionPreset() {
        configureSupportedPhotoSessionPreset(for: session)
    }
    
    nonisolated func configureSupportedPhotoSessionPreset(for captureSession: AVCaptureSession) {
        if captureSession.canSetSessionPreset(.photo) {
            captureSession.sessionPreset = .photo
        } else if captureSession.canSetSessionPreset(.inputPriority) {
            captureSession.sessionPreset = .inputPriority
        }
    }
    
    func resetToDefaults() {
        let defaults = UserDefaults.standard
        [
            "saveLocation",
            "shownCaptureFormats",
            "defaultFileFormat",
            "defaultResolution",
            "defaultPhotoFilter",
            "defaultHistogramSmall",
            "defaultHistogramLarge",
            "shouldGeotagLocation",
            "shouldPrioritizeBurstSpeed",
            "shouldShowBurstFeedback",
            "detailedCountdownTimer",
            "shouldHideUIWhileCountingDown",
            "shouldShowConfettiCannons",
            "shouldShowGrid",
            "shouldShowLevel",
            "recognizeBarcodes",
            "isSmartSelfieFramingEnabled"
        ].forEach(defaults.removeObject)
        
        setShownCaptureFormats(CaptureMode.defaultShownFormats)
        defaultFileFormat = .raw
        defaultResolution = .max
        defaultPhotoFilter = .off
        saveLocation = .photos
        resetFileSaveLocationToDefault()
        defaultHistogramSmall = .none
        defaultHistogramLarge = .none
        shouldGeotagLocation = false
        recognizeBarcodes = false
        shouldShowGrid = false
        shouldShowLevel = false
        detailedCountdownTimer = false
        shouldHideUIWhileCountingDown = true
        shouldPrioritizeBurstSpeed = true
        shouldShowBurstFeedback = false
        shouldShowConfettiCannons = true
        isSmartSelfieFramingEnabled = false
    }
}
