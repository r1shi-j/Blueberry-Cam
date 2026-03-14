internal import AVFoundation
import CoreLocation
import ImageIO
import Photos
import SwiftUI
import UniformTypeIdentifiers

@MainActor @Observable
class CameraModel: NSObject, AVCaptureSessionControlsDelegate {
    
    // MARK: - Session
    nonisolated let session = AVCaptureSession()
    private var device: AVCaptureDevice?
    nonisolated private let photoOutput = AVCapturePhotoOutput()
    nonisolated private let videoOutput = AVCaptureVideoDataOutput()
    nonisolated private let sessionQueue = DispatchQueue(label: "com.rawcam.sessionQueue")
    nonisolated private let _frameCounter = FrameCounter()
    private let _pendingCaptureModeBox = CaptureModeBox()
    
    // MARK: - Camera Control (iOS 18)
    private var cleanUIControl: AVCaptureIndexPicker?
    private var lensControl: AVCaptureIndexPicker?
    private var evControl: AVCaptureSlider?
    private var isoControl: AVCaptureSlider?
    private var ssControl: AVCaptureIndexPicker?
    private var focusControl: AVCaptureSlider?
    private var wbControl: AVCaptureSlider?
    /// Prevents Camera Control action callbacks from overwriting properties when we set ctrl.value programmatically
    private var isUpdatingHardwareControl = false
    
    // MARK: - Capture format
    var captureMode: CaptureMode = .raw {
        didSet {
            if oldValue != captureMode {
                buildAvailableFormats()
            }
        }
    }
    var availableFormats: [CaptureMode] = []
    var flashMode: AVCaptureDevice.FlashMode = .off
    
    // MARK: - Manual controls
    var iso: Float = 100 {
        didSet {
            if oldValue != iso {
                syncISOToHardware()
            }
        }
    }
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
    var showHistogram: Bool = false
    var showClipping: Bool = false
    var showZebraStripes: Bool = false
    var isAdjustingManualFocus: Bool = false
    var lensPosition: Float = 1.0 {
        didSet {
            if oldValue != lensPosition {
                syncFocusToHardware()
            }
        }
    }
    var isAutoFocus: Bool = true {
        didSet {
            if oldValue != isAutoFocus {
                if !isAutoFocus, let d = device {
                    self.lensPosition = d.lensPosition
                }
                updateCameraControlsMode()
            }
        }
    }
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
    var exposureBias: Float = 0.0 {
        didSet {
            if oldValue != exposureBias {
                syncEVToHardware()
            }
        }
    }
    var minExposureBias: Float = -8.0
    var maxExposureBias: Float = 8.0
    private var exposureDebounceTask: Task<Void, Never>?
    private var focusPeakingHoldTask: Task<Void, Never>?
    
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
    var activeLens: Lens = .wide
    
    // MARK: - UI State
    var isCapturing: Bool = false
    var showError: Bool = false
    var errorMessage: String = ""
    var histogramData: [Float] = Array(repeating: 0, count: 256)
    var redHistogram: [Float] = Array(repeating: 0, count: 256)
    var greenHistogram: [Float] = Array(repeating: 0, count: 256)
    var blueHistogram: [Float] = Array(repeating: 0, count: 256)
    var waveformData: [Float] = []
    nonisolated static var wfCols: Int { WaveformConstants.wfCols }
    nonisolated static var wfRows: Int { WaveformConstants.wfRows }
    var histogramSize: HistogramSize = .small
    var histogramMode: HistogramMode = .luminance
    var analysisGridSize: CGSize = .zero
    var focusPeakingMask: [UInt8] = []
    var zebraMask: [UInt8] = []
    var clippingMask: [UInt8] = []
    var liveISO: Float = 0
    var liveShutter: String = ""
    var liveWB: String = ""
    var liveFocus: String = ""
    var isCleanUI: Bool = false
    
    // MARK: - Location
    private let locationManager = CLLocationManager()
    private var currentLocation: CLLocation?
    var shouldEmbedLocationData: Bool = false
    
    var locationLabel: String {
        shouldEmbedLocationData ? "location.fill" : "location.slash.fill"
    }
    
    var captureAspectRatio: CGFloat { 3.0 / 4.0 }
    
    var shouldShowFocusPeakingOverlay: Bool {
        !isAutoFocus
    }
    
    // MARK: - Resolution
    var availableResolutions: [ResolutionOption] = []
    var selectedResolution: ResolutionOption? = nil
    
    // MARK: - Configure
    func configure() {
        if shouldEmbedLocationData {
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
        
        videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "com.rawcam.videoQueue"))
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
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
    
