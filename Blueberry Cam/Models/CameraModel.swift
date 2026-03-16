internal import AVFoundation
internal import CoreLocation
import ImageIO
import Photos
import SwiftUI
import UniformTypeIdentifiers

@MainActor @Observable
class CameraModel: NSObject, AVCaptureSessionControlsDelegate {
    // MARK: - Session
    nonisolated let session = AVCaptureSession()
    var device: AVCaptureDevice?
    nonisolated let photoOutput = AVCapturePhotoOutput()
    nonisolated let videoOutput = AVCaptureVideoDataOutput()
    nonisolated let depthOutput = AVCaptureDepthDataOutput()
    private var synchronizer: AVCaptureDataOutputSynchronizer?
    nonisolated let sessionQueue = DispatchQueue(label: "com.blueberrycam.sessionQueue")
    nonisolated let frameCounter = FrameCounter()
    let _pendingCaptureModeBox = CaptureModeBox()
    
    // MARK: - Camera Control (iOS 18)
    var cleanUIControl: AVCaptureIndexPicker?
    var lensControl: AVCaptureIndexPicker?
    var evControl: AVCaptureSlider?
    var isoControl: AVCaptureSlider?
    var ssControl: AVCaptureIndexPicker?
    var focusControl: AVCaptureSlider?
    var wbControl: AVCaptureSlider?
    /// Prevents Camera Control action callbacks from overwriting properties when we set ctrl.value programmatically
    var isUpdatingHardwareControl = false
    
