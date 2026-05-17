internal import AVFoundation
import CoreMotion
internal import Photos

@MainActor @Observable
class LockedCameraModel: NSObject {
    // MARK: - Session
    var device: AVCaptureDevice?
    nonisolated let session = AVCaptureSession()
    nonisolated let photoOutput = AVCapturePhotoOutput()
    nonisolated let videoOutput = AVCaptureVideoDataOutput()
    nonisolated let sessionQueue = DispatchQueue(label: "\(BundleIDs.appID).locked.sessionQueue")
    nonisolated let frameCounter = FrameCounter()
    let _pendingCaptureModeBox = CaptureModeBox()
    nonisolated let _captureContextStore = LockedPhotoCaptureContextStore()
    nonisolated let _sessionContentURLBox = SessionURLBox()
    
    /// Whether the extension has sufficient Photos access to save captures.
    /// Checks both `.addOnly` and `.readWrite` — if either is granted, we can save.
    var hasPhotosAccess: Bool {
        let addOnly = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        let readWrite = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        return addOnly == .authorized || addOnly == .limited
        || readWrite == .authorized || readWrite == .limited
    }
    
    // MARK: - Defaults
    let proRawFileFormat: ProRawFileFormat = .jpegXLLossless
    let defaultFileFormat: CaptureMode = .heif
    let defaultResolution: ResolutionPreference = .efficient
    let detailedCountdownTimer = false
    let shouldHideUIWhileCountingDown = true
    
    // MARK: - Capture format
    var captureMode: CaptureMode = .heif {
        didSet {
            if oldValue != captureMode {
                buildAvailableFormats()
            }
        }
    }
    var availableFormats: [CaptureMode] = []
    var enabledFormats: [CaptureMode] = []
    var selectedResolution: ResolutionOption? = nil
    var availableResolutions: [ResolutionOption] = []
    var enabledResolutions: [ResolutionOption] = []
    var cachedResolutionOptionsByLens: [Lens: ResolutionOptionsSnapshot] = [:]
    var pendingCaptureModeAfterLensSwitch: CaptureMode?
    var activeLens: Lens = .wide
    var isSwitchingLens = false
    @ObservationIgnored
    var captureRotationCoordinator: AVCaptureDevice.RotationCoordinator?
    @ObservationIgnored
    let captureMotionManager = CMMotionManager()
    @ObservationIgnored
    var captureMotionRotationOffset: CGFloat?
    
    // MARK: - UI State
    var isCapturing: Bool = false
    var processingPhotoCount: Int = 0
    var isProcessingPhoto: Bool { processingPhotoCount > 0 }
    var showError: Bool = false
    var errorMessage: String = ""
    
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
            }
        }
    }
    var iso: Float = 100
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
    var shutterIndex: Int = 0
    var exposureBias: Float = 0.0
    var minExposureBias: Float = -8.0
    var maxExposureBias: Float = 8.0
    var exposureDebounceTask: Task<Void, Never>?
    var isAutoFocus: Bool = true {
        didSet {
            if oldValue != isAutoFocus, !isAutoFocus, let d = device {
                self.lensPosition = d.lensPosition
            }
        }
    }
    var lensPosition: Float = 1.0
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
            }
        }
    }
    var whiteBalanceTargetKelvin: Float = 5000 {
        didSet {
            if oldValue != whiteBalanceTargetKelvin {
                if !isAutoWhiteBalance {
                    applyManualWhiteBalance()
                }
            }
        }
    }
    
    // MARK: - Flash
    var flashMode: AVCaptureDevice.FlashMode = .off {
        didSet {
            if oldValue != flashMode {
                buildAvailableFormats()
            }
        }
    }
    
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
    var isTimerCountingDown = false
    var timerCountdownValue: Double? = nil
    @ObservationIgnored
    var onTimerCountdownSecond: (() -> Void)?
    
    // MARK: - Lens switching
    var lensSwitchCompletionCount: Int = 0
    
    // MARK: - Focus
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
    
    // MARK: - Other properties / methods
    var captureAspectRatio: CGFloat {
        let ratio: CaptureAspectRatioOption = .portrait4x3
        return ratio.widthToHeightRatio
    }
    
    deinit {
        if let subjectAreaChangeObserver {
            NotificationCenter.default.removeObserver(subjectAreaChangeObserver)
        }
        focusAdjustmentObservation?.invalidate()
        lensPositionObservation?.invalidate()
    }
}