    // MARK: - Lens switching
    func switchLens(to lens: Lens) {
        guard lens != activeLens else { return }
        activeLens = lens
        
        sessionQueue.async { Task { @MainActor in
            self.session.beginConfiguration()
            for input in self.session.inputs { self.session.removeInput(input) }
            
            guard let cam = AVCaptureDevice.default(lens.deviceType, for: .video, position: lens.position),
                  let input = try? AVCaptureDeviceInput(device: cam),
                  self.session.canAddInput(input) else {
                self.session.commitConfiguration()
                return
            }
            self.session.addInput(input)
            self.device = cam
            
            // Crop zoom for 2x / 8x back lenses
            if lens.zoomFactor > 1.0 {
                try? cam.lockForConfiguration()
                cam.videoZoomFactor = lens.zoomFactor
                cam.unlockForConfiguration()
            }
            
            // Portrait rotation + mirror
            let isFront = lens.isFront
            let rotationAngle: CGFloat = isFront ? 0 : 90
            for conn in [self.photoOutput.connection(with: .video),
                         self.videoOutput.connection(with: .video)].compactMap({ $0 }) {
                if conn.isVideoRotationAngleSupported(rotationAngle) {
                    conn.videoRotationAngle = rotationAngle
                }
                conn.isVideoMirrored = isFront
            }
            
            self.session.commitConfiguration()
            
            // Set output max to largest the active format supports
            if let largest = cam.activeFormat.supportedMaxPhotoDimensions.max(by: {
                Int($0.width) * Int($0.height) < Int($1.width) * Int($1.height)
            }) {
                self.photoOutput.maxPhotoDimensions = largest
            }
            
            self.buildAvailableFormats()
            self.updateDeviceRanges()
            self.normalizeFlashModeForCurrentDevice()
            self.enforceExposureModeConstraints()
            // Recreate camera controls with new device's ISO/SS bounds
            self.setupCameraControls()
            
            if !cam.isLockingFocusWithCustomLensPositionSupported {
                self.isAutoFocus = true
            }
        }}
    }
    
    // MARK: - Formats & ranges
    private func buildAvailableFormats() {
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
        if !modes.contains(captureMode) {
            let nextMode: CaptureMode = modes.contains(.heif) ? .heif : .jpeg
            if captureMode != nextMode {
                captureMode = nextMode
            }
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
            // RAW locks to 12MP only (48MP RAW not supported by AVFoundation)
            // JPEG/HEIF allows both
            let smallest = deduped.first
            let largest  = deduped.last
            if captureMode == .raw {
                options = smallest.map { [$0] } ?? []
            } else if let s = smallest, let l = largest, s.id != l.id {
                options = [s, l]
            } else {
                options = deduped
            }
        }
        
        if availableResolutions != options {
            availableResolutions = options
        }
        
        // Preserve selection if still valid, otherwise default to highest
        if options.isEmpty {
            if selectedResolution != nil { selectedResolution = nil }
        } else if let current = selectedResolution, options.contains(where: { $0.id == current.id }) {
            // keep
        } else {
            if selectedResolution != options.last {
                selectedResolution = options.last
            }
        }
    }
    
