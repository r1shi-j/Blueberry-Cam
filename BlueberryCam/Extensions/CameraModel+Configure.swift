internal import AVFoundation
import Foundation

extension CameraModel {
    func configure() {
        loadSettings()
        toggleLocationGeotag()
        
        Task.detached(priority: .userInitiated) { @MainActor in
            self.setupSession()
            self.startSession()
        }
    }
    
    func startSession() {
        sessionQueue.async {
            if !self.session.isRunning {
                self.session.startRunning()
            }
        }
    }
    
    func stopSession() {
        sessionQueue.async {
            if self.session.isRunning {
                self.session.stopRunning()
            }
        }
    }
    
    func waitForSessionQueueIdle() async {
        await withCheckedContinuation { continuation in
            sessionQueue.async {
                continuation.resume()
            }
        }
    }
    
    private func setupSession() {
        session.beginConfiguration()
        session.sessionPreset = .photo
        
        guard let cam = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: cam),
              session.canAddInput(input) else {
            session.commitConfiguration()
            return
        }
        session.addInput(input)
        
        session.setControlsDelegate(self, queue: DispatchQueue.main)
        setupCameraControls()
        
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
        }
        
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
        }
        
        if session.canAddOutput(metadataOutput) {
            session.addOutput(metadataOutput)
            metadataOutput.setMetadataObjectsDelegate(self, queue: .main)
            let available = metadataOutput.availableMetadataObjectTypes
            let toSet = supportedMetadataTypes.filter { available.contains($0) }
            if !toSet.isEmpty {
                metadataOutput.metadataObjectTypes = toSet
            }
        }
        
        enableLensSmudgeDetectionIfSupported(on: cam)
        configureSubjectAreaMonitoring(for: cam)
        
        // Keep analysis output orientation aligned with preview from first launch.
        let isFront = activeLens.isFront
        let rotationAngle: CGFloat = isFront ? 0 : 90
        for conn in [photoOutput.connection(with: .video),
                     videoOutput.connection(with: .video)].compactMap({ $0 }) {
            if conn.isVideoRotationAngleSupported(rotationAngle) {
                conn.videoRotationAngle = rotationAngle
            }
            conn.isVideoMirrored = isFront
        }
        
        session.commitConfiguration()
        
        // Match initial flip to lens
        self.flipRotation = activeLens.isFront ? 180 : 0
        
        let analysisQueue = DispatchQueue(label: "\(BundleIDs.appID).analysisQueue")
        videoOutput.setSampleBufferDelegate(self, queue: analysisQueue)
        
        // Restoration of hardware defaults and state
        self.device = cam
        self.configureLensSmudgeDetection(for: cam)
        if let largest = cam.activeFormat.supportedMaxPhotoDimensions.max(by: {
            Int($0.width) * Int($0.height) < Int($1.width) * Int($1.height)
        }) {
            self.photoOutput.maxPhotoDimensions = largest
        }
        self.buildAvailableFormats()
        self.updateDeviceRanges()
        self.normalizeFlashModeForCurrentDevice()
        self.enforceExposureModeConstraints()
    }
    
    private func loadSettings() {
        let defaults = UserDefaults.standard
        
        if let format = defaults.string(forKey: "defaultFileFormat"), let mode = CaptureMode(rawValue: format) {
            self.defaultFileFormat = mode
            // Prime the active mode immediately so the UI reflects the saved state during launch.
            self.captureMode = mode
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
        self.recognizeBarcodes = defaults.object(forKey: "recognizeBarcodes") as? Bool ?? false
        self.shouldShowGrid = defaults.object(forKey: "shouldShowGrid") as? Bool ?? false
        self.shouldShowLevel = defaults.object(forKey: "shouldShowLevel") as? Bool ?? false
        self.detailedCountdownTimer = defaults.object(forKey: "detailedCountdownTimer") as? Bool ?? false
        self.shouldHideUIWhileCountingDown = defaults.object(forKey: "shouldHideUIWhileCountingDown") as? Bool ?? true
        self.shouldPrioritizeBurstSpeed = defaults.object(forKey: "shouldPrioritizeBurstSpeed") as? Bool ?? true
        self.shouldShowBurstFeedback = defaults.object(forKey: "shouldShowBurstFeedback") as? Bool ?? false
        self.shouldShowConfettiCannons = defaults.object(forKey: "shouldShowConfettiCannons") as? Bool ?? true
    }
    
    func resetToDefaults() {
        let defaults = UserDefaults.standard
        [
            "defaultFileFormat",
            "defaultResolution",
            "defaultPhotoFilter",
            "defaultHistogramSmall",
            "defaultHistogramLarge",
            "shouldGeotagLocation",
            "recognizeBarcodes",
            "shouldShowGrid",
            "shouldShowLevel",
            "detailedCountdownTimer",
            "shouldHideUIWhileCountingDown",
            "shouldPrioritizeBurstSpeed",
            "shouldShowBurstFeedback",
            "shouldShowConfettiCannons"
        ].forEach(defaults.removeObject)
        
        defaultFileFormat = .raw
        defaultResolution = .max
        defaultPhotoFilter = .off
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
    }
}
