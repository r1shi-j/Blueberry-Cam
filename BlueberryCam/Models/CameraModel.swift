internal import AVFoundation
internal import CoreLocation
internal import Photos
import UIKit

@MainActor @Observable
class CameraModel: NSObject, AVCaptureSessionControlsDelegate {
    // MARK: - Session
    nonisolated let session = AVCaptureSession()
    var device: AVCaptureDevice?
    nonisolated let photoOutput = AVCapturePhotoOutput()
    nonisolated let videoOutput = AVCaptureVideoDataOutput()
    nonisolated let depthOutput = AVCaptureDepthDataOutput()
    private var synchronizer: AVCaptureDataOutputSynchronizer?
    nonisolated let sessionQueue = DispatchQueue(label: "\(BundleIDs.appID).sessionQueue")
    nonisolated let frameCounter = FrameCounter()
    let _pendingCaptureModeBox = CaptureModeBox()
    let _pendingPhotoFilterBox = PhotoFilterBox()
    let _captureContextStore = PhotoCaptureContextStore()
    let _burstCaptureTracker = BurstCaptureTracker()
    
    // MARK: - Barcode Detection
    nonisolated let metadataOutput = AVCaptureMetadataOutput()
    var detectedCodeURL: URL? = nil
    var detectedCodeString: String? = nil
    var ignoredCodes: [String: Date] = [:]
    var barcodeResetTask: Task<Void, Never>?
    var supportedMetadataTypes: [AVMetadataObject.ObjectType] {
        [
            .qr, .microQR,
            .ean13, .ean8, .upce,
            .code128, .code39, .code39Mod43, .code93,
            .itf14, .interleaved2of5,
            .dataMatrix, .pdf417, .microPDF417, .aztec,
            .codabar, .gs1DataBar, .gs1DataBarExpanded, .gs1DataBarLimited
        ]
    }
    
    // MARK: - Lens cleaning detection
    var lensSmudgeDetectionStatus: AVCaptureCameraLensSmudgeDetectionStatus = .disabled
    var shouldShowLensCleaningHint = false
    @ObservationIgnored
    private var didDismissLensCleaningHint = false
    @ObservationIgnored
    private var lensSmudgeStatusObservation: NSKeyValueObservation?
    
    // MARK: - Camera Control (iOS 18)
    var cleanUIControl: AVCaptureIndexPicker?
    var filterControl: AVCaptureIndexPicker?
    var lensControl: AVCaptureIndexPicker?
    var evControl: AVCaptureSlider?
    var isoControl: AVCaptureSlider?
    var ssControl: AVCaptureIndexPicker?
    var focusControl: AVCaptureSlider?
    var wbControl: AVCaptureSlider?
    /// Prevents Camera Control action callbacks from overwriting properties when we set ctrl.value programmatically
    var isUpdatingHardwareControl = false
    
    // MARK: - Defaults (for settings)
    var defaultFileFormat: CaptureMode = .raw {
        didSet {
            UserDefaults.standard.set(defaultFileFormat.rawValue, forKey: "defaultFileFormat")
            // Always try to apply the preference to the active mode immediately.
            // Enforcement (fallbacks) will be handled by buildAvailableFormats() once hardware is ready.
            if captureMode != defaultFileFormat {
                captureMode = defaultFileFormat
            }
        }
    }
    var defaultResolution: ResolutionPreference = .max {
        didSet {
            UserDefaults.standard.set(defaultResolution.rawValue, forKey: "defaultResolution")
            // Force apply the new preference immediately to the current selection
            if !enabledResolutions.isEmpty {
                selectedResolution = defaultResolution == .max ? enabledResolutions.last : enabledResolutions.first
            }
        }
    }
    var defaultPhotoFilter: PhotoFilter = .off {
        didSet {
            UserDefaults.standard.set(defaultPhotoFilter.rawValue, forKey: "defaultPhotoFilter")
        }
    }
    var defaultHistogramSmall: HistogramMode = .none {
        didSet {
            UserDefaults.standard.set(defaultHistogramSmall.rawValue, forKey: "defaultHistogramSmall")
            histogramModeSmall = defaultHistogramSmall
        }
    }
    var defaultHistogramLarge: HistogramMode = .none {
        didSet {
            UserDefaults.standard.set(defaultHistogramLarge.rawValue, forKey: "defaultHistogramLarge")
            histogramModeLarge = defaultHistogramLarge
        }
    }
    var shouldGeotagLocation = false {
        didSet {
            UserDefaults.standard.set(shouldGeotagLocation, forKey: "shouldGeotagLocation")
            toggleLocationGeotag()
        }
    }
    var recognizeBarcodes: Bool = false {
        didSet {
            UserDefaults.standard.set(recognizeBarcodes, forKey: "recognizeBarcodes")
            updateMetadataOutputStatus()
        }
    }
    var shouldShowGrid = false {
        didSet { UserDefaults.standard.set(shouldShowGrid, forKey: "shouldShowGrid") }
    }
    var shouldShowLevel = false {
        didSet { UserDefaults.standard.set(shouldShowLevel, forKey: "shouldShowLevel") }
    }
    var detailedCountdownTimer = false {
        didSet { UserDefaults.standard.set(detailedCountdownTimer, forKey: "detailedCountdownTimer") }
    }
    var shouldHideUIWhileCountingDown = true {
        didSet {
            UserDefaults.standard.set(shouldHideUIWhileCountingDown, forKey: "shouldHideUIWhileCountingDown")
            updateAnalysisPauseState()
        }
    }
    var shouldPrioritizeBurstSpeed = true {
        didSet {
            UserDefaults.standard.set(shouldPrioritizeBurstSpeed, forKey: "shouldPrioritizeBurstSpeed")
            refreshFastCapturePrioritizationForBurstMode()
        }
    }
    var shouldShowBurstFeedback = false {
        didSet { UserDefaults.standard.set(shouldShowBurstFeedback, forKey: "shouldShowBurstFeedback") }
    }
    var shouldShowConfettiCannons = true {
        didSet { UserDefaults.standard.set(shouldShowConfettiCannons, forKey: "shouldShowConfettiCannons") }
    }
    