    private func normalizeFlashModeForCurrentDevice() {
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
    
    private func enforceExposureModeConstraints() {
        if !isAutoExposure {
            flashMode = .off
            if captureMode != .raw {
                captureMode = .raw
            }
        }
    }
    
    private func updateDeviceRanges() {
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
    
    func cycleFlashMode() {
        guard supportsFlash, isAutoExposure else {
            flashMode = .off
            return
        }
        
        let supported = photoOutput.supportedFlashModes
        let order: [AVCaptureDevice.FlashMode] = [.off, .auto, .on]
        let currentIndex = order.firstIndex(of: flashMode) ?? 0
        
        for offset in 1...order.count {
            let candidate = order[(currentIndex + offset) % order.count]
            if supported.contains(candidate) {
                flashMode = candidate
                return
            }
        }
        
        flashMode = .off
    }
    
    func toggleLocationGeotag() {
        shouldEmbedLocationData.toggle()
        if shouldEmbedLocationData {
            locationManager.delegate = self
            locationManager.desiredAccuracy = kCLLocationAccuracyBest
            locationManager.requestWhenInUseAuthorization()
            locationManager.startUpdatingLocation()
        } else {
            locationManager.stopUpdatingLocation()
            locationManager.delegate = nil
            currentLocation = nil
        }
    }
    
    func selectResolution(_ opt: ResolutionOption) {
        selectedResolution = opt
        // No format switching needed — selectedResolution is used directly in captureDimensions()
        // The active format already supports this dim (it came from activeFormat.supportedMaxPhotoDimensions)
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
    
    // MARK: - Manual Exposure
    func applyManualExposure() {
        if manualShutterDenominator > 0 {
            applyManualExposureWithDenominator(manualShutterDenominator)
            return
        }
        exposureDebounceTask?.cancel()
        exposureDebounceTask = Task {
            try? await Task.sleep(nanoseconds: 50_000_000)
            guard !Task.isCancelled, let d = device, shutterSpeeds.indices.contains(shutterIndex) else { return }
            try? d.lockForConfiguration()
            let clampedISO = max(d.activeFormat.minISO, min(d.activeFormat.maxISO, iso))
            d.setExposureModeCustom(duration: shutterSpeeds[shutterIndex], iso: clampedISO, completionHandler: nil)
            d.unlockForConfiguration()
        }
    }
    
    func applyManualExposureWithDenominator(_ denom: Int) {
        let duration = CMTimeMake(value: 1, timescale: CMTimeScale(max(1, denom)))
        exposureDebounceTask?.cancel()
        exposureDebounceTask = Task {
            try? await Task.sleep(nanoseconds: 50_000_000)
            guard !Task.isCancelled, let d = device else { return }
            try? d.lockForConfiguration()
            let clampedISO = max(d.activeFormat.minISO, min(d.activeFormat.maxISO, iso))
            d.setExposureModeCustom(duration: duration, iso: clampedISO, completionHandler: nil)
            d.unlockForConfiguration()
        }
    }
    
    // MARK: - White Balance
    func applyManualWhiteBalance() {
        guard let d = device else { return }
        try? d.lockForConfiguration()
        applyManualWhiteBalanceLocked()
        d.unlockForConfiguration()
    }
    
    private func applyManualWhiteBalanceLocked() {
        guard let d = device else { return }
        // Expanded bounding from 2000K (very cool/blue) to 10000K (very warm/orange)
        let kelvin = max(2000, min(10000, whiteBalanceTargetKelvin))
        let tempAndTint = AVCaptureDevice.WhiteBalanceTemperatureAndTintValues(temperature: kelvin, tint: 0)
        let rawGains = d.deviceWhiteBalanceGains(for: tempAndTint)
        
        let maxGain = d.maxWhiteBalanceGain
        let clampedGains = AVCaptureDevice.WhiteBalanceGains(
            redGain: max(1.0, min(maxGain, rawGains.redGain)),
            greenGain: max(1.0, min(maxGain, rawGains.greenGain)),
            blueGain: max(1.0, min(maxGain, rawGains.blueGain))
        )
        
        d.setWhiteBalanceModeLocked(with: clampedGains, completionHandler: nil)
    }
    
    func setAutoWhiteBalance() {
        guard let d = device else { return }
        try? d.lockForConfiguration()
        if d.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
            d.whiteBalanceMode = .continuousAutoWhiteBalance
        }
        d.unlockForConfiguration()
    }
    
    func setAutoExposure() {
        guard let d = device else { return }
        try? d.lockForConfiguration()
        d.exposureMode = .continuousAutoExposure
        d.unlockForConfiguration()
        applyExposureBias()
        
        sessionQueue.async { Task { @MainActor in
            self.updateCameraControlsMode()
        }}
    }
    
    func applyExposureBias() {
        guard let d = device else { return }
        let clamped = max(minExposureBias, min(maxExposureBias, exposureBias))
        try? d.lockForConfiguration()
        d.setExposureTargetBias(clamped, completionHandler: nil)
        d.unlockForConfiguration()
    }
    
    // MARK: - Manual Focus
    func applyManualFocus() {
        guard let d = device else { return }
        beginManualFocusAdjustment()
        guard d.isLockingFocusWithCustomLensPositionSupported else {
            try? d.lockForConfiguration()
            d.focusMode = .continuousAutoFocus
            d.unlockForConfiguration()
            isAutoFocus = true
            return
        }
        try? d.lockForConfiguration()
        d.setFocusModeLocked(lensPosition: lensPosition) { _ in }
        d.unlockForConfiguration()
    }
    
    func setAutoFocus() {
        guard let d = device else { return }
        endManualFocusAdjustment()
        try? d.lockForConfiguration()
        d.focusMode = .continuousAutoFocus
        d.unlockForConfiguration()
    }
    
    func beginManualFocusAdjustment() {
        guard !isAutoFocus else { return }
        focusPeakingHoldTask?.cancel()
        isAdjustingManualFocus = true
    }
    
    func endManualFocusAdjustment() {
        focusPeakingHoldTask?.cancel()
        focusPeakingHoldTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }
            self.isAdjustingManualFocus = false
        }
    }
    
    func resetControl(for control: ManualControl) {
        switch control {
            case .ev:
                if isAutoExposure {
                    exposureBias = 0.0
                    applyExposureBias()
                }
            case .iso:
                isAutoExposure = true
            case .ss:
                isAutoExposure = true
            case .f:
                isAutoFocus = true
                setAutoFocus()
            case .wb:
                isAutoWhiteBalance = true
        }
    }
    
