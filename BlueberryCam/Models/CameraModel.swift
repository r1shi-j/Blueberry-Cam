import AVFoundation
import CoreLocation
import Photos
import UIKit
internal import Combine

@MainActor
class CameraModel: NSObject, ObservableObject {
    // MARK: - Session
    nonisolated let session = AVCaptureSession()
    var device: AVCaptureDevice?
    nonisolated let photoOutput = AVCapturePhotoOutput()
    nonisolated let videoOutput = AVCaptureVideoDataOutput()
    nonisolated let sessionQueue = DispatchQueue(label: "\(BundleIDs.appID).sessionQueue")
    nonisolated let frameCounter = FrameCounter()
    let _pendingCaptureModeBox = CaptureModeBox()
    
    // MARK: - Barcode Detection
    nonisolated let metadataOutput = AVCaptureMetadataOutput()
    @Published var detectedCodeURL: URL? = nil
    @Published var detectedCodeString: String? = nil
    @Published var ignoredCodes: [String: Date] = [:]
    var barcodeResetTask: Task<Void, Never>?
    var supportedMetadataTypes: [AVMetadataObject.ObjectType] {
        // Only types available on iOS 15
        [
            .qr,
            .ean13, .ean8, .upce,
            .code128, .code39, .code39Mod43, .code93,
            .itf14, .interleaved2of5,
            .dataMatrix, .pdf417, .aztec
        ]
    }
    
    // MARK: - Defaults (for settings)
    @Published var defaultFileFormat: CaptureMode = .raw {
        didSet {
            UserDefaults.standard.set(defaultFileFormat.rawValue, forKey: "defaultFileFormat")
            if captureMode != defaultFileFormat {
                captureMode = defaultFileFormat
            }
        }
    }
    @Published var defaultResolution: ResolutionPreference = .max {
        didSet {
            UserDefaults.standard.set(defaultResolution.rawValue, forKey: "defaultResolution")
            if !enabledResolutions.isEmpty {
                selectedResolution = defaultResolution == .max ? enabledResolutions.last : enabledResolutions.first
            }
        }
    }
    @Published var defaultHistogramSmall: HistogramMode = .none {
        didSet {
            UserDefaults.standard.set(defaultHistogramSmall.rawValue, forKey: "defaultHistogramSmall")
            histogramModeSmall = defaultHistogramSmall
        }
    }
    @Published var defaultHistogramLarge: HistogramMode = .none {
        didSet {
            UserDefaults.standard.set(defaultHistogramLarge.rawValue, forKey: "defaultHistogramLarge")
            histogramModeLarge = defaultHistogramLarge
        }
    }
    @Published var shouldGeotagLocation = false {
        didSet {
            UserDefaults.standard.set(shouldGeotagLocation, forKey: "shouldGeotagLocation")
            toggleLocationGeotag()
        }
    }
    @Published var recognizeBarcodes: Bool = false {
        didSet {
            UserDefaults.standard.set(recognizeBarcodes, forKey: "recognizeBarcodes")
            updateMetadataOutputStatus()
        }
    }
    @Published var shouldShowGrid = false {
        didSet { UserDefaults.standard.set(shouldShowGrid, forKey: "shouldShowGrid") }
    }
    @Published var shouldShowLevel = false {
        didSet { UserDefaults.standard.set(shouldShowLevel, forKey: "shouldShowLevel") }
    }
    
    // MARK: - Capture format
    @Published var captureMode: CaptureMode = .jpeg {
        didSet {
            if oldValue != captureMode {
                buildAvailableFormats()
            }
        }
    }
    @Published private(set) var availableFormats: [CaptureMode] = []
    @Published private(set) var enabledFormats: [CaptureMode] = []
    @Published private(set) var availableResolutions: [ResolutionOption] = []
    @Published private(set) var enabledResolutions: [ResolutionOption] = []
    @Published var selectedResolution: ResolutionOption? = nil
    @Published var activeLens: Lens = .wide
    @Published var flipRotation: Double = 0
    @Published var flashMode: AVCaptureDevice.FlashMode = .off
    nonisolated(unsafe) var lastGravity: (x: Double, y: Double, z: Double) = (0, -1, 0)
    