    // MARK: - Capture format
    var captureMode: CaptureMode = .raw {
        didSet {
            if oldValue != captureMode {
                buildAvailableFormats()
                refreshFastCapturePrioritizationForBurstMode()
                updateCameraControlsMode()
            }
        }
    }
    private(set) var availableFormats: [CaptureMode] = []
    private(set) var enabledFormats: [CaptureMode] = []
    private(set) var availableResolutions: [ResolutionOption] = []
    private(set) var enabledResolutions: [ResolutionOption] = []
    var selectedResolution: ResolutionOption? = nil
    var selectedPhotoFilter: PhotoFilter = .off {
        didSet {
            syncPhotoFilterToHardware()
        }
    }
    var timerMode: TimerMode = .off
    var activeLens: Lens = .wide
    var flipRotation: Double = 0
    var flashMode: AVCaptureDevice.FlashMode = .off
    var isBurstModeEnabled: Bool = false {
        didSet {
            refreshFastCapturePrioritizationForBurstMode()
            if isBurstModeEnabled {
                flashMode = .off
                timerMode = .off
            }
        }
    }
    private(set) var isBurstCapturing: Bool = false {
        didSet {
            updateAnalysisPauseState()
            updateMetadataOutputStatus()
            if isBurstCapturing {
                detectedCodeURL = nil
                detectedCodeString = nil
                barcodeResetTask?.cancel()
                barcodeResetTask = nil
            }
        }
    }
    private(set) var burstCapturedCount: Int = 0
    var burstCaptureFailureCount: Int = 0
    var burstSaveFailureCount: Int = 0
    var burstIntervalSeconds: Double?
    var burstFrameLimit: Int?
    var burstIntervalRemainingSeconds: Double?
    var burstFeedbackMessage: String?
    var confettiCannonTrigger = 0
    var burstSessionCounter = 0
    var activeBurstSessionID: Int?
    var burstSaveStatsBySession: [Int: BurstSaveStats] = [:]
    @ObservationIgnored
    var burstCaptureTask: Task<Void, Never>?
    @ObservationIgnored
    var burstFeedbackTask: Task<Void, Never>?
    @ObservationIgnored
    nonisolated(unsafe) private(set) var shouldPauseAnalysis = false
    var isMacroEnabled: Bool = false {
        didSet {
            if oldValue != isMacroEnabled {
                applyMacroMode()
                buildAvailableFormats()
            }
        }
    }
    @ObservationIgnored
    var timerCountdownTask: Task<Void, Never>?
    var isTimerCountingDown = false {
        didSet {
            guard oldValue != isTimerCountingDown else { return }
            updateAnalysisPauseState()
            updateMetadataOutputStatus()
            if isTimerCountingDown {
                detectedCodeURL = nil
                detectedCodeString = nil
                barcodeResetTask?.cancel()
                barcodeResetTask = nil
            }
        }
    }
    var timerCountdownValue: Double? = nil
    @ObservationIgnored
    nonisolated(unsafe) var lastGravity: (x: Double, y: Double, z: Double) = (0, -1, 0)
    @ObservationIgnored
    var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    
    // MARK: - Manual controls
    var isAutoExposure: Bool = true {
        didSet {
            if oldValue != isAutoExposure {
                if !isAutoExposure, let d = device {
                    let currentISO = d.iso
                    let currentDur = d.exposureDuration
                    let snappedISO = round(currentISO / 50.0) * 50.0
                    self.iso = max(minISO, min(maxISO, snappedISO))
                    if let closestIdx = shutterSpeeds.indices.min(by: {
                        abs(CMTimeGetSeconds(shutterSpeeds[$0]) - CMTimeGetSeconds(currentDur)) <
                            abs(CMTimeGetSeconds(shutterSpeeds[$1]) - CMTimeGetSeconds(currentDur))
                    }) {
                        self.shutterIndex = closestIdx
                    }
                }
                enforceExposureModeConstraints()
                buildAvailableFormats()
                updateCameraControlsMode()
            }
        }
    }
    var iso: Float = 100 {
        didSet {
            if oldValue != iso {
                syncISOToHardware()
            }
        }
    }
    private(set) var minISO: Float = 25
    private(set) var maxISO: Float = 6400
    private(set) var shutterSpeeds: [CMTime] = []
    var shutterIndex: Int = 0 {
        didSet {
            if oldValue != shutterIndex {
                syncShutterToHardware()
            }
        }
    }
    /// Denominator for in-app shutter slider (1 = 1s, 500 = 1/500s). 0 means use shutterIndex instead.
    var manualShutterDenominator: Int = 0
    var exposureBias: Float = 0.0 {
        didSet {
            if oldValue != exposureBias {
                syncEVToHardware()
            }
        }
    }
    private(set) var minExposureBias: Float = -8.0
    private(set) var maxExposureBias: Float = 8.0
    var exposureDebounceTask: Task<Void, Never>?
    
