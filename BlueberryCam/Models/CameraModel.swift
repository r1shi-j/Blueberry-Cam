internal import AVFoundation
internal import CoreLocation
internal import Photos

@MainActor @Observable
class CameraModel: NSObject, AVCaptureSessionControlsDelegate {
    // MARK: - Session
    var device: AVCaptureDevice?
    nonisolated let session = AVCaptureSession()
    nonisolated let dualSession: AVCaptureMultiCamSession? = AVCaptureMultiCamSession.isMultiCamSupported ? AVCaptureMultiCamSession() : nil
    nonisolated let photoOutput = AVCapturePhotoOutput()
    nonisolated let videoOutput = AVCaptureVideoDataOutput()
    nonisolated let secondaryVideoOutput = AVCaptureVideoDataOutput()
    nonisolated let liveFilterPreviewOutput = LiveFilterPreviewOutput()
    nonisolated let sessionQueue = DispatchQueue(label: "\(BundleIDs.appID).sessionQueue")
    nonisolated let analysisQueue = DispatchQueue(label: "\(BundleIDs.appID).analysisQueue")
    nonisolated let pipFrameQueue = DispatchQueue(label: "\(BundleIDs.appID).pipFrameQueue")
    nonisolated let frameCounter = FrameCounter()
    let _pendingCaptureModeBox = CaptureModeBox()
    let _pendingPhotoFilterBox = PhotoFilterBox()
    let _liveCaptureModeBox = CaptureModeBox()
    let _livePhotoFilterBox = PhotoFilterBox()
    var isCaptureSessionRunning = false
    let _pendingSaveLocationBox = SaveLocationBox()
    let _captureContextStore = PhotoCaptureContextStore()
    let _burstCaptureTracker = BurstCaptureTracker()
    let _secondaryFrameStore = PixelBufferStore()
    