    func toggleHistogram() { showHistogram.toggle() }
    func toggleClipping() { showClipping.toggle() }
    func toggleZebraStripes() { showZebraStripes.toggle() }
    func cycleHistogramMode() {
        switch (histogramSize, histogramMode) {
            case (.small, .luminance):
                histogramMode = .color
            case (.small, .color):
                histogramMode = .waveform
            case (.small, .waveform):
                histogramMode = .parade
            case (.small, .parade):
                histogramSize = .large
                histogramMode = .luminance
            case (.large, .luminance):
                histogramMode = .color
            case (.large, .color):
                histogramMode = .waveform
            case (.large, .waveform):
                histogramMode = .parade
            case (.large, .parade):
                histogramSize = .small
                histogramMode = .luminance
        }
    }
    
    private func setCleanUI(to value: Bool) {
        isCleanUI = value
    }
}

// MARK: - AVCapturePhotoCaptureDelegate
extension CameraModel: AVCapturePhotoCaptureDelegate {
    
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput,
                                 didFinishProcessingPhoto photo: AVCapturePhoto,
                                 error: Error?) {
        if let error {
            Task { @MainActor in self.errorMessage = error.localizedDescription; self.showError = true }
            return
        }
        guard let data = photo.fileDataRepresentation() else {
            Task { @MainActor in self.errorMessage = "Failed to get photo data."; self.showError = true }
            return
        }
        let isHeif = !photo.isRawPhoto && self._pendingCaptureModeBox.value == .heif
        Task {
            let loc = await MainActor.run { self.currentLocation }
            self.saveToPhotos(data: data, location: loc, isDNG: photo.isRawPhoto, isHEIF: isHeif)
        }
    }
    
    private nonisolated func saveToPhotos(data: Data, location: CLLocation?, isDNG: Bool, isHEIF: Bool = false) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                Task { @MainActor in self.errorMessage = "Photos access denied."; self.showError = true }
                return
            }
            
            // 1. Resolve the "Blueberry Cam" album, creating it only when necessary.
            let albumID = resolveAlbumID()
            let album = albumID.flatMap {
                PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [$0], options: nil).firstObject
            }
            
            PHPhotoLibrary.shared().performChanges({
                let opts = PHAssetResourceCreationOptions()
                opts.uniformTypeIdentifier = isDNG ? "com.adobe.raw-image" : (isHEIF ? "public.heic" : "public.jpeg")
                let req = PHAssetCreationRequest.forAsset()
                if let loc = location {
                    req.location = loc
                }
                req.addResource(with: .photo, data: data, options: opts)
                
                // 2. Add the new asset to the album
                if let album, let placeholder = req.placeholderForCreatedAsset {
                    let albumReq = PHAssetCollectionChangeRequest(for: album)
                    albumReq?.addAssets([placeholder] as NSArray)
                }
            }) { success, error in
                Task { @MainActor in
                    if !success {
                        self.errorMessage = error?.localizedDescription ?? "Unknown save error."
                        self.showError = true
                    }
                }
            }
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
extension CameraModel: AVCaptureVideoDataOutputSampleBufferDelegate {
    