    var isAdjustingManualFocus: Bool = false
    var showFocusPeaking: Bool = true {
        didSet {
            if showFocusPeaking && showFocusLoupe { showFocusLoupe = false }
            peakingEnabledForAnalysis = !isAutoFocus && showFocusPeaking
        }
    }
    var showFocusLoupe: Bool = false {
        didSet {
            if showFocusLoupe && showFocusPeaking { showFocusPeaking = false }
            loupeEnabledForAnalysis = !isAutoFocus && showFocusLoupe
        }
    }
    var isAutoFocus: Bool = true {
        didSet {
            if oldValue != isAutoFocus {
                peakingEnabledForAnalysis = !isAutoFocus && showFocusPeaking
                loupeEnabledForAnalysis = !isAutoFocus && showFocusLoupe
                if !isAutoFocus, let d = device {
                    self.lensPosition = d.lensPosition
                }
                updateCameraControlsMode()
            }
        }
    }
    var lensPosition: Float = 1.0 {
        didSet {
            if oldValue != lensPosition {
                syncFocusToHardware()
                lastLensPosition = lensPosition
            }
        }
    }
    
    @ObservationIgnored
    nonisolated(unsafe) private(set) var lastLensPosition: Float = 1.0
    @ObservationIgnored
    nonisolated(unsafe) var peakingTemporalScores: [Float] = []
    @ObservationIgnored
    nonisolated(unsafe) private(set) var minimumFocusDistanceForAnalysis: Float = 0
    var focusPeakingHoldTask: Task<Void, Never>?
    
    var isAutoWhiteBalance: Bool = true {
        didSet {
            if oldValue != isAutoWhiteBalance {
                if isAutoWhiteBalance {
                    setAutoWhiteBalance()
                } else {
                    if let d = device {
                        let tnt = d.temperatureAndTintValues(for: d.deviceWhiteBalanceGains)
                        self.whiteBalanceTargetKelvin = tnt.temperature
                    }
                    applyManualWhiteBalance()
                }
                updateCameraControlsMode()
            }
        }
    }
    var whiteBalanceTargetKelvin: Float = 5000 {
        didSet {
            if oldValue != whiteBalanceTargetKelvin {
                if !isAutoWhiteBalance {
                    applyManualWhiteBalance()
                }
                syncWBToHardware()
            }
        }
    }
    var histogramModeSmall: HistogramMode = .none {
        didSet { histogramModeForAnalysisSmall = histogramModeSmall }
    }
    var histogramModeLarge: HistogramMode = .none {
        didSet { histogramModeForAnalysisLarge = histogramModeLarge }
    }
    var showClipping: Bool = false {
        didSet { clippingEnabledForAnalysis = showClipping }
    }
    var showZebraStripes: Bool = false {
        didSet { zebraEnabledForAnalysis = showZebraStripes }
    }
    