    // MARK: - Camera Control
    var cleanUIControl: AVCaptureIndexPicker?
    var filterControl: AVCaptureIndexPicker?
    var lensControl: AVCaptureIndexPicker?
    var evControl: AVCaptureSlider?
    var isoControl: AVCaptureIndexPicker?
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
    var saveLocation: SaveLocation = .stored {
        didSet {
            UserDefaults.standard.set(saveLocation.rawValue, forKey: SaveLocation.storageKey)
            if saveLocation == .files {
                ensureDefaultFileSaveLocation()
                validateFilesSaveLocation()
            }
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
    var isSmartSelfieFramingEnabled = false {
        didSet {
            guard oldValue != isSmartSelfieFramingEnabled else { return }
            UserDefaults.standard.set(isSmartSelfieFramingEnabled, forKey: "isSmartSelfieFramingEnabled")
            refreshSmartSelfieFraming()
        }
    }
    
    // MARK: - Capture format
    var captureMode: CaptureMode = .raw {
        didSet {
            if oldValue != captureMode {
                _liveCaptureModeBox.value = captureMode
                if captureMode == .raw, selectedPhotoFilter != .off {
                    selectedPhotoFilter = .off
                }
                buildAvailableFormats()
                refreshFastCapturePrioritizationForBurstMode()
                updateCameraControlsMode()
                refreshSmartSelfieFraming()
            }
        }
    }
    var availableFormats: [CaptureMode] = []
    var enabledFormats: [CaptureMode] = []
    var selectedResolution: ResolutionOption? = nil {
        didSet {
            updateLiveFilterPreviewReferenceSize()
        }
    }
    var availableResolutions: [ResolutionOption] = []
    var enabledResolutions: [ResolutionOption] = []
    var cachedResolutionOptionsByLens: [Lens: ResolutionOptionsSnapshot] = [:]
    var selectedCaptureAspectRatio: CaptureAspectRatioOption = .defaultSelection
    var availableCaptureAspectRatios: [CaptureAspectRatioOption] = [.defaultSelection]
    var isCaptureAspectRatioTransitioning = false
    var pendingCaptureModeAfterLensSwitch: CaptureMode?
    var activeLens: Lens = .wide
    var isSwitchingLens = false
    @ObservationIgnored
    var captureRotationCoordinator: AVCaptureDevice.RotationCoordinator?
    
    // MARK: - Dual camera
    var isDualCameraEnabled = false {
        didSet {
            guard oldValue != isDualCameraEnabled else { return }
            updateAnalysisPauseState()
            refreshSmartSelfieFraming()
            if isDualCameraEnabled {
                selectedPhotoFilter = .off
                isAutoExposure = true
                isAutoFocus = true
                isAutoWhiteBalance = true
                isMacroEnabled = false
                showFocusPeaking = false
                showFocusLoupe = false
                showZebraStripes = false
                showClipping = false
                histogramModeSmall = .none
                histogramModeLarge = .none
            }
            if !isConfiguringDualCamera {
                buildAvailableFormats()
                setupCameraControls()
            }
        }
    }
    var isConfiguringDualCamera = false
    var isDetachingPreviewForReconfiguration = false
    var isDualCameraTransitionCoverVisible = false
    var isDualCameraPreviewSettling = false
    var secondaryDevice: AVCaptureDevice?
    var secondaryLens: Lens?
    var mainPreviewDeviceUniqueID: String?
    var pipPreviewDeviceUniqueID: String?
    var dualCameraPipPlacement: DualCameraPipPlacement = .topTrailing
    var dualCameraPipRotationAngle: CGFloat = 0
    @ObservationIgnored
    var dualCameraPreviewSettlingTask: Task<Void, Never>?
    
    // MARK: - Save Location
    var fileSaveLocationName = FileSaveLocationStore.displayName()
    var isFileSaveLocationAvailable = true
    var fileSaveLocationIssue: String?
    
    // MARK: - UI State
    var isCapturing: Bool = false
    var showError: Bool = false
    var errorMessage: String = ""
    var appView: AppView = .standard {
        didSet {
            updateAnalysisPauseState()
            if oldValue != appView && (appView == .settings || oldValue == .settings) {
                setupCameraControls()
            }
        }
    }
    @ObservationIgnored
    nonisolated(unsafe) var shouldPauseAnalysis = false
    var selectedPhotoFilter: PhotoFilter = .off {
        didSet {
            guard oldValue != selectedPhotoFilter else { return }
            _livePhotoFilterBox.value = selectedPhotoFilter
            enforcePhotoFilterConstraints()
            syncPhotoFilterToHardware()
            buildAvailableFormats()
            updateCameraControlsMode()
        }
    }
    var confettiCannonTrigger = 0
    @ObservationIgnored
    var onStandardPhotoSaved: (() -> Void)?
    @ObservationIgnored
    var analysisGridSize: CGSize = .zero
    @ObservationIgnored
    nonisolated(unsafe) var liveFilterPreviewReferenceSize: CGSize = .zero
    
    // MARK: - Live readouts
    var liveISO: Float = 0
    var liveShutter: String = ""
    var liveWB: String = ""
    var liveFocus: String = ""
    
    // MARK: - Manual controls
    var isViewfinderBright = false {
        didSet { isViewfinderBrightForAnalysis = isViewfinderBright }
    }
    @ObservationIgnored
    nonisolated(unsafe) private(set) var isViewfinderBrightForAnalysis = false
    
    static let minEV: Float = -4
    static let maxEV: Float = 4
    var isAutoExposure: Bool = true {
        didSet {
            if oldValue != isAutoExposure {
                if !isAutoExposure, let d = device {
                    let currentISO = d.iso
                    let currentDur = d.exposureDuration
                    self.iso = nearestISOStop(to: currentISO)
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
    var minISO: Float = 25
    var maxISO: Float = 6400
    let preferredISOStops: [Float] = [
        25, 50, 64, 75, 100, 125, 150, 175, 200,
        250, 300, 350, 400,
        500, 600, 700, 800,
        1000, 1200, 1400, 1600,
        2000, 2400, 2800, 3200,
        4000, 4800, 5600, 6400,
        8000, 9600, 11200, 12000
    ]
    var isoStops: [Float] = []
    var shutterSpeeds: [CMTime] = []
    let preferredShutterDenominators: [Int] = [
        1, 2, 3, 4, 5, 6, 8, 10, 13, 15, 20, 25, 30, 40, 50, 60, 80, 100, 125,
        160, 200, 250, 320, 400, 500, 640, 800, 1000, 1250, 1600, 2000, 2500,
        3200, 4000, 5000, 6000, 7000, 8000, 9000, 10000, 12500, 15000, 17500,
        20000, 25000, 30000, 40000, 50000, 62500
    ]
    var shutterIndex: Int = 0 {
        didSet {
            if oldValue != shutterIndex {
                syncShutterToHardware()
            }
        }
    }
    var exposureBias: Float = 0.0 {
        didSet {
            if oldValue != exposureBias {
                syncEVToHardware()
            }
        }
    }
    var minExposureBias: Float = -8.0
    var maxExposureBias: Float = 8.0
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
                    if !showFocusPeaking && !showFocusLoupe {
                        showFocusPeaking = true
                    }
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
            }
        }
    }
    @ObservationIgnored
    nonisolated(unsafe) var peakingTemporalScores: [Float] = []
    var focusPeakingHoldTask: Task<Void, Never>?
    static let minWhiteBalance: Float = 2000
    static let maxWhiteBalance: Float = 10000
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
    
    // MARK: - Flash
    var flashMode: AVCaptureDevice.FlashMode = .off
    
    // MARK: - Macro
    var isMacroEnabled: Bool = false {
        didSet {
            if oldValue != isMacroEnabled {
                applyMacroMode()
                buildAvailableFormats()
            }
        }
    }
    
    // MARK: - Timer
    var timerMode: TimerMode = .off
    var timerCountdownTask: Task<Void, Never>?
    var isTimerCountingDown = false {
        didSet {
            guard oldValue != isTimerCountingDown else { return }
            updateAnalysisPauseState()
            updateMetadataOutputStatus()
            refreshSmartSelfieFraming()
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
    var onTimerCountdownSecond: (() -> Void)?
    
    // MARK: - Burst
    var isBurstModeEnabled: Bool = false {
        didSet {
            refreshFastCapturePrioritizationForBurstMode()
            if isBurstModeEnabled {
                flashMode = .off
                timerMode = .off
            }
        }
    }
    var isBurstCapturing: Bool = false {
        didSet {
            updateAnalysisPauseState()
            updateMetadataOutputStatus()
            refreshSmartSelfieFraming()
            if isBurstCapturing {
                detectedCodeURL = nil
                detectedCodeString = nil
                barcodeResetTask?.cancel()
                barcodeResetTask = nil
            }
        }
    }
    var burstCapturedCount: Int = 0
    var burstIntervalSeconds: Double?
    var burstFrameLimit: Int?
    var burstIntervalRemainingSeconds: Double?
    var burstFeedbackMessage: String?
    var burstSessionCounter = 0
    var activeBurstSessionID: Int?
    var burstSaveStatsBySession: [Int: BurstSaveStats] = [:]
    @ObservationIgnored
    var burstCaptureTask: Task<Void, Never>?
    @ObservationIgnored
    var burstFeedbackTask: Task<Void, Never>?
    
    // MARK: - Lens switching
    var flipRotation: Double = 0
    var lensSwitchCompletionCount: Int = 0
    
    // MARK: - Focus
    var focusPeakingMask: [UInt8] = []
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
    var tapFocusRetakeProtectionUntil: Date?
    @ObservationIgnored
    var tapFocusLensPositionBaseline: Float?
    @ObservationIgnored
    var tapFocusLensPositionMonitorTask: Task<Void, Never>?
    var loupeImage: CGImage?
    @ObservationIgnored
    nonisolated(unsafe) private(set) var loupeEnabledForAnalysis: Bool = false
    @ObservationIgnored
    nonisolated(unsafe) private(set) var peakingEnabledForAnalysis: Bool = false
    
    // MARK: - Zebras
    var showZebraStripes: Bool = false {
        didSet { zebraEnabledForAnalysis = showZebraStripes }
    }
    var zebraMask: [UInt8] = []
    @ObservationIgnored
    nonisolated(unsafe) private(set) var zebraEnabledForAnalysis: Bool = false
    
    // MARK: - Highlight Clipping
    var showClipping: Bool = false {
        didSet { clippingEnabledForAnalysis = showClipping }
    }
    var clippingMask: [UInt8] = []
    @ObservationIgnored
    nonisolated(unsafe) private(set) var clippingEnabledForAnalysis: Bool = false
    
    // MARK: - Histograms
    var histogramModeSmall: HistogramMode = .none {
        didSet { histogramModeForAnalysisSmall = histogramModeSmall }
    }
    var histogramModeLarge: HistogramMode = .none {
        didSet { histogramModeForAnalysisLarge = histogramModeLarge }
    }
    var histogramData: [Float] = Array(repeating: 0, count: 256)
    var redHistogram: [Float] = Array(repeating: 0, count: 256)
    var greenHistogram: [Float] = Array(repeating: 0, count: 256)
    var blueHistogram: [Float] = Array(repeating: 0, count: 256)
    var waveformData: [Float] = []
    nonisolated static var wfCols: Int { WaveformConstants.wfCols }
    nonisolated static var wfRows: Int { WaveformConstants.wfRows }
    @ObservationIgnored
    nonisolated(unsafe) private(set) var histogramModeForAnalysisSmall: HistogramMode = .luminance
    @ObservationIgnored
    nonisolated(unsafe) private(set) var histogramModeForAnalysisLarge: HistogramMode = .luminance
    
    // MARK: - Location
    let locationManager = CLLocationManager()
    var currentLocation: CLLocation?
    
    // MARK: - Barcode Detection
    nonisolated let metadataOutput = AVCaptureMetadataOutput()
    var detectedCodeURL: URL? = nil
    var detectedCodeString: String? = nil
    var detectedCodes: [DetectedCode] = []
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
    var didDismissLensCleaningHint = false
    @ObservationIgnored
    var lensSmudgeStatusObservation: NSKeyValueObservation?
    
    // MARK: - Smart selfie framing
    @ObservationIgnored
    var smartSelfieFramingMonitor: AVCaptureSmartFramingMonitor?
    @ObservationIgnored
    var smartSelfieFramingRecommendationObservation: NSKeyValueObservation?
    @ObservationIgnored
    var smartSelfieCenterStageActiveObservation: NSKeyValueObservation?
    @ObservationIgnored
    var smartSelfieCenterStageDeviceUniqueID: String?
    @ObservationIgnored
    var didEnableSmartSelfieCenterStage = false
    @ObservationIgnored
    var smartSelfieFramingApplyTask: Task<Void, Never>?
    var isSmartSelfieFramingAvailable = false
    var isSmartSelfieFramingMonitoring = false
    var isSmartSelfieCenterStageActive = false
    var lastAppliedSmartSelfieFramingRecommendation: SmartSelfieFramingRecommendation?
    
    // MARK: - Other properties / methods
    var captureAspectRatio: CGFloat {
        let ratio: CaptureAspectRatioOption = activeLens.isFront ? selectedCaptureAspectRatio : .portrait4x3
        return ratio.widthToHeightRatio
    }
    
    func updateAnalysisPauseState() {
        shouldPauseAnalysis = showSimpleView || isDualCameraEnabled
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
}
