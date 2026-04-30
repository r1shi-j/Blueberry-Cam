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
    var selectedResolution: ResolutionOption? = nil
    private(set) var availableResolutions: [ResolutionOption] = []
    private(set) var enabledResolutions: [ResolutionOption] = []
    var pendingCaptureModeAfterLensSwitch: CaptureMode?
    var activeLens: Lens = .wide
    var isSwitchingLens = false
    
    // MARK: - UI State
    private(set) var isCapturing: Bool = false
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
    nonisolated(unsafe) private(set) var shouldPauseAnalysis = false
    @ObservationIgnored
    var selectedPhotoFilter: PhotoFilter = .off {
        didSet {
            syncPhotoFilterToHardware()
        }
    }
    var confettiCannonTrigger = 0
    @ObservationIgnored
    var onStandardPhotoSaved: (() -> Void)?
    @ObservationIgnored
    nonisolated(unsafe) var lastGravity: (x: Double, y: Double, z: Double) = (0, -1, 0)
    @ObservationIgnored
    var analysisGridSize: CGSize = .zero
    
    // MARK: - Live readouts
    var liveISO: Float = 0
    var liveShutter: String = ""
    var liveWB: String = ""
    var liveFocus: String = ""
    
    // MARK: - Manual controls
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
    private(set) var minISO: Float = 25
    private(set) var maxISO: Float = 6400
    private let preferredISOStops: [Float] = [
        25, 50, 64, 75, 100, 125, 150, 175, 200,
        250, 300, 350, 400,
        500, 600, 700, 800,
        1000, 1200, 1400, 1600,
        2000, 2400, 2800, 3200,
        4000, 4800, 5600, 6400,
        8000, 9600, 11200, 12000
    ]
    private(set) var isoStops: [Float] = []
    private(set) var shutterSpeeds: [CMTime] = []
    private let preferredShutterDenominators: [Int] = [
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
    
    // MARK: - Selfie switch
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
    
    // MARK: - Computed properties
    var showSimpleView: Bool {
        appView == .clean || appView == .settings || isBurstCapturing || (isTimerCountingDown && shouldHideUIWhileCountingDown)
    }
    var captureAspectRatio: CGFloat { 3.0 / 4.0 }
    var formattedISO: String { Self.formatISO(iso) }
    var formattedFocus: String { Double(lensPosition).formatted(.number.precision(.fractionLength(2))) }
    var formattedWhiteBalance: String { "\(Int(whiteBalanceTargetKelvin))K" }
    var isoStopIndex: Float {
        let stops = availableISOStops
        guard let nearestIndex = stops.indices.min(by: {
            abs(Float(stops[$0]) - iso) < abs(Float(stops[$1]) - iso)
        }) else { return 0 }
        return Float(nearestIndex)
    }
    var maxISOStopIndex: Float { Float(max(0, availableISOStops.count - 1)) }
    var maxShutterIndex: Float { Float(max(0, shutterSpeeds.count - 1)) }
    var formattedShutterSpeed: String {
        guard shutterSpeeds.indices.contains(shutterIndex) else { return "--" }
        return Self.formatShutter(shutterSpeeds[shutterIndex])
    }
    var availableISOStops: [Float] {
        let filteredStops = preferredISOStops.filter { stop in
            stop >= minISO && stop <= maxISO
        }
        let boundedStops = ([minISO] + filteredStops + [maxISO]).sorted()
        
        var dedupedStops: [Float] = []
        for stop in boundedStops {
            guard dedupedStops.last.map({ abs($0 - stop) < 0.5 }) != true else { continue }
            dedupedStops.append(stop)
        }
        
        return dedupedStops
    }
    
    // MARK: - Manual controls
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
    
    private func nearestISOStop(to value: Float) -> Float {
        let stops = availableISOStops
        guard let nearestIndex = nearestISOStopIndex(in: stops, to: value) else {
            return max(minISO, min(maxISO, value))
        }
        return stops[nearestIndex]
    }
    
    func nearestISOStopIndex(in stops: [Float], to value: Float) -> Int? {
        stops.indices.min {
            abs(stops[$0] - value) < abs(stops[$1] - value)
        }
    }
    
    private func nearestShutterIndex(to duration: CMTime) -> Int? {
        let seconds = CMTimeGetSeconds(duration)
        guard seconds.isFinite && seconds > 0 else { return nil }
        
        return shutterSpeeds.indices.min {
            abs(CMTimeGetSeconds(shutterSpeeds[$0]) - seconds) < abs(CMTimeGetSeconds(shutterSpeeds[$1]) - seconds)
        }
    }
    
    private func snappedWhiteBalanceKelvin(_ kelvin: Float) -> Float {
        let steppedKelvin = (kelvin / 100).rounded() * 100
        return min(max(steppedKelvin, CameraModel.minWhiteBalance), CameraModel.maxWhiteBalance)
    }
    
    private func snappedFocusPosition(_ position: Float) -> Float {
        let steppedPosition = (position / 0.01).rounded() * 0.01
        return min(max(steppedPosition, 0), 1)
    }
    
    func syncAutoRulerValues(
        iso liveISO: Float,
        exposureDuration: CMTime,
        whiteBalanceTemperature: Float,
        lensPosition liveLensPosition: Float
    ) {
        if isAutoExposure {
            let nextISO = nearestISOStop(to: liveISO)
            if abs(iso - nextISO) > 0.1 {
                iso = nextISO
            }
            
            if let nextShutterIndex = nearestShutterIndex(to: exposureDuration),
               shutterIndex != nextShutterIndex {
                shutterIndex = nextShutterIndex
            }
        }
        
        if isAutoWhiteBalance {
            let nextWhiteBalance = snappedWhiteBalanceKelvin(whiteBalanceTemperature)
            if abs(whiteBalanceTargetKelvin - nextWhiteBalance) >= 50 {
                whiteBalanceTargetKelvin = nextWhiteBalance
            }
        }
        
        if isAutoFocus {
            let nextLensPosition = snappedFocusPosition(liveLensPosition)
            if abs(lensPosition - nextLensPosition) >= 0.005 {
                lensPosition = nextLensPosition
            }
        }
    }
    
    func setExposureBias(_ bias: Float) {
        guard isAutoExposure else { return }
        
        let steppedBias = (bias / 0.1).rounded() * 0.1
        let lowerBound = max(minExposureBias, CameraModel.minEV)
        let upperBound = min(maxExposureBias, CameraModel.maxEV)
        let clampedBias = min(max(steppedBias, lowerBound), upperBound)
        
        guard clampedBias != exposureBias else { return }
        
        exposureBias = clampedBias
        applyExposureBias()
    }
    
    func setManualISOStopIndex(_ value: Float) {
        let stops = availableISOStops
        guard !stops.isEmpty else { return }
        
        let clampedIndex = min(max(Int(value.rounded()), 0), stops.count - 1)
        let nextISO = stops[clampedIndex]
        
        guard nextISO != iso || isAutoExposure else { return }
        
        if isAutoExposure {
            isAutoExposure = false
        }
        exposureBias = 0
        iso = nextISO
        liveISO = nextISO
        applyManualExposure()
    }
    
    func setManualShutterIndex(_ value: Float) {
        let clampedIndex = min(max(Int(value.rounded()), 0), shutterSpeeds.count - 1)
        
        guard shutterSpeeds.indices.contains(clampedIndex),
              clampedIndex != shutterIndex || isAutoExposure else { return }
        
        if isAutoExposure {
            isAutoExposure = false
        }
        exposureBias = 0
        setCustomShutter(to: clampedIndex)
        liveShutter = formattedShutterSpeed
        applyManualExposure()
    }
    
    func setManualFocusPosition(_ position: Float) {
        let clampedPosition = snappedFocusPosition(position)
        
        guard clampedPosition != lensPosition || isAutoFocus else { return }
        
        if isAutoFocus {
            isAutoFocus = false
        }
        lensPosition = clampedPosition
        liveFocus = formattedFocus
        applyManualFocus()
        endManualFocusAdjustment()
    }
    
    func setWhiteBalanceTargetKelvin(_ kelvin: Float) {
        let clampedKelvin = snappedWhiteBalanceKelvin(kelvin)
        
        guard clampedKelvin != whiteBalanceTargetKelvin || isAutoWhiteBalance else { return }
        
        if isAutoWhiteBalance {
            isAutoWhiteBalance = false
        }
        whiteBalanceTargetKelvin = clampedKelvin
        liveWB = formattedWhiteBalance
    }
    
    // MARK: - Capture Settings
    func isFormatEnabled(_ mode: CaptureMode) -> Bool {
        if mode == .raw {
            return canSelectRawCaptureMode
        }
        
        return enabledFormats.contains(mode)
    }
    
    var canSelectRawCaptureMode: Bool {
        guard availableFormats.contains(.raw) else { return false }
        guard !isHighResolutionSelected else { return false }
        guard isAutoExposure, !isMacroEnabled else { return enabledFormats.contains(.raw) }
        return hasRawCapableLensForCurrentFacing
    }
    
    private var hasRawCapableLensForCurrentFacing: Bool {
        Lens.allCases.contains { lens in
            lens.isFront == activeLens.isFront &&
            lens.preservesRawCaptureMode &&
            AVCaptureDevice.default(lens.deviceType, for: .video, position: lens.position) != nil
        }
    }
    
    func isResolutionEnabled(_ option: ResolutionOption) -> Bool {
        if isHighResolutionOption(option) {
            return canSelectHighResolution
        }
        
        return enabledResolutions.contains(where: { $0.id == option.id })
    }
    
    var isHighResolutionSelected: Bool {
        guard let selectedResolution else { return false }
        return isHighResolutionOption(selectedResolution)
    }
    
    var canSelectHighResolution: Bool {
        guard !activeLens.isFront,
              captureMode != .raw,
              !isMacroEnabled,
              highResolutionOption != nil else { return false }
        return hasHighResolutionCapableBackLens
    }
    
    private var highResolutionOption: ResolutionOption? {
        guard availableResolutions.count > 1 else { return nil }
        return availableResolutions.last
    }
    
    func isHighResolutionOption(_ option: ResolutionOption) -> Bool {
        highResolutionOption?.id == option.id
    }
    
    private var hasHighResolutionCapableBackLens: Bool {
        Lens.allCases.contains { lens in
            !lens.isFront &&
            lens.preservesHighResolutionCapture &&
            AVCaptureDevice.default(lens.deviceType, for: .video, position: .back) != nil
        }
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
    
    func waitForSessionQueueIdle() async {
        await withCheckedContinuation { continuation in
            sessionQueue.async {
                continuation.resume()
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
        isoStops = availableISOStops
        
        let shutterOptions = generateShutterStops(for: d)
        shutterSpeeds = shutterOptions.map(\.duration)
        shutterIndex = shutterSpeeds.indices.min(by: {
            abs(CMTimeGetSeconds(shutterSpeeds[$0]) - 1.0/60.0) <
                abs(CMTimeGetSeconds(shutterSpeeds[$1]) - 1.0/60.0)
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
        syncEVToHardware()
        
        // For ISO and Shutter, we skip setting their .value here because their min/max
        // bounds depend on the active device. switchLens() calls setupCameraControls()
        // right after this, which rebuilds the sliders with the correct bounds and seeds
        // their values safely. Setting them here on stale bounds causes crashes.
        
        // If controls weren't set up yet (e.g. at launch), try again now
        if lensControl == nil || evControl == nil || isoControl == nil || ssControl == nil {
            setupCameraControls()
        }
    }
    
    private func generateShutterStops(for device: AVCaptureDevice) -> [(denominator: Int, duration: CMTime)] {
        let fmt = device.activeFormat
        let minSecs = CMTimeGetSeconds(fmt.minExposureDuration)
        let maxSecs = CMTimeGetSeconds(fmt.maxExposureDuration)
        
        return preferredShutterDenominators.compactMap { denominator in
            let seconds = 1.0 / Double(denominator)
            guard seconds >= minSecs - 1e-9 && seconds <= maxSecs + 1e-9 else { return nil }
            return (denominator, CMTimeMake(value: 1, timescale: CMTimeScale(denominator)))
        }
    }
    
    static func formatShutter(_ time: CMTime) -> String {
        let secs = CMTimeGetSeconds(time)
        guard secs.isFinite && secs > 0 else { return "—" }
        if secs >= 1.0 { return "\(secs.formatted(.number.precision(.fractionLength(1))))s" }
        return "1/\(Int(round(1.0 / secs)))s"
    }
    
    static func formatCameraControlShutter(_ time: CMTime) -> String {
        let secs = CMTimeGetSeconds(time)
        guard secs.isFinite && secs > 0 else { return "—" }
        if secs >= 1.0 { return secs.formatted(.number.precision(.fractionLength(1))) }
        return "1/\(Int(round(1.0 / secs)))"
    }
    
    static func formatISO(_ iso: Float) -> String {
        Double(iso).formatted(.number.precision(.fractionLength(0)))
    }
    
    // MARK: Bursts
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
            
            await self.waitForSessionQueueIdle()
            await self.settleManualWhiteBalanceBeforeBurst()
            guard !Task.isCancelled, self.isBurstModeEnabled else { return }
            
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
    
    static let burstIntervalMin = 0.2
    static let burstIntervalMax = 5.0
    static let burstFrameLimitMin = 1
    static let burstFrameLimitMax = 100
    
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
    
    private func refreshFastCapturePrioritizationForBurstMode() {
        guard photoOutput.isFastCapturePrioritizationSupported else { return }
        photoOutput.isFastCapturePrioritizationEnabled = isBurstModeEnabled && shouldPrioritizeBurstSpeed && captureMode != .raw
    }
    
    // MARK: Capturing
    private func capturePhoto(onCapture: @escaping @MainActor @Sendable () -> Void) {
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
}