    // MARK: - UI State
    private(set) var isCapturing: Bool = false
    var showError: Bool = false
    var errorMessage: String = ""
    var liveISO: Float = 0
    var liveShutter: String = ""
    var liveWB: String = ""
    var liveFocus: String = ""
    var lensSwitchCompletionCount: Int = 0
    var appView: AppView = .standard {
        didSet {
            updateAnalysisPauseState()
            if oldValue != appView && (appView == .settings || oldValue == .settings) {
                setupCameraControls()
            }
        }
    }
    var loupeImage: CGImage?
    nonisolated static let loupeCIContext = CIContext(options: [.useSoftwareRenderer: false])
    var focusPeakingMask: [UInt8] = []
    var zebraMask: [UInt8] = []
    var clippingMask: [UInt8] = []
    var analysisGridSize: CGSize = .zero
    var histogramData: [Float] = Array(repeating: 0, count: 256)
    var redHistogram: [Float] = Array(repeating: 0, count: 256)
    var greenHistogram: [Float] = Array(repeating: 0, count: 256)
    var blueHistogram: [Float] = Array(repeating: 0, count: 256)
    var waveformData: [Float] = []
    nonisolated static var wfCols: Int { WaveformConstants.wfCols }
    nonisolated static var wfRows: Int { WaveformConstants.wfRows }
    var tapFocusIndicatorPoint: CGPoint? = nil
    var isTapFocusIndicatorVisible = false
    var isTapFocusIndicatorDimmed = false
    var isTapFocusInteractionActive = false
    var tapFocusIndicatorOffset: CGFloat = 0
    var tapFocusLockLabel: String? = nil
    var tapExposureBias: Float = 0
    var tap​Focus​Lock​Haptic​Trigger: Int = 0
    @ObservationIgnored
    var tapFocusHideTask: Task<Void, Never>?
    @ObservationIgnored
    var tapFocusLockTask: Task<Void, Never>?
    @ObservationIgnored
    var subjectAreaChangeObserver: NSObjectProtocol?
    @ObservationIgnored
    var focusAdjustmentObservation: NSKeyValueObservation?
    @ObservationIgnored
    var lensPositionObservation: NSKeyValueObservation?
    @ObservationIgnored
    var ignoredTapFocusAdjustmentEvents = 0
    @ObservationIgnored
    var ignoredTapFocusAdjustmentDeadline: Date?
    @ObservationIgnored
    var tapFocusLensPositionBaseline: Float?
    @ObservationIgnored
    var tapFocusLensPositionMonitorTask: Task<Void, Never>?
    @ObservationIgnored
    nonisolated(unsafe) private(set) var loupeEnabledForAnalysis: Bool = false
    @ObservationIgnored
    nonisolated(unsafe) private(set) var peakingEnabledForAnalysis: Bool = false
    @ObservationIgnored
    nonisolated(unsafe) private(set) var zebraEnabledForAnalysis: Bool = false
    @ObservationIgnored
    nonisolated(unsafe) private(set) var clippingEnabledForAnalysis: Bool = false
    @ObservationIgnored
    nonisolated(unsafe) private(set) var histogramModeForAnalysisSmall: HistogramMode = .luminance
    @ObservationIgnored
    nonisolated(unsafe) private(set) var histogramModeForAnalysisLarge: HistogramMode = .luminance
    
    // MARK: - Lens cleaning
    nonisolated func enableLensSmudgeDetectionIfSupported(on camera: AVCaptureDevice) {
        guard camera.activeFormat.isCameraLensSmudgeDetectionSupported else { return }
        try? camera.lockForConfiguration()
        camera.setCameraLensSmudgeDetectionEnabled(true, detectionInterval: CMTime(seconds: 30, preferredTimescale: 1))
        camera.unlockForConfiguration()
    }
    