    // MARK: - Manual controls
    @Published var isAutoExposure: Bool = true {
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
            }
        }
    }
    @Published var iso: Float = 100
    @Published private(set) var minISO: Float = 25
    @Published private(set) var maxISO: Float = 6400
    @Published private(set) var shutterSpeeds: [CMTime] = []
    @Published var shutterIndex: Int = 0
    @Published var manualShutterDenominator: Int = 0
    @Published var exposureBias: Float = 0.0
    @Published private(set) var minExposureBias: Float = -8.0
    @Published private(set) var maxExposureBias: Float = 8.0
    var exposureDebounceTask: Task<Void, Never>?
    
    @Published var isAdjustingManualFocus: Bool = false
    @Published var showFocusLoupe: Bool = false {
        didSet {
            loupeEnabledForAnalysis = !isAutoFocus && showFocusLoupe
        }
    }
    @Published var isAutoFocus: Bool = true {
        didSet {
            if oldValue != isAutoFocus {
                loupeEnabledForAnalysis = !isAutoFocus && showFocusLoupe
                if !isAutoFocus, let d = device {
                    self.lensPosition = d.lensPosition
                }
            }
        }
    }
    @Published var lensPosition: Float = 1.0 {
        didSet {
            if oldValue != lensPosition {
                lastLensPosition = lensPosition
            }
        }
    }
    
    nonisolated(unsafe) private(set) var lastLensPosition: Float = 1.0
    nonisolated(unsafe) private(set) var minimumFocusDistanceForAnalysis: Float = 0
    var focusPeakingHoldTask: Task<Void, Never>?
    
    @Published var isAutoWhiteBalance: Bool = true {
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
    @Published var whiteBalanceTargetKelvin: Float = 5000 {
        didSet {
            if oldValue != whiteBalanceTargetKelvin {
                if !isAutoWhiteBalance {
                    applyManualWhiteBalance()
                }
            }
        }
    }
    @Published var histogramModeSmall: HistogramMode = .none {
        didSet { histogramModeForAnalysisSmall = histogramModeSmall }
    }
    @Published var histogramModeLarge: HistogramMode = .none {
        didSet { histogramModeForAnalysisLarge = histogramModeLarge }
    }
    @Published var showClipping: Bool = false {
        didSet { clippingEnabledForAnalysis = showClipping }
    }
    @Published var showZebraStripes: Bool = false {
        didSet { zebraEnabledForAnalysis = showZebraStripes }
    }
    
    // MARK: - UI State
    @Published private(set) var isCapturing: Bool = false
    @Published var showError: Bool = false
    @Published var errorMessage: String = ""
    @Published var liveISO: Float = 0
    @Published var liveShutter: String = ""
    @Published var liveWB: String = ""
    @Published var liveFocus: String = ""
    @Published var lensSwitchCompletionCount: Int = 0
    @Published var appView: AppView = .standard
    @Published var loupeImage: CGImage?
    nonisolated static let loupeCIContext = CIContext(options: [.useSoftwareRenderer: false])
    @Published var zebraMask: [UInt8] = []
    @Published var clippingMask: [UInt8] = []
    @Published var analysisGridSize: CGSize = .zero
    @Published var histogramData: [Float] = Array(repeating: 0, count: 256)
    @Published var redHistogram: [Float] = Array(repeating: 0, count: 256)
    @Published var greenHistogram: [Float] = Array(repeating: 0, count: 256)
    @Published var blueHistogram: [Float] = Array(repeating: 0, count: 256)
    @Published var waveformData: [Float] = []
    nonisolated static var wfCols: Int { WaveformConstants.wfCols }
    nonisolated static var wfRows: Int { WaveformConstants.wfRows }
    @Published var tapFocusIndicatorPoint: CGPoint? = nil
    @Published var isTapFocusIndicatorVisible = false
    @Published var isTapFocusIndicatorDimmed = false
    @Published var isTapFocusInteractionActive = false
    @Published var tapFocusIndicatorOffset: CGFloat = 0
    @Published var tapFocusLockLabel: String? = nil
    @Published var tapExposureBias: Float = 0
    var tapFocusHideTask: Task<Void, Never>?
    var tapFocusLockTask: Task<Void, Never>?
    var subjectAreaChangeObserver: NSObjectProtocol?
    var focusAdjustmentObservation: NSKeyValueObservation?
    var lensPositionObservation: NSKeyValueObservation?
    var ignoredTapFocusAdjustmentEvents = 0
    var ignoredTapFocusAdjustmentDeadline: Date?
    var tapFocusLensPositionBaseline: Float?
    var tapFocusLensPositionMonitorTask: Task<Void, Never>?
    nonisolated(unsafe) private(set) var loupeEnabledForAnalysis: Bool = false
    nonisolated(unsafe) private(set) var zebraEnabledForAnalysis: Bool = false
    nonisolated(unsafe) private(set) var clippingEnabledForAnalysis: Bool = false
    nonisolated(unsafe) private(set) var histogramModeForAnalysisSmall: HistogramMode = .luminance
    nonisolated(unsafe) private(set) var histogramModeForAnalysisLarge: HistogramMode = .luminance
    
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
    
    
    var supportsFlash: Bool {
        guard device?.hasFlash == true else { return false }
        return !photoOutput.supportedFlashModes.isEmpty
    }
    
    var flashLabel: (systemImage: String, isActive: Bool) {
        switch flashMode {
            case .off: return ("bolt.slash", false)
            case .auto: return ("bolt.badge.a.fill", true)
            case .on: return ("bolt.fill", true)
            @unknown default: return ("bolt.slash", false)
        }
    }
    
    var showSimpleView: Bool {
        appView == .clean || appView == .settings
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
        if let subjectAreaChangeObserver = subjectAreaChangeObserver {
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
        
        configureSubjectAreaMonitoring(for: cam)
        
        // Set video orientation on connections (iOS 15 compatible)
        let isFront = activeLens.isFront
        for conn in [photoOutput.connection(with: .video),
                     videoOutput.connection(with: .video)].compactMap({ $0 }) {
            if conn.isVideoOrientationSupported {
                conn.videoOrientation = .portrait
            }
            conn.isVideoMirrored = isFront
        }
        
        session.commitConfiguration()
        
        self.flipRotation = activeLens.isFront ? 180 : 0
        
        // Use video output as the sole sample buffer delegate
        let syncQueue = DispatchQueue(label: "\(BundleIDs.appID).analysisQueue")
        videoOutput.setSampleBufferDelegate(self, queue: syncQueue)
        
        self.device = cam
        self.buildAvailableFormats()
        self.updateDeviceRanges()
        self.normalizeFlashModeForCurrentDevice()
        self.enforceExposureModeConstraints()
    }
    
    private func loadSettings() {
        let defaults = UserDefaults.standard
        
        if let format = defaults.string(forKey: "defaultFileFormat"), let mode = CaptureMode(rawValue: format) {
            self.defaultFileFormat = mode
            self.captureMode = mode
        }
        
        self.shouldGeotagLocation = defaults.bool(forKey: "shouldGeotagLocation")
        self.recognizeBarcodes = defaults.object(forKey: "recognizeBarcodes") as? Bool ?? true
        self.shouldShowGrid = defaults.object(forKey: "shouldShowGrid") as? Bool ?? true
        self.shouldShowLevel = defaults.object(forKey: "shouldShowLevel") as? Bool ?? true
        
        if let res = defaults.string(forKey: "defaultResolution"), let rPref = ResolutionPreference(rawValue: res) {
            self.defaultResolution = rPref
        }
        
        if let histSmall = defaults.string(forKey: "defaultHistogramSmall"), let hMode = HistogramMode(rawValue: histSmall) {
            self.defaultHistogramSmall = hMode
        }
        
        if let histLarge = defaults.string(forKey: "defaultHistogramLarge"), let hMode = HistogramMode(rawValue: histLarge) {
            self.defaultHistogramLarge = hMode
        }
    }
    
    // MARK: - Formats & ranges
    func buildAvailableFormats() {
        guard device != nil else { return }
        
        let zoomBlocksRAW = (device?.videoZoomFactor ?? 1.0) > 1.0
        let isFront = activeLens.isFront
        
        var visibleModes: [CaptureMode] = [.jpeg]
        if photoOutput.availablePhotoCodecTypes.contains(.hevc) {
            visibleModes.append(.heif)
        }
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
                        return !zoomBlocksRAW
                }
            }
        } else {
            modes = visibleModes.filter { $0 == .raw }
        }
        if enabledFormats != modes {
            enabledFormats = modes
        }
        
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
        
        // On iOS 15 we don't have supportedMaxPhotoDimensions — show a single resolution entry
        let visibleOptions: [ResolutionOption]
        if isFront {
            visibleOptions = []
        } else {
            if let fmt = device?.activeFormat {
                let desc = fmt.formatDescription
                let dims = CMVideoFormatDescriptionGetDimensions(desc)
                let opt = ResolutionOption(width: dims.width, height: dims.height)
                visibleOptions = [opt]
            } else {
                visibleOptions = []
            }
        }
        
        let enabledOptions: [ResolutionOption]
        if isFront {
            enabledOptions = []
        } else if captureMode == .raw {
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
            selectedResolution = defaultResolution == .max ? enabledOptions.last : enabledOptions.first
        } else if let current = selectedResolution, !enabledOptions.contains(where: { $0.id == current.id }) {
            selectedResolution = defaultResolution == .max ? enabledOptions.last : enabledOptions.first
        }
    }
    
    func primeResolutionOptions(for lens: Lens, device: AVCaptureDevice) {
        let visibleOptions: [ResolutionOption]
        if lens.isFront {
            visibleOptions = []
        } else {
            let fmt = device.activeFormat
            let dims = CMVideoFormatDescriptionGetDimensions(fmt.formatDescription)
            let opt = ResolutionOption(width: dims.width, height: dims.height)
            visibleOptions = [opt]
        }
        
        let enabledOptions: [ResolutionOption]
        if lens.isFront {
            enabledOptions = []
        } else if captureMode == .raw {
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
        
        let newISO = max(minISO, min(maxISO, iso))
        if newISO != iso { iso = newISO }
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
        if secs >= 1.0 { return String(format: "%.1fs", secs) }
        return "1/\(Int(round(1.0 / secs)))"
    }
    
    // MARK: - Capture
    func changeCapturingState(to new: Bool) {
        isCapturing = new
    }
    
    func capturePhoto(onCapture: () -> ()) {
        onCapture()
        
        exposureDebounceTask?.cancel()
        _pendingCaptureModeBox.value = captureMode
        
        updateCaptureOrientation()
        
        if !isAutoExposure, let d = device {
            let duration: CMTime
            if manualShutterDenominator > 0 {
                duration = CMTimeMake(value: 1, timescale: CMTimeScale(manualShutterDenominator))
            } else if shutterSpeeds.indices.contains(shutterIndex) {
                duration = shutterSpeeds[shutterIndex]
            } else {
                return
            }
            let isoValue = max(d.activeFormat.minISO, min(d.activeFormat.maxISO, iso))
            try? d.lockForConfiguration()
            d.setExposureModeCustom(duration: duration, iso: isoValue) { [weak self] _ in
                guard let self = self else { return }
                Task { @MainActor in
                    self.photoOutput.capturePhoto(with: self.buildPhotoSettings(), delegate: self)
                }
            }
            d.unlockForConfiguration()
        } else {
            photoOutput.capturePhoto(with: buildPhotoSettings(), delegate: self)
        }
    }
    
    private func buildPhotoSettings() -> AVCapturePhotoSettings {
        let zoomBlocksRAW = (device?.videoZoomFactor ?? 1.0) > 1.0
        
        switch captureMode {
            case .raw:
                if !zoomBlocksRAW,
                   let fmt = photoOutput.availableRawPhotoPixelFormatTypes.first(where: {
                       !AVCapturePhotoOutput.isAppleProRAWPixelFormat($0)
                   }) ?? photoOutput.availableRawPhotoPixelFormatTypes.first {
                    let s = AVCapturePhotoSettings(rawPixelFormatType: fmt)
                    applyFlashModeIfSupported(to: s)
                    return s
                }
                fallthrough
            case .heif:
                if photoOutput.availablePhotoCodecTypes.contains(.hevc) {
                    let s = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
                    applyFlashModeIfSupported(to: s)
                    return s
                }
                fallthrough
            case .jpeg:
                let s = AVCapturePhotoSettings()
                applyFlashModeIfSupported(to: s)
                return s
        }
    }
    
    private func updateCaptureOrientation() {
        guard session.isRunning, let photoConnection = photoOutput.connection(with: .video), photoConnection.isActive else { return }
        
        let (gx, gy, gz) = lastGravity
        let isFront = activeLens.isFront
        
        if abs(gz) > 0.75 { return }
        
        let orientation: AVCaptureVideoOrientation
        if abs(gy) > abs(gx) {
            if gy < 0 {
                orientation = .portrait
            } else {
                orientation = .portraitUpsideDown
            }
        } else {
            if gx > 0 {
                orientation = isFront ? .landscapeLeft : .landscapeRight
            } else {
                orientation = isFront ? .landscapeRight : .landscapeLeft
            }
        }
        
        if photoConnection.isVideoOrientationSupported {
            photoConnection.videoOrientation = orientation
        }
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
    
}