    // MARK: - Defaults (for settings)
    var selectedFileFormat: CaptureMode = .raw {
        didSet {
            UserDefaults.standard.set(selectedFileFormat.rawValue, forKey: "selectedFileFormat")
            // When user changes their default preference, we immediately try to apply it
            if availableFormats.contains(selectedFileFormat) {
                captureMode = selectedFileFormat
            }
        }
    }
    var preferredResolution: ResolutionPreference = .max {
        didSet {
            UserDefaults.standard.set(preferredResolution.rawValue, forKey: "preferredResolution")
            // Force apply the new preference immediately to the current selection
            if !availableResolutions.isEmpty {
                selectedResolution = preferredResolution == .max ? availableResolutions.last : availableResolutions.first
            }
        }
    }
    var shouldGeotagLocation = false {
        didSet {
            UserDefaults.standard.set(shouldGeotagLocation, forKey: "shouldGeotagLocation")
            toggleLocationGeotag()
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
    var shouldShowGrid = true {
        didSet { UserDefaults.standard.set(shouldShowGrid, forKey: "shouldShowGrid") }
    }
    var shouldShowLevel = true {
        didSet { UserDefaults.standard.set(shouldShowLevel, forKey: "shouldShowLevel") }
    }
    
    // MARK: - Capture format
    var captureMode: CaptureMode = .raw {
        didSet {
            if oldValue != captureMode {
                buildAvailableFormats()
            }
        }
    }
    var availableFormats: [CaptureMode] = []
    var availableResolutions: [ResolutionOption] = []
    var selectedResolution: ResolutionOption? = nil
    var activeLens: Lens = .wide
    var flashMode: AVCaptureDevice.FlashMode = .off
    
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
    var shutterSpeeds: [CMTime] = []
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
    var minExposureBias: Float = -8.0
    var maxExposureBias: Float = 8.0
    var exposureDebounceTask: Task<Void, Never>?
    
    var isAdjustingManualFocus: Bool = false
    var isAutoFocus: Bool = true {
        didSet {
            if oldValue != isAutoFocus {
                peakingEnabledForAnalysis = !isAutoFocus
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
    nonisolated(unsafe) var lastLensPosition: Float = 1.0
    @ObservationIgnored
    nonisolated(unsafe) var peakingTemporalScores: [Float] = []
    @ObservationIgnored
    nonisolated(unsafe) var minimumFocusDistanceForAnalysis: Float = 0
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
    var isCapturing: Bool = false
    var showError: Bool = false
    var errorMessage: String = ""
    var liveISO: Float = 0
    var liveShutter: String = ""
    var liveWB: String = ""
    var liveFocus: String = ""
    var appView: AppView = .standard {
        didSet {
            if oldValue != appView && (appView == .settings || oldValue == .settings) {
                setupCameraControls()
            }
        }
    }
    var histogramData: [Float] = Array(repeating: 0, count: 256)
    var redHistogram: [Float] = Array(repeating: 0, count: 256)
    var greenHistogram: [Float] = Array(repeating: 0, count: 256)
    var blueHistogram: [Float] = Array(repeating: 0, count: 256)
    var waveformData: [Float] = []
    nonisolated static var wfCols: Int { WaveformConstants.wfCols }
    nonisolated static var wfRows: Int { WaveformConstants.wfRows }
    var analysisGridSize: CGSize = .zero
    var focusPeakingMask: [UInt8] = []
    var zebraMask: [UInt8] = []
    var clippingMask: [UInt8] = []
    @ObservationIgnored
    nonisolated(unsafe) var peakingEnabledForAnalysis: Bool = false
    @ObservationIgnored
    nonisolated(unsafe) var zebraEnabledForAnalysis: Bool = false
    @ObservationIgnored
    nonisolated(unsafe) var clippingEnabledForAnalysis: Bool = false
    @ObservationIgnored
    nonisolated(unsafe) var histogramModeForAnalysisSmall: HistogramMode = .luminance
    @ObservationIgnored
    nonisolated(unsafe) var histogramModeForAnalysisLarge: HistogramMode = .luminance
    
    // MARK: - Location
    let locationManager = CLLocationManager()
    var currentLocation: CLLocation?
    
    // MARK: - Computed properties
    var captureAspectRatio: CGFloat { 3.0 / 4.0 }
    
    var supportsManualFocus: Bool {
        device?.isLockingFocusWithCustomLensPositionSupported ?? false
    }
    
    var supportsFlash: Bool {
        guard device?.hasFlash == true else { return false }
        return !photoOutput.supportedFlashModes.isEmpty
    }
    
    var isFlashControlEnabled: Bool {
        supportsFlash && isAutoExposure
    }
    
    var isFormatPickerEnabled: Bool {
        isAutoExposure
    }
    
    var flashLabel: (systemImage: String, label: String) {
        switch flashMode {
            case .off: return ("flashlight.slash", "")
            case .auto: return ("flashlight.on.fill", "A")
            case .on: return ("flashlight.on.fill", "ON")
            @unknown default: return ("flashlight.slash", "?")
        }
    }
    
    var shouldShowFocusPeakingOverlay: Bool {
        !isAutoFocus
    }
    
    var showSimpleView: Bool {
        appView == .clean
    }
    
    // MARK: - Configure
    func configure() {
        loadSettings()
        
        if shouldGeotagLocation {
            locationManager.delegate = self
            locationManager.desiredAccuracy = kCLLocationAccuracyBest
            locationManager.requestWhenInUseAuthorization()
            locationManager.startUpdatingLocation()
        }
        
        switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized:
                sessionQueue.async { Task { @MainActor in self.setupSession() } }
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .video) { granted in
                    if granted { self.sessionQueue.async { Task { @MainActor in self.setupSession() } } }
                }
            default:
                errorMessage = "Camera access denied. Please enable in Settings."
                showError = true
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
        
        if session.canAddOutput(depthOutput) {
            session.addOutput(depthOutput)
            depthOutput.isFilteringEnabled = true
        }
        
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
        
        // Safely setup synchronizer or fallback
        let syncQueue = DispatchQueue(label: "com.blueberrycam.analysisQueue")
        if depthOutput.connection(with: .depthData) != nil && videoOutput.connection(with: .video) != nil {
            synchronizer = AVCaptureDataOutputSynchronizer(dataOutputs: [videoOutput, depthOutput])
            synchronizer?.setDelegate(self, queue: syncQueue)
        } else {
            // Fallback for devices without LiDAR or if depth is not available in current format
            videoOutput.setSampleBufferDelegate(self, queue: syncQueue)
        }
        
        Task.detached(priority: .userInitiated) {
            self.session.startRunning()
            Task { @MainActor in
                self.device = cam
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
        }
    }
    
    // MARK: - Formats & ranges
    func buildAvailableFormats() {
        let zoomBlocksRAW = (device?.videoZoomFactor ?? 1.0) > 1.0
        let isFront = activeLens.isFront
        
        var modes: [CaptureMode] = [.jpeg]
        if photoOutput.availablePhotoCodecTypes.contains(.hevc) {
            modes.append(.heif)
        }
        if !photoOutput.availableRawPhotoPixelFormatTypes.isEmpty && !zoomBlocksRAW {
            modes.append(.raw)
        }
        if availableFormats != modes {
            availableFormats = modes
        }
        
        // SMART SWITCH: Prioritize user's 'selectedFileFormat' preference if it's available.
        // This ensures if we fell back to JPEG because of a temporary state (like startup), 
        // we bounce back to RAW as soon as it becomes available.
        let targetMode: CaptureMode
        if modes.contains(selectedFileFormat) {
            targetMode = selectedFileFormat
        } else if modes.contains(captureMode) {
            targetMode = captureMode
        } else {
            targetMode = modes.contains(.heif) ? .heif : .jpeg
        }
        
        if captureMode != targetMode {
            captureMode = targetMode
        }
        
        let isCropLens = activeLens == .tele2x || activeLens == .tele8x
        
        let options: [ResolutionOption]
        if isFront {
            options = []
        } else if isCropLens {
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
            options = deduped.first.map { [$0] } ?? []
        } else {
            // Back optical lenses: use active format's supported dims, deduped by MP bucket
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
            let largest  = deduped.last
            if captureMode == .raw {
                // RAW is strictly 12MP in this app's pipeline (non-ProRAW)
                options = smallest.map { [$0] } ?? []
            } else if let s = smallest, let l = largest, s.id != l.id {
                options = [s, l]
            } else {
                options = deduped
            }
        }
        
        let sameOptions = availableResolutions.count == options.count &&
                          zip(availableResolutions, options).allSatisfy { $0.id == $1.id }
        
        if !sameOptions {
            availableResolutions = options
            // Options change (Format or Lens switch): re-apply resolution preference
            selectedResolution = preferredResolution == .max ? options.last : options.first
        } else if let current = selectedResolution, !options.contains(where: { $0.id == current.id }) {
            // Current selection became invalid
            selectedResolution = preferredResolution == .max ? options.last : options.first
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
        if secs >= 1.0 { return String(format: "%.1fs", secs) }
        return "1/\(Int(round(1.0 / secs)))"
    }
    
    // MARK: - Capture
    func capturePhoto() {
        withAnimation { isCapturing = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation { self.isCapturing = false }
        }
        
        exposureDebounceTask?.cancel()
        _pendingCaptureModeBox.value = captureMode
        
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
    
    private func applyFlashModeIfSupported(to settings: AVCapturePhotoSettings) {
        guard isAutoExposure else {
            settings.flashMode = .off
            return
        }
        guard supportsFlash else {
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
    
    private func loadSettings() {
        let defaults = UserDefaults.standard
        
        if let format = defaults.string(forKey: "selectedFileFormat"), let mode = CaptureMode(rawValue: format) {
            self.selectedFileFormat = mode
        }
        
        self.shouldGeotagLocation = defaults.bool(forKey: "shouldGeotagLocation")
        self.shouldShowGrid = defaults.object(forKey: "shouldShowGrid") as? Bool ?? true
        self.shouldShowLevel = defaults.object(forKey: "shouldShowLevel") as? Bool ?? true
        
        if let res = defaults.string(forKey: "preferredResolution"), let rPref = ResolutionPreference(rawValue: res) {
            self.preferredResolution = rPref
        }
        
        if let histSmall = defaults.string(forKey: "defaultHistogramSmall"), let hMode = HistogramMode(rawValue: histSmall) {
            self.defaultHistogramSmall = hMode
        }
        
        if let histLarge = defaults.string(forKey: "defaultHistogramLarge"), let hMode = HistogramMode(rawValue: histLarge) {
            self.defaultHistogramLarge = hMode
        }
    }
}