    nonisolated func captureOutput(_ output: AVCaptureOutput,
                                   didOutput sampleBuffer: CMSampleBuffer,
                                   from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        Task { @MainActor in
            if let d = self.device {
                self.liveISO = d.iso
                self.liveShutter = Self.formatShutter(d.exposureDuration)
                let tnt = d.temperatureAndTintValues(for: d.deviceWhiteBalanceGains)
                self.liveWB = "\(Int(tnt.temperature))K"
                self.liveFocus = String(format: "%.2f", d.lensPosition)
            }
        }
        
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        
        let pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        
        var hist  = [Float](repeating: 0, count: 256)
        var rHist = [Float](repeating: 0, count: 256)
        var gHist = [Float](repeating: 0, count: 256)
        var bHist = [Float](repeating: 0, count: 256)
        var count: Float = 0
        let step = 8
        let sampleWidth  = max(1, width  / step)
        let sampleHeight = max(1, height / step)
        let sampleCount  = sampleWidth * sampleHeight
        var lumaGrid = [Float](repeating: 0, count: sampleCount)
        var zebra    = [UInt8](repeating: 0, count: sampleCount)
        
        // Waveform accumulators: X = horizontal position, Y = brightness level
        let wfCols = CameraModel.wfCols
        let wfRows = CameraModel.wfRows
        var wfRSum  = [Float](repeating: 0, count: wfCols * wfRows)
        var wfGSum  = [Float](repeating: 0, count: wfCols * wfRows)
        var wfBSum  = [Float](repeating: 0, count: wfCols * wfRows)
        var wfCount = [Float](repeating: 0, count: wfCols * wfRows)
        
        let readPixel: (Int, Int) -> (r: Float, g: Float, b: Float, luma: Float)
        if pixelFormat == kCVPixelFormatType_32BGRA {
            let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
            guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return }
            readPixel = { x, y in
                let row = base.advanced(by: y * bytesPerRow).assumingMemoryBound(to: UInt8.self)
                let o = x * 4
                let b = Float(row[o]); let g = Float(row[o + 1]); let r = Float(row[o + 2])
                return (r, g, b, 0.299 * r + 0.587 * g + 0.114 * b)
            }
        } else if CVPixelBufferIsPlanar(pixelBuffer), CVPixelBufferGetPlaneCount(pixelBuffer) > 0 {
            let yW  = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
            let yH  = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
            let yBR = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
            guard let yBase = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0) else { return }
            readPixel = { x, y in
                let row = yBase.advanced(by: min(yH - 1, y) * yBR).assumingMemoryBound(to: UInt8.self)
                let l = Float(row[min(yW - 1, x)])
                return (l, l, l, l)   // planar YCbCr — luma only, treat as neutral grey
            }
        } else {
            return
        }
        
        for sy in 0..<sampleHeight {
            let py = min(height - 1, sy * step)
            for sx in 0..<sampleWidth {
                let px = min(width - 1, sx * step)
                let (r, g, b, luma) = readPixel(px, py)
                let idx = sy * sampleWidth + sx
                lumaGrid[idx] = luma
                zebra[idx] = luma >= 235 ? 1 : 0
                hist[min(Int(luma), 255)]  += 1
                rHist[min(Int(r), 255)] += 1
                gHist[min(Int(g), 255)] += 1
                bHist[min(Int(b), 255)] += 1
                count += 1
                
                // Map to waveform cell: col = horizontal position, row = brightness
                let wfCol = min(wfCols - 1, px * wfCols / max(width, 1))
                let wfRow = min(wfRows - 1, Int(luma) * wfRows / 256)
                let wfIdx = wfRow * wfCols + wfCol
                wfRSum[wfIdx]  += r / 255.0
                wfGSum[wfIdx]  += g / 255.0
                wfBSum[wfIdx]  += b / 255.0
                wfCount[wfIdx] += 1
            }
        }
        
        var peaking = [UInt8](repeating: 0, count: sampleCount)
        if sampleWidth > 4 && sampleHeight > 4 {
            var edgeMap = [Float](repeating: 0, count: sampleCount)
            var edgeSum: Float = 0
            var edgeSumSquares: Float = 0
            var edgeCount: Float = 0
            var edgeMax: Float = 0
            
            // Sobel edge magnitude gives a stronger, cleaner focus signal than a simple 2-axis diff.
            for y in 1..<(sampleHeight - 1) {
                for x in 1..<(sampleWidth - 1) {
                    let i = y * sampleWidth + x
                    let tl = lumaGrid[(y - 1) * sampleWidth + (x - 1)]
                    let tc = lumaGrid[(y - 1) * sampleWidth + x]
                    let tr = lumaGrid[(y - 1) * sampleWidth + (x + 1)]
                    let ml = lumaGrid[y * sampleWidth + (x - 1)]
                    let mr = lumaGrid[y * sampleWidth + (x + 1)]
                    let bl = lumaGrid[(y + 1) * sampleWidth + (x - 1)]
                    let bc = lumaGrid[(y + 1) * sampleWidth + x]
                    let br = lumaGrid[(y + 1) * sampleWidth + (x + 1)]
                    
                    let gx = -tl - (2 * ml) - bl + tr + (2 * mr) + br
                    let gy = -tl - (2 * tc) - tr + bl + (2 * bc) + br
                    let edge = sqrt((gx * gx) + (gy * gy))
                    edgeMap[i] = edge
                    edgeSum += edge
                    edgeSumSquares += edge * edge
                    edgeCount += 1
                    if edge > edgeMax { edgeMax = edge }
                }
            }
            
            let edgeMean = edgeCount > 0 ? edgeSum / edgeCount : 0
            let variance = edgeCount > 0 ? max(0, (edgeSumSquares / edgeCount) - (edgeMean * edgeMean)) : 0
            let edgeSigma = sqrt(variance)
            let adaptiveThreshold = max(115, edgeMean + (4.2 * edgeSigma))
            let threshold = max(adaptiveThreshold, edgeMax * 0.68)
            
            // Keep only local maxima and sparsify points to achieve precise "dot" peaking.
            for y in 2..<(sampleHeight - 2) {
                for x in 2..<(sampleWidth - 2) {
                    let i = y * sampleWidth + x
                    let edge = edgeMap[i]
                    guard edge >= threshold else { continue }
                    guard lumaGrid[i] > 28 else { continue }
                    
                    let left = edgeMap[i - 1]
                    let right = edgeMap[i + 1]
                    let up = edgeMap[i - sampleWidth]
                    let down = edgeMap[i + sampleWidth]
                    let upLeft = edgeMap[i - sampleWidth - 1]
                    let upRight = edgeMap[i - sampleWidth + 1]
                    let downLeft = edgeMap[i + sampleWidth - 1]
                    let downRight = edgeMap[i + sampleWidth + 1]
                    
                    let isLocalMaximum = edge >= left &&
                    edge >= right &&
                    edge >= up &&
                    edge >= down &&
                    edge >= upLeft &&
                    edge >= upRight &&
                    edge >= downLeft &&
                    edge >= downRight
                    
                    if isLocalMaximum {
                        peaking[i] = 1
                    }
                }
            }
            
            // Remove isolated speckles; keep only clustered peaks so out-of-focus scenes
            // don't show random noise dots.
            var clustered = [UInt8](repeating: 0, count: sampleCount)
            for y in 2..<(sampleHeight - 2) {
                for x in 2..<(sampleWidth - 2) {
                    let i = y * sampleWidth + x
                    guard peaking[i] == 1 else { continue }
                    
                    var neighbors = 0
                    for ny in (y - 1)...(y + 1) {
                        for nx in (x - 1)...(x + 1) {
                            if nx == x && ny == y { continue }
                            if peaking[ny * sampleWidth + nx] == 1 {
                                neighbors += 1
                            }
                        }
                    }
                    
                    if neighbors >= 2 {
                        clustered[i] = 1
                    }
                }
            }
            peaking = clustered
        }
        
        let normalizedHistogram: [Float]? = count > 0 ? hist.map  { $0 / count } : nil
        let normR = count > 0 ? rHist.map { $0 / count } : nil
        let normG = count > 0 ? gHist.map { $0 / count } : nil
        let normB = count > 0 ? bHist.map { $0 / count } : nil
        
        // Build RGBN waveform: per-cell avg colour + per-COLUMN normalised density.
        // Normalising per column (not globally) means every column lights up regardless
        // of how many pixels mapped there — gives a continuous oscilloscope-style trace.
        var colMax = [Float](repeating: 0, count: wfCols)
        for col in 0..<wfCols {
            for row in 0..<wfRows {
                let n = wfCount[row * wfCols + col]
                if n > colMax[col] { colMax[col] = n }
            }
        }
        var wfRGBN = [Float](repeating: 0, count: wfCols * wfRows * 4)
        for col in 0..<wfCols {
            let cMax = colMax[col]
            guard cMax > 0 else { continue }
            for row in 0..<wfRows {
                let i = row * wfCols + col
                let n = wfCount[i]
                guard n > 0 else { continue }
                wfRGBN[i * 4] = wfRSum[i] / n   // avg r (0–1)
                wfRGBN[i * 4 + 1] = wfGSum[i] / n   // avg g (0–1)
                wfRGBN[i * 4 + 2] = wfBSum[i] / n   // avg b (0–1)
                                                    // density relative to the busiest row in this column — smooth falloff
                wfRGBN[i * 4 + 3] = min(1, (n / cMax) * 1.4)
            }
        }
        
        let analysisSize  = CGSize(width: sampleWidth, height: sampleHeight)
        let peakingMask   = peaking
        let zebraMask     = zebra
        let capturedWfRGBN = wfRGBN   // local copy so Swift 6 is happy crossing isolation boundary
        
        Task { @MainActor in
            if let normalizedHistogram { self.histogramData  = normalizedHistogram }
            if let normR { self.redHistogram   = normR }
            if let normG { self.greenHistogram = normG }
            if let normB { self.blueHistogram  = normB }
            self.waveformData = capturedWfRGBN
            self.analysisGridSize = analysisSize
            self.focusPeakingMask = peakingMask
            self.zebraMask = zebraMask
        }
    }
}