    func configureLensSmudgeDetection(for camera: AVCaptureDevice) {
        lensSmudgeStatusObservation?.invalidate()
        lensSmudgeStatusObservation = nil
        
        guard camera.activeFormat.isCameraLensSmudgeDetectionSupported else {
            lensSmudgeDetectionStatus = .disabled
            shouldShowLensCleaningHint = false
            didDismissLensCleaningHint = false
            return
        }
        
        lensSmudgeDetectionStatus = camera.cameraLensSmudgeDetectionStatus
        updateLensCleaningHint(for: lensSmudgeDetectionStatus)
        
        lensSmudgeStatusObservation = camera.observe(\.cameraLensSmudgeDetectionStatus, options: [.initial, .new]) { [weak self] _, change in
            guard let status = change.newValue else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.lensSmudgeDetectionStatus = status
                self.updateLensCleaningHint(for: status)
            }
        }
    }
    
    func dismissLensCleaningHint() {
        didDismissLensCleaningHint = true
        shouldShowLensCleaningHint = false
    }
    
    private func updateLensCleaningHint(for status: AVCaptureCameraLensSmudgeDetectionStatus) {
        switch status {
            case .smudged:
                shouldShowLensCleaningHint = !didDismissLensCleaningHint
            case .smudgeNotDetected, .unknown, .disabled:
                shouldShowLensCleaningHint = false
                didDismissLensCleaningHint = false
            @unknown default:
                shouldShowLensCleaningHint = false
                didDismissLensCleaningHint = false
        }
    }
    
    // MARK: - Location
    let locationManager = CLLocationManager()
    var currentLocation: CLLocation?
    
    // MARK: - Computed properties
    var captureAspectRatio: CGFloat { 3.0 / 4.0 }
    
    func isFormatEnabled(_ mode: CaptureMode) -> Bool {
        enabledFormats.contains(mode)
    }
    
    func isResolutionEnabled(_ option: ResolutionOption) -> Bool {
        enabledResolutions.contains(where: { $0.id == option.id })
    }
    
    var supportsManualFocus: Bool {
        device?.isLockingFocusWithCustomLensPositionSupported ?? false
    }
    
    var supportsMacro: Bool {
        // Macro is typically supported on Pro models with AF on Ultra Wide.
        // We look for a back camera that can focus closer than 15cm (150mm).
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInUltraWideCamera, .builtInWideAngleCamera],
            mediaType: .video,
            position: .back
        )
        return discovery.devices.contains { $0.minimumFocusDistance > 0 && $0.minimumFocusDistance <= 150 }
    }
    
    var supportsFlash: Bool {
        guard device?.hasFlash == true else { return false }
        return !photoOutput.supportedFlashModes.isEmpty
    }
    
    var flashLabel: String {
        switch flashMode {
            case .off, .on: "bolt.fill"
            case .auto: "bolt.badge.automatic.fill"
            @unknown default: "bolt.badge.xmark.fill"
        }
    }
    
    var showSimpleView: Bool {
        appView == .clean || appView == .settings || isBurstCapturing || (isTimerCountingDown && shouldHideUIWhileCountingDown)
    }
    
    private func updateAnalysisPauseState() {
        shouldPauseAnalysis = showSimpleView
    }
    
    // MARK: - Configure
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
    
    deinit {
        burstCaptureTask?.cancel()
        burstFeedbackTask?.cancel()
        _burstCaptureTracker.cancelAll()
        _captureContextStore.removeAll()
        if let subjectAreaChangeObserver {
            NotificationCenter.default.removeObserver(subjectAreaChangeObserver)
        }
        focusAdjustmentObservation?.invalidate()
        lensPositionObservation?.invalidate()
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
        
        if session.canAddOutput(depthOutput) {
            session.addOutput(depthOutput)
            depthOutput.isFilteringEnabled = true
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
        
        // Setup rotation coordinator
        self.rotationCoordinator = AVCaptureDevice.RotationCoordinator(device: cam, previewLayer: nil)
        
        // Safely setup synchronizer or fallback
        let syncQueue = DispatchQueue(label: "\(BundleIDs.appID).analysisQueue")
        if depthOutput.connection(with: .depthData) != nil && videoOutput.connection(with: .video) != nil {
            synchronizer = AVCaptureDataOutputSynchronizer(dataOutputs: [videoOutput, depthOutput])
            synchronizer?.setDelegate(self, queue: syncQueue)
        } else {
            // Fallback for devices without LiDAR or if depth is not available in current format
            videoOutput.setSampleBufferDelegate(self, queue: syncQueue)
        }
        
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
        
        self.shouldGeotagLocation = defaults.bool(forKey: "shouldGeotagLocation")
        self.recognizeBarcodes = defaults.object(forKey: "recognizeBarcodes") as? Bool ?? true
        self.shouldShowGrid = defaults.object(forKey: "shouldShowGrid") as? Bool ?? true
        self.shouldShowLevel = defaults.object(forKey: "shouldShowLevel") as? Bool ?? true
        self.detailedCountdownTimer = defaults.object(forKey: "detailedCountdownTimer") as? Bool ?? false
        self.shouldHideUIWhileCountingDown = defaults.object(forKey: "shouldHideUIWhileCountingDown") as? Bool ?? true
        self.shouldPrioritizeBurstSpeed = defaults.object(forKey: "shouldPrioritizeBurstSpeed") as? Bool ?? true
        self.shouldShowBurstFeedback = defaults.object(forKey: "shouldShowBurstFeedback") as? Bool ?? false
        self.shouldShowConfettiCannons = defaults.object(forKey: "shouldShowConfettiCannons") as? Bool ?? true
        
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
    }
    
    private func refreshFastCapturePrioritizationForBurstMode() {
        guard photoOutput.isFastCapturePrioritizationSupported else { return }
        photoOutput.isFastCapturePrioritizationEnabled = isBurstModeEnabled && shouldPrioritizeBurstSpeed && captureMode != .raw
    }
    
    // MARK: - Formats & ranges
    func buildAvailableFormats() {
        // We only enforce this logic if the device is ready.
        guard device != nil else { return }
        
        let zoomBlocksRAW = (device?.videoZoomFactor ?? 1.0) > 1.0
        let isFront = activeLens.isFront
        
        var visibleModes: [CaptureMode] = []
        if photoOutput.availablePhotoCodecTypes.contains(.hevc) {
            visibleModes.append(.heif)
        }
        visibleModes.append(.jpeg)
        if !photoOutput.availableRawPhotoPixelFormatTypes.isEmpty {
            visibleModes.append(.raw)
        }
        if availableFormats != visibleModes {
            availableFormats = visibleModes
        }
        
        let modes: [CaptureMode]
        if isAutoExposure {
            modes = visibleModes.filter { mode in
                switch mode {
                    case .jpeg, .heif:
                        return true
                    case .raw:
                        return !zoomBlocksRAW && !isMacroEnabled
                }
            }
        } else {
            modes = visibleModes.filter { $0 == .raw }
        }
        if enabledFormats != modes {
            enabledFormats = modes
        }
        
        // SMART SWITCH: Keep the current selection if valid, else fallback to preference, else base fallback.
        let targetMode: CaptureMode
        if modes.contains(captureMode) {
            targetMode = captureMode
        } else if modes.contains(defaultFileFormat) {
            targetMode = defaultFileFormat
        } else {
            targetMode = modes.contains(.heif) ? .heif : .jpeg
        }
        
        if captureMode != targetMode {
            captureMode = targetMode
        }
        
        let isCropLens = activeLens == .tele2x || activeLens == .tele8x
        
        let visibleOptions: [ResolutionOption]
        if isFront {
            visibleOptions = []
        } else {
            let outputMax = photoOutput.maxPhotoDimensions
            let allDims = (device?.activeFormat.supportedMaxPhotoDimensions ?? [])
                .filter { $0.width <= outputMax.width && $0.height <= outputMax.height }
                .sorted { Int($0.width) * Int($0.height) < Int($1.width) * Int($1.height) }
            
            var deduped: [ResolutionOption] = []
            for dim in allDims {
                let opt = ResolutionOption(width: dim.width, height: dim.height)
                if !deduped.contains(where: { abs($0.id - opt.id) < 2_000_000 }) {
                    deduped.append(opt)
                }
            }
            // Always show 12MP + 48MP for back optical lenses
            let smallest = deduped.first
            let largest = deduped.last
            if let s = smallest, let l = largest, s.id != l.id {
                visibleOptions = [s, l]
            } else {
                visibleOptions = deduped
            }
        }
        
        let enabledOptions: [ResolutionOption]
        if isFront {
            enabledOptions = []
        } else if isCropLens || isMacroEnabled || captureMode == .raw {
            enabledOptions = visibleOptions.first.map { [$0] } ?? []
        } else {
            enabledOptions = visibleOptions
        }
        
        let sameVisibleOptions = availableResolutions.count == visibleOptions.count &&
        zip(availableResolutions, visibleOptions).allSatisfy { $0.id == $1.id }
        if !sameVisibleOptions {
            availableResolutions = visibleOptions
        }
        
        let sameEnabledOptions = enabledResolutions.count == enabledOptions.count &&
        zip(enabledResolutions, enabledOptions).allSatisfy { $0.id == $1.id }
        if !sameEnabledOptions {
            enabledResolutions = enabledOptions
        }
        
        if !sameEnabledOptions {
            // Options change (Format or Lens switch): re-apply resolution preference
            selectedResolution = defaultResolution == .max ? enabledOptions.last : enabledOptions.first
        } else if let current = selectedResolution, !enabledOptions.contains(where: { $0.id == current.id }) {
            // Current selection became invalid
            selectedResolution = defaultResolution == .max ? enabledOptions.last : enabledOptions.first
        }
    }
    
    func primeResolutionOptions(for lens: Lens, device: AVCaptureDevice) {
        let visibleOptions: [ResolutionOption]
        if lens.isFront {
            visibleOptions = []
        } else {
            let outputMax = device.activeFormat.supportedMaxPhotoDimensions.max(by: {
                Int($0.width) * Int($0.height) < Int($1.width) * Int($1.height)
            }) ?? photoOutput.maxPhotoDimensions
            let allDims = device.activeFormat.supportedMaxPhotoDimensions
                .filter { $0.width <= outputMax.width && $0.height <= outputMax.height }
                .sorted { Int($0.width) * Int($0.height) < Int($1.width) * Int($1.height) }
            
            var deduped: [ResolutionOption] = []
            for dim in allDims {
                let opt = ResolutionOption(width: dim.width, height: dim.height)
                if !deduped.contains(where: { abs($0.id - opt.id) < 2_000_000 }) {
                    deduped.append(opt)
                }
            }
            
            let smallest = deduped.first
            let largest = deduped.last
            if let s = smallest, let l = largest, s.id != l.id {
                visibleOptions = [s, l]
            } else {
                visibleOptions = deduped
            }
        }
        
        let isCropLens = lens == .tele2x || lens == .tele8x
        let enabledOptions: [ResolutionOption]
        if lens.isFront {
            enabledOptions = []
        } else if isCropLens || isMacroEnabled || captureMode == .raw {
            enabledOptions = visibleOptions.first.map { [$0] } ?? []
        } else {
            enabledOptions = visibleOptions
        }
        
        availableResolutions = visibleOptions
        enabledResolutions = enabledOptions
        
        if enabledOptions.isEmpty {
            selectedResolution = nil
        } else if let current = selectedResolution, enabledOptions.contains(where: { $0.id == current.id }) {
            return
        } else {
            selectedResolution = defaultResolution == .max ? enabledOptions.last : enabledOptions.first
        }
    }
    
    func normalizeFlashModeForCurrentDevice() {
        guard supportsFlash else {
            flashMode = .off
            return
        }
        if !photoOutput.supportedFlashModes.contains(flashMode) {
            flashMode = photoOutput.supportedFlashModes.contains(.auto) ? .auto : .off
        }
        if !isAutoExposure {
            flashMode = .off
        }
    }
    
    func enforceExposureModeConstraints() {
        if !isAutoExposure {
            flashMode = .off
            if isMacroEnabled {
                isMacroEnabled = false
            }
            if captureMode != .raw {
                captureMode = .raw
            }
        }
    }
    
    func updateDeviceRanges() {
        guard let d = device else { return }
        minISO = d.activeFormat.minISO
        maxISO = d.activeFormat.maxISO
        
        let stops = generateShutterStops(for: d)
        shutterSpeeds = stops
        shutterIndex = stops.indices.min(by: {
            abs(CMTimeGetSeconds(stops[$0]) - 1.0/60.0) <
                abs(CMTimeGetSeconds(stops[$1]) - 1.0/60.0)
        }) ?? 0
        
        liveISO = d.iso
        liveShutter = Self.formatShutter(d.exposureDuration)
        minExposureBias = d.minExposureTargetBias
        maxExposureBias = d.maxExposureTargetBias
        minimumFocusDistanceForAnalysis = d.minimumFocusDistance > 0 ? Float(d.minimumFocusDistance) / 1000.0 : 0
        
        // Always clamp iso to the new device's valid range (handles lens switches where minISO changes)
        let newISO = max(minISO, min(maxISO, iso))
        if newISO != iso { iso = newISO }
        
        // Update EV slider value (EV bounds are fixed -4...4 so this never crashes)
        if let ev = evControl {
            let clampedEV = max(-4.0, min(4.0, exposureBias))
            ev.value = round(clampedEV * 10) / 10.0
        }
        
        // For ISO and Shutter, we skip setting their .value here because their min/max
        // bounds depend on the active device. switchLens() calls setupCameraControls()
        // right after this, which rebuilds the sliders with the correct bounds and seeds
        // their values safely. Setting them here on stale bounds causes crashes.
        
        // If controls weren't set up yet (e.g. at launch), try again now
        if lensControl == nil || evControl == nil || isoControl == nil || ssControl == nil {
            setupCameraControls()
        }
    }
    
    private func generateShutterStops(for device: AVCaptureDevice) -> [CMTime] {
        let fmt = device.activeFormat
        let minSecs = CMTimeGetSeconds(fmt.minExposureDuration)
        let maxSecs = CMTimeGetSeconds(fmt.maxExposureDuration)
        let timescale = fmt.minExposureDuration.timescale
        
        let allStops: [Double] = [
            1/100000, 1/80000, 1/60000, 1/50000, 1/40000, 1/32000,
            1/25000,  1/20000, 1/16000, 1/12500, 1/10000, 1/8000,
            1/6400,   1/5000,  1/4000,  1/3200,  1/2500,  1/2000,
            1/1600,   1/1250,  1/1000,  1/800,   1/640,   1/500,
            1/400,    1/320,   1/250,   1/200,   1/160,   1/125,
            1/100,    1/80,    1/60,    1/50,    1/40,    1/30,
            1/25,     1/20,    1/15,    1/13,    1/10,    1/8,
            1/6,      1/5,     1/4,     1/3,     1/2.5,   1/2,
            1/1.6,    1/1.3
        ]
        
        return allStops
            .filter { $0 >= minSecs - 1e-9 && $0 <= maxSecs + 1e-9 }
            .map { CMTimeMakeWithSeconds($0, preferredTimescale: timescale) }
    }
    
    static func formatShutter(_ time: CMTime) -> String {
        let secs = CMTimeGetSeconds(time)
        guard secs.isFinite && secs > 0 else { return "—" }
        if secs >= 1.0 { return "\(secs.formatted(.number.precision(.fractionLength(1))))s" }
        return "1/\(Int(round(1.0 / secs)))"
    }
    
    // MARK: - Capture
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
                startBurstCapture(onCapture: onCapture, onBurstPhotoCaptured: onBurstPhotoCaptured)
            }
            return
        }
        
        capturePhoto(onCapture: onCapture)
    }
    
    private func startBurstCapture(onCapture: @escaping @MainActor @Sendable () -> Void,
                                   onBurstPhotoCaptured: @escaping @MainActor @Sendable () -> Void) {
        guard burstCaptureTask == nil else { return }
        guard canStartBurstCapture else {
            if !isAutoExposure && !manualExposureIsFastEnoughForBurst {
                errorMessage = "Raw Bursts in manual exposure require shutter speed of 1/100s or faster."
                showError = true
            }
            return
        }
        
        flashMode = .off
        timerCountdownTask?.cancel()
        timerCountdownTask = nil
        isTimerCountingDown = false
        timerCountdownValue = nil
        burstCapturedCount = 0
        burstCaptureFailureCount = 0
        burstSaveFailureCount = 0
        burstIntervalRemainingSeconds = nil
        burstSessionCounter += 1
        let burstSessionID = burstSessionCounter
        activeBurstSessionID = burstSessionID
        burstSaveStatsBySession[burstSessionID] = BurstSaveStats(captureMode: captureMode, frameLimit: burstFrameLimit)
        isBurstCapturing = true
        onCapture()
        
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
            
            while !Task.isCancelled, self.isBurstModeEnabled {
                guard self.canContinueBurstCapture else { break }
                self.exposureDebounceTask?.cancel()
                self._pendingCaptureModeBox.value = self.captureMode
                self._pendingPhotoFilterBox.value = self.selectedPhotoFilter
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
        guard session.isRunning, !isTimerCountingDown else { return false }
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
        if manualShutterDenominator > 0 {
            return CMTimeMake(value: 1, timescale: CMTimeScale(manualShutterDenominator))
        } else if shutterSpeeds.indices.contains(shutterIndex) {
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
            burstIntervalSeconds = min(5.0, max(0.2, seconds))
        } else {
            burstIntervalSeconds = nil
        }
    }
    
    func setBurstFrameLimit(_ limit: Int?) {
        if let limit {
            burstFrameLimit = min(100, max(1, limit))
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
    
    private func showBurstFeedback(_ message: String) {
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
    
    private func registerCaptureContext(for settings: AVCapturePhotoSettings, isBurst: Bool, burstSessionID: Int? = nil) {
        _captureContextStore.set(
            PhotoCaptureContext(
                captureMode: captureMode,
                photoFilter: selectedPhotoFilter,
                isBurst: isBurst,
                burstSessionID: burstSessionID
            ),
            for: settings.uniqueID
        )
    }
    
    func recordBurstSensorCapture(sessionID: Int) {
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
    
    func capturePhoto(onCapture: @escaping @MainActor @Sendable () -> Void) {
        guard timerCountdownTask == nil else { return }
        
        if let totalSeconds = timerMode.seconds {
            isTimerCountingDown = true
            timerCountdownValue = Double(totalSeconds)
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
                
                while true {
                    let remaining = endDate.timeIntervalSinceNow
                    guard remaining > 0 else { break }
                    
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
        onCapture()
        
        exposureDebounceTask?.cancel()
        _pendingCaptureModeBox.value = captureMode
        _pendingPhotoFilterBox.value = selectedPhotoFilter
        
        // Update orientation based on current physical position
        updateCaptureOrientation()
        
        // For manual exposure, wait for hardware to confirm values are applied before firing.
        // setExposureModeCustom is async — the completionHandler fires once the sensor has
        // actually settled on the requested ISO/shutter, then we fire the shutter.
        if !isAutoExposure, let d = device {
            // Use manualShutterDenominator if set (in-app slider), else fall back to shutterIndex stop
            let duration: CMTime
            if manualShutterDenominator > 0 {
                duration = CMTimeMake(value: 1, timescale: CMTimeScale(manualShutterDenominator))
            } else if shutterSpeeds.indices.contains(shutterIndex) {
                duration = shutterSpeeds[shutterIndex]
            } else {
                return  // no valid shutter duration available, skip
            }
            let isoValue = max(d.activeFormat.minISO, min(d.activeFormat.maxISO, iso))
            try? d.lockForConfiguration()
            d.setExposureModeCustom(duration: duration, iso: isoValue) { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in
                    let settings = self.buildPhotoSettings()
                    self.registerCaptureContext(for: settings, isBurst: false)
                    self.photoOutput.capturePhoto(with: settings, delegate: self)
                    if requestsConfettiAfterCapture {
                        self.requestConfettiCannons()
                    }
                }
            }
            d.unlockForConfiguration()
        } else {
            let settings = buildPhotoSettings()
            registerCaptureContext(for: settings, isBurst: false)
            photoOutput.capturePhoto(with: settings, delegate: self)
            if requestsConfettiAfterCapture {
                requestConfettiCannons()
            }
        }
    }
    
    private func buildPhotoSettings() -> AVCapturePhotoSettings {
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
        
        let settings = buildPhotoSettings()
        settings.flashMode = .off
        if shouldPrioritizeBurstSpeed, captureMode != .raw {
            settings.photoQualityPrioritization = .speed
        }
        return settings
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
    
    private func captureDimensions() -> CMVideoDimensions {
        if let selected = selectedResolution { return selected.dimensions }
        guard let d = device else { return photoOutput.maxPhotoDimensions }
        let outputMax = photoOutput.maxPhotoDimensions
        return d.activeFormat.supportedMaxPhotoDimensions
            .filter { $0.width <= outputMax.width && $0.height <= outputMax.height }
            .max { Int($0.width) * Int($0.height) < Int($1.width) * Int($1.height) }
        ?? outputMax
    }
    
    func applyMacroMode() {
        if isMacroEnabled {
            // 1. Switch to Ultra Wide if it's not already active
            if activeLens != .ultraWide {
                // We use the internal switchLens but skip the recursive applyMacroMode
                // This will be handled by the UI toggle
            }
            
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
