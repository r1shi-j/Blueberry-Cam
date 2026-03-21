internal import AVFoundation
import LockedCameraCapture
import Photos
import UIKit

@MainActor @Observable
class LockedCameraModel: NSObject {
    // MARK: - Session
    nonisolated let session = AVCaptureSession()
    private var lockedSession: LockedCameraCaptureSession?
    
    var device: AVCaptureDevice?
    nonisolated let photoOutput = AVCapturePhotoOutput()
    nonisolated let videoOutput = AVCaptureVideoDataOutput()
    nonisolated let sessionQueue = DispatchQueue(label: "\(BundleIDs.appID).locked.sessionQueue")
    let _pendingCaptureModeBox = CaptureModeBox()
    nonisolated let _sessionContentURLBox = SessionURLBox()
    
    // MARK: - Capture format
    var captureMode: CaptureMode = .heif {
        didSet {
            if oldValue != captureMode {
                buildAvailableFormats()
            }
        }
    }
    private(set) var availableFormats: [CaptureMode] = []
    private(set) var enabledFormats: [CaptureMode] = []
    private(set) var availableResolutions: [ResolutionOption] = []
    private(set) var enabledResolutions: [ResolutionOption] = []
    var selectedResolution: ResolutionOption? = nil
    var activeLens: Lens = .wide
    var flashMode: AVCaptureDevice.FlashMode = .off
    var isMacroEnabled: Bool = false {
        didSet {
            if oldValue != isMacroEnabled {
                applyMacroMode()
                buildAvailableFormats()
            }
        }
    }
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
            }
        }
    }
    var iso: Float = 100
    private(set) var minISO: Float = 25
    private(set) var maxISO: Float = 6400
    private(set) var shutterSpeeds: [CMTime] = []
    var shutterIndex: Int = 0
    /// Denominator for in-app shutter slider (1 = 1s, 500 = 1/500s). 0 means use shutterIndex instead.
    var manualShutterDenominator: Int = 0
    var exposureBias: Float = 0.0
    private(set) var minExposureBias: Float = -8.0
    private(set) var maxExposureBias: Float = 8.0
    var exposureDebounceTask: Task<Void, Never>?
    
    var isAdjustingManualFocus: Bool = false
    var isAutoFocus: Bool = true {
        didSet {
            if oldValue != isAutoFocus, !isAutoFocus, let d = device {
                self.lensPosition = d.lensPosition
            }
        }
    }
    var lensPosition: Float = 1.0
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
    
    // MARK: - UI State
    private(set) var isCapturing: Bool = false
    var showError: Bool = false
    var errorMessage: String = ""
    var liveISO: Float = 0
    var liveShutter: String = ""
    var liveWB: String = ""
    var liveFocus: String = ""
    var lensSwitchCompletionCount: Int = 0
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
    
    var flashLabel: (systemImage: String, label: String) {
        switch flashMode {
            case .off: return ("flashlight.slash", "")
            case .auto: return ("flashlight.on.fill", "A")
            case .on: return ("flashlight.on.fill", "ON")
            @unknown default: return ("flashlight.slash", "?")
        }
    }
    
    // MARK: - Configure
    func configure(with lockedSession: LockedCameraCaptureSession) {
        self.lockedSession = lockedSession
        _sessionContentURLBox.value = lockedSession.sessionContentURL
        
        // Request photos authorization eagerly so it's ready before first capture
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        if status == .notDetermined {
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { _ in }
        }
        
        sessionQueue.async { Task { @MainActor in self.setupPipeline() } }
    }
    
    deinit {
        if let subjectAreaChangeObserver {
            NotificationCenter.default.removeObserver(subjectAreaChangeObserver)
        }
        focusAdjustmentObservation?.invalidate()
        lensPositionObservation?.invalidate()
    }
    
    private func setupPipeline() {
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
        
        videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "\(BundleIDs.appID).locked.videoQueue"))
        videoOutput.alwaysDiscardsLateVideoFrames = true
        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
        }
        
        configureSubjectAreaMonitoring(for: cam)
        
        for conn in [photoOutput.connection(with: .video),
                     videoOutput.connection(with: .video)].compactMap({ $0 }) {
            if conn.isVideoRotationAngleSupported(90) {
                conn.videoRotationAngle = 90
            }
        }
        
        session.commitConfiguration()
        
        // Setup rotation coordinator
        self.rotationCoordinator = AVCaptureDevice.RotationCoordinator(device: cam, previewLayer: nil)
        
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
        // We only enforce this logic if the device is ready.
        guard device != nil else { return }
        
        let zoomBlocksRAW = (device?.videoZoomFactor ?? 1.0) > 1.0
        
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
        } else {
            targetMode = modes.contains(.heif) ? .heif : .jpeg
        }
        
        if captureMode != targetMode {
            captureMode = targetMode
        }
        
        let isCropLens = activeLens == .tele2x || activeLens == .tele8x
        
        let visibleOptions: [ResolutionOption]
        
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
        
        let enabledOptions: [ResolutionOption]
        if isCropLens || isMacroEnabled || captureMode == .raw {
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
        
        if enabledOptions.isEmpty {
            selectedResolution = nil
        } else if let cur = selectedResolution, enabledOptions.contains(where: { $0.id == cur.id }) {
            
        } else {
            selectedResolution = enabledOptions.first
        }
    }
    
    func primeResolutionOptions(for lens: Lens, device: AVCaptureDevice) {
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
        let visibleOptions: [ResolutionOption]
        if let s = smallest, let l = largest, s.id != l.id {
            visibleOptions = [s, l]
        } else {
            visibleOptions = deduped
        }
        
        let isCropLens = lens == .tele2x || lens == .tele8x
        let enabledOptions: [ResolutionOption]
        if isCropLens || isMacroEnabled || captureMode == .raw {
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
            selectedResolution = enabledOptions.first
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
        
        // Always clamp iso to the new device's valid range (handles lens switches where minISO changes)
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
    
    private func updateCaptureOrientation() {
        guard session.isRunning, let photoConnection = photoOutput.connection(with: .video), photoConnection.isActive else { return }
        
        let (gx, gy, gz) = lastGravity
        
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
                degrees = 90
            } else {
                // Upside down portrait
                degrees = 270
            }
        } else {
            // Landscape orientation
            if gx > 0 {
                // Landscape right (home button on right)
                degrees = 180
            } else {
                // Landscape left (home button on left)
                degrees = 0
            }
        }
        
        // Update the photo connection rotation
        photoConnection.videoRotationAngle = degrees
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