// MARK: - Camera Control Setup
extension CameraModel {
    private func setupCameraControls() {
        // Surgical removal to prevent duplicates
        if let c = cleanUIControl { session.removeControl(c); cleanUIControl = nil }
        if let l = lensControl { session.removeControl(l); lensControl = nil }
        if let e = evControl { session.removeControl(e); evControl = nil }
        if let i = isoControl { session.removeControl(i); isoControl = nil }
        if let s = ssControl { session.removeControl(s); ssControl = nil }
        if let f = focusControl { session.removeControl(f); focusControl = nil }
        if let wb = wbControl { session.removeControl(wb); wbControl = nil }
        
        // Final wipe of any orphans just in case
        session.controls.forEach { session.removeControl($0) }
        
        // Clean UI Picker
        let titles = ["On", "Off"]
        let values = [true, false]
        let cUI = AVCaptureIndexPicker("Clean UI", symbolName: "square.arrowtriangle.4.outward", localizedIndexTitles: titles)
        cUI.setActionQueue(.main) { [weak self] index in
            guard let self else { return }
            guard index >= 0 else { return }
            self.setCleanUI(to: values[index])
        }
        cUI.selectedIndex = self.isCleanUI ? 0 : 1
        self.cleanUIControl = cUI
        session.addControl(cUI)
        
        // Lens Picker
        let availableLenses = Lens.allCases.filter { len in
            AVCaptureDevice.default(len.deviceType, for: .video, position: len.position) != nil
        }
        if !availableLenses.isEmpty {
            let titles = availableLenses.map { "\($0.label)x" }
            let picker = AVCaptureIndexPicker("Cameras", symbolName: "camera.aperture", localizedIndexTitles: titles)
            picker.setActionQueue(.main) { [weak self] index in
                guard let self else { return }
                guard index >= 0 && index < availableLenses.count else { return }
                self.switchLens(to: availableLenses[index])
            }
            if let activeIndex = availableLenses.firstIndex(of: activeLens) {
                picker.selectedIndex = activeIndex
            }
            self.lensControl = picker
            session.addControl(picker)
        }
        
        // EV Slider
        let ev = AVCaptureSlider("Exposure", symbolName: "plusminus", in: -4.0...4.0, step: 0.1)
        ev.prominentValues = [-4.0, -3.5, -3.0, -2.5, -2.0, -1.5, -1.0, -0.5, 0.0, 0.5, 1.0, 1.5, 2.0, 2.5, 3.0, 3.5, 4.0]
        ev.localizedValueFormat = "%@ EV"
        // Seed to current EV value
        let clampedEV = max(-4.0, min(4.0, exposureBias))
        ev.value = round(clampedEV * 10) / 10.0
        ev.setActionQueue(.main) { [weak self] value in
            guard let self, !self.isUpdatingHardwareControl else { return }
            if abs(self.exposureBias - value) > 0.01 {
                self.exposureBias = value
                self.applyExposureBias()
            }
        }
        self.evControl = ev
        session.addControl(ev)
        
        // ISO Slider — use step-safe bounds (ceil min to next 50, floor max to prev 50)
        // This ensures min/max are exact multiples of the step so AVCaptureSlider never throws
        let isoSliderMin = ceil(minISO / 50.0) * 50.0
        let isoSliderMax = floor(maxISO / 50.0) * 50.0
        guard isoSliderMin <= isoSliderMax else { return }
        let isoSlider = AVCaptureSlider("ISO", symbolName: "film", in: isoSliderMin...isoSliderMax, step: 50.0)
        isoSlider.prominentValues = [100, 200, 400, 800, 1600, 3200, 6400]
        // Seed the slider to the current iso (clamped & snapped)
        let seedISO = max(isoSliderMin, min(isoSliderMax, round(iso / 50.0) * 50.0))
        isoSlider.value = seedISO
        isoSlider.setActionQueue(.main) { [weak self] value in
            guard let self, !self.isUpdatingHardwareControl else { return }
            if abs(self.iso - value) > 1.0 {
                self.iso = value
                self.applyManualExposure()
            }
        }
        self.isoControl = isoSlider
        session.addControl(isoSlider)
        
        // Shutter Speed Index Picker — index 0 is fastest (left), max index is slowest (right)
        // This solves both the negative sign formatting limitations of AVCaptureSlider
        // and ensures we only select valid stops for the current camera.
        if shutterSpeeds.count > 0 {
            let ssPicker = AVCaptureIndexPicker("Shutter Speed", symbolName: "lightspectrum.horizontal", numberOfIndexes: shutterSpeeds.count) { [weak self] index in
                guard let self else { return "" }
                guard index >= 0 && index < self.shutterSpeeds.count else { return "" }
                return Self.formatShutter(self.shutterSpeeds[index])
            }
            // Seed to current shutterIndex
            let clampedIdx = max(0, min(shutterSpeeds.count - 1, shutterIndex))
            ssPicker.selectedIndex = clampedIdx
            ssPicker.setActionQueue(.main) { [weak self] index in
                guard let self, !self.isUpdatingHardwareControl else { return }
                if self.shutterIndex != index {
                    self.shutterIndex = index
                    self.manualShutterDenominator = 0 // clear manual denominator
                    self.applyManualExposure()
                }
            }
            self.ssControl = ssPicker
            session.addControl(ssPicker)
        }
        
        // Focus Slider
        // Trick: slider runs 0...100 so iOS formats it as whole numbers, and we prefix with "0."
        let focus = AVCaptureSlider("Focus", symbolName: "scope", in: 0...100, step: 1)
        focus.localizedValueFormat = "0.%@"
        focus.value = Float(lensPosition * 100.0)
        focus.setActionQueue(.main) { [weak self] value in
            guard let self, !self.isUpdatingHardwareControl else { return }
            let normalized = value / 100.0
            if abs(self.lensPosition - normalized) > 0.01 {
                self.lensPosition = normalized
                self.applyManualFocus()
            }
        }
        self.focusControl = focus
        session.addControl(focus)
        
        // White Balance Slider
        let wb = AVCaptureSlider("White Balance", symbolName: "thermometer.sun.fill", in: 2000...10000, step: 100)
        wb.localizedValueFormat = "%@K"
        wb.value = whiteBalanceTargetKelvin
        wb.setActionQueue(.main) { [weak self] value in
            guard let self, !self.isUpdatingHardwareControl else { return }
            if abs(self.whiteBalanceTargetKelvin - value) > 10 {
                self.whiteBalanceTargetKelvin = value
                // Setting whiteBalanceTargetKelvin triggers applyManualWhiteBalance() via didSet if manual WB
            }
        }
        self.wbControl = wb
        session.addControl(wb)
        
        updateCameraControlsMode()
    }
    
    private func updateCameraControlsMode() {
        evControl?.isEnabled = isAutoExposure
        isoControl?.isEnabled = !isAutoExposure
        ssControl?.isEnabled = !isAutoExposure
        focusControl?.isEnabled = !isAutoFocus
        wbControl?.isEnabled = !isAutoWhiteBalance
    }
    
    // MARK: - Bidirectional Sync Helpers
    private func syncEVToHardware() {
        guard let ctrl = evControl else { return }
        let clamped = max(-4.0, min(4.0, exposureBias))
        let snapped = round(clamped * 10.0) / 10.0
        if abs(ctrl.value - snapped) > 0.01 {
            isUpdatingHardwareControl = true
            ctrl.value = snapped
            isUpdatingHardwareControl = false
        }
    }
    
    private func syncISOToHardware() {
        guard let ctrl = isoControl else { return }
        let raw = max(minISO, min(maxISO, iso))
        let snapped = round(raw / 50.0) * 50.0
        let safeMin = ceil(minISO / 50.0) * 50.0
        let safeMax = floor(maxISO / 50.0) * 50.0
        let final = max(safeMin, min(safeMax, snapped))
        if abs(ctrl.value - final) > 0.1 {
            isUpdatingHardwareControl = true
            ctrl.value = final
            isUpdatingHardwareControl = false
        }
    }
    
    private func syncShutterToHardware() {
        guard let ctrl = ssControl, shutterSpeeds.indices.contains(shutterIndex) else { return }
        if ctrl.selectedIndex != shutterIndex {
            isUpdatingHardwareControl = true
            ctrl.selectedIndex = shutterIndex
            isUpdatingHardwareControl = false
        }
    }
    
    private func syncFocusToHardware() {
        guard let ctrl = focusControl else { return }
        let clamped = max(0.0, min(1.0, lensPosition))
        let sliderValue = Float(clamped * 100.0)
        if abs(ctrl.value - sliderValue) > 1.0 {
            isUpdatingHardwareControl = true
            ctrl.value = sliderValue
            isUpdatingHardwareControl = false
        }
    }
    
    private func syncWBToHardware() {
        guard let ctrl = wbControl else { return }
        let clamped = max(2000, min(10000, whiteBalanceTargetKelvin))
        if abs(ctrl.value - clamped) > 1.0 {
            isUpdatingHardwareControl = true
            ctrl.value = clamped
            isUpdatingHardwareControl = false
        }
    }
}

// MARK: - Camera Control Delegate
extension CameraModel {
    func sessionControlsDidBecomeActive(_ session: AVCaptureSession) {
        // Called when the controls of an AVCaptureSession instance become active and are available for interaction.
    }
    
    func sessionControlsWillEnterFullscreenAppearance(_ session: AVCaptureSession) {
        // Called when the controls will enter a fullscreen appearance.
    }
    
    func sessionControlsWillExitFullscreenAppearance(_ session: AVCaptureSession) {
        // Called when the controls will exit a fullscreen appearance.
    }
    
    func sessionControlsDidBecomeInactive(_ session: AVCaptureSession) {
        // Called when the controls become inactive.
    }
}

// MARK: - CLLocationManagerDelegate
extension CameraModel: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        currentLocation = locations.last
    }
}
