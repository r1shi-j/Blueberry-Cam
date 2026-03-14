internal import AVFoundation
import LockedCameraCapture
import Photos
import SwiftUI

// MARK: - LockedCameraModel
//
// A trimmed version of CameraModel for use inside the LockedCameraCaptureExtension.
//
// Key differences from the main app's CameraModel:
//   - Does NOT create an AVCaptureSession — uses the one provided by LockedCameraCaptureSession
//   - No location / CLLocationManager (network/location unavailable in extension sandbox)
//   - No Camera Controls API (AVCaptureSessionControlsDelegate — not available when locked)
//   - All capture, manual exposure, histogram, peaking, and saving code is identical
//
// The provided `LockedCameraCaptureSession` wraps a real AVCaptureSession.
// You add inputs and outputs to it exactly as in the main app.

@MainActor @Observable
class LockedCameraModel: NSObject {
    
    // MARK: - Session
    // We create our own AVCaptureSession — LockedCameraCaptureSession only provides
    // sessionContentURL (file storage) and openApplication(); it does NOT wrap AVCaptureSession.
    nonisolated let session = AVCaptureSession()
    private var lockedSession: LockedCameraCaptureSession?
    
    private var device: AVCaptureDevice?
    nonisolated private let photoOutput = AVCapturePhotoOutput()
    nonisolated private let videoOutput = AVCaptureVideoDataOutput()
    nonisolated private let sessionQueue = DispatchQueue(label: "com.blueberrycam.locked.sessionQueue")
    nonisolated private let _frameCounter = FrameCounter()
    private let _pendingCaptureModeBox = CaptureModeBox()
    nonisolated private let _sessionContentURLBox = SessionURLBox()
    
    // MARK: - Capture format
    var captureMode: CaptureMode = .raw {
        didSet { if oldValue != captureMode { buildAvailableFormats() } }
    }
    var availableFormats: [CaptureMode] = []
    var flashMode: AVCaptureDevice.FlashMode = .off
    
    // MARK: - Manual controls
    var iso: Float = 100
    var isAutoExposure: Bool = true {
        didSet {
            if oldValue != isAutoExposure {
                if !isAutoExposure, let d = device {
                    let snapped = round(d.iso / 50.0) * 50.0
                    self.iso = max(minISO, min(maxISO, snapped))
                    if let idx = shutterSpeeds.indices.min(by: {
                        abs(CMTimeGetSeconds(shutterSpeeds[$0]) - CMTimeGetSeconds(d.exposureDuration)) <
                            abs(CMTimeGetSeconds(shutterSpeeds[$1]) - CMTimeGetSeconds(d.exposureDuration))
                    }) { shutterIndex = idx }
                }
                enforceExposureModeConstraints()
            }
        }
    }
    var isAutoFocus: Bool = true {
        didSet {
            if oldValue != isAutoFocus, !isAutoFocus, let d = device {
                self.lensPosition = d.lensPosition
            }
        }
    }
    var lensPosition: Float = 1.0
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
    var exposureBias: Float = 0.0
    var minExposureBias: Float = -8.0
    var maxExposureBias: Float = 8.0
    var isAdjustingManualFocus: Bool = false
    private var focusPeakingHoldTask: Task<Void, Never>?
    var minISO: Float = 25
    var maxISO: Float = 6400
    var shutterSpeeds: [CMTime] = []
    var shutterIndex: Int = 0
    var manualShutterDenominator: Int = 0
    private var exposureDebounceTask: Task<Void, Never>?
    
    var supportsManualFocus: Bool { device?.isLockingFocusWithCustomLensPositionSupported ?? false }
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
    
    // MARK: - UI State
    var activeLens: Lens = .wide
    var isCapturing: Bool = false
    var showError: Bool = false
    var errorMessage: String = ""
    var showManualControls: Bool = false
    var liveISO: Float = 0
    var liveShutter: String = ""
    var liveWB: String = ""
    var liveFocus: String = ""
    
    var availableResolutions: [ResolutionOption] = []
    var selectedResolution: ResolutionOption? = nil
    
    var captureAspectRatio: CGFloat { 3.0 / 4.0 }
    
    // MARK: - Configure
    // Called from LockedCaptureView.onAppear with the system-provided session.
    func configure(with lockedSession: LockedCameraCaptureSession) {
        self.lockedSession = lockedSession
        _sessionContentURLBox.value = lockedSession.sessionContentURL
        sessionQueue.async { Task { @MainActor in self.setupPipeline() } }
    }
    
    private func setupPipeline() {
        session.beginConfiguration()
        session.sessionPreset = .photo
        
        // Find and add the default back wide camera
        guard let cam = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: cam),
              session.canAddInput(input) else {
            session.commitConfiguration(); return
        }
        session.addInput(input)
        
        // Photo output
        if session.canAddOutput(photoOutput) { session.addOutput(photoOutput) }
        
        // Video output for live analysis (histogram, peaking, zebra)
        videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "com.blueberrycam.locked.videoQueue"))
        videoOutput.alwaysDiscardsLateVideoFrames = true
//        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        if session.canAddOutput(videoOutput) { session.addOutput(videoOutput) }
        
        // Portrait rotation
        for conn in [photoOutput.connection(with: .video),
                     videoOutput.connection(with: .video)].compactMap({ $0 }) {
            if conn.isVideoRotationAngleSupported(90) { conn.videoRotationAngle = 90 }
        }
        
        session.commitConfiguration()
        
        Task.detached(priority: .userInitiated) {
            self.session.startRunning()
            Task { @MainActor in
                self.device = cam
                if let largest = cam.activeFormat.supportedMaxPhotoDimensions.max(by: {
                    Int($0.width) * Int($0.height) < Int($1.width) * Int($1.height)
                }) { self.photoOutput.maxPhotoDimensions = largest }
                self.buildAvailableFormats()
                self.updateDeviceRanges()
                self.normalizeFlashModeForCurrentDevice()
                self.enforceExposureModeConstraints()
            }
        }
    }
    
    // MARK: - Lens switching (back cameras only — lock screen context)
    func switchLens(to lens: Lens) {
        guard lens != activeLens, !lens.isFront else { return }
        activeLens = lens
        sessionQueue.async { Task { @MainActor in
            self.session.beginConfiguration()
            for input in self.session.inputs { self.session.removeInput(input) }
            guard let cam = AVCaptureDevice.default(lens.deviceType, for: .video, position: .back),
                  let input = try? AVCaptureDeviceInput(device: cam),
                  self.session.canAddInput(input) else {
                self.session.commitConfiguration(); return
            }
            self.session.addInput(input)
            self.device = cam
            if lens.zoomFactor > 1.0 {
                try? cam.lockForConfiguration()
                cam.videoZoomFactor = lens.zoomFactor
                cam.unlockForConfiguration()
            }
            for conn in [self.photoOutput.connection(with: .video),
                         self.videoOutput.connection(with: .video)].compactMap({ $0 }) {
                if conn.isVideoRotationAngleSupported(90) { conn.videoRotationAngle = 90 }
            }
            self.session.commitConfiguration()
            if let largest = cam.activeFormat.supportedMaxPhotoDimensions.max(by: {
                Int($0.width) * Int($0.height) < Int($1.width) * Int($1.height)
            }) { self.photoOutput.maxPhotoDimensions = largest }
            self.buildAvailableFormats()
            self.updateDeviceRanges()
            self.normalizeFlashModeForCurrentDevice()
            self.enforceExposureModeConstraints()
        }}
    }
    
    private func normalizeFlashModeForCurrentDevice() {
        guard supportsFlash else { flashMode = .off; return }
        if !photoOutput.supportedFlashModes.contains(flashMode) {
            flashMode = photoOutput.supportedFlashModes.contains(.auto) ? .auto : .off
        }
        if !isAutoExposure { flashMode = .off }
    }
    
    private func enforceExposureModeConstraints() {
        if !isAutoExposure {
            flashMode = .off
            if captureMode != .raw { captureMode = .raw }
        }
    }
    
    // MARK: - Formats & ranges (identical logic to main app)
    private func buildAvailableFormats() {
        let zoomBlocksRAW = (device?.videoZoomFactor ?? 1.0) > 1.0
        var modes: [CaptureMode] = [.jpeg]
        if photoOutput.availablePhotoCodecTypes.contains(.hevc) { modes.append(.heif) }
        if !photoOutput.availableRawPhotoPixelFormatTypes.isEmpty && !zoomBlocksRAW { modes.append(.raw) }
        if availableFormats != modes { availableFormats = modes }
        if !modes.contains(captureMode) { captureMode = modes.contains(.heif) ? .heif : .jpeg }
        
        let isCropLens = activeLens == .tele2x || activeLens == .tele8x
        let outputMax = photoOutput.maxPhotoDimensions
        let allDims = (device?.activeFormat.supportedMaxPhotoDimensions ?? [])
            .filter { $0.width <= outputMax.width && $0.height <= outputMax.height }
            .sorted { Int($0.width) * Int($0.height) < Int($1.width) * Int($1.height) }
        var deduped: [ResolutionOption] = []
        for dim in allDims {
            let opt = ResolutionOption(width: dim.width, height: dim.height)
            if !deduped.contains(where: { abs($0.id - opt.id) < 2_000_000 }) { deduped.append(opt) }
        }
        let options: [ResolutionOption]
        if isCropLens { options = deduped.first.map { [$0] } ?? [] }
        else if captureMode == .raw { options = deduped.first.map { [$0] } ?? [] }
        else if let s = deduped.first, let l = deduped.last, s.id != l.id { options = [s, l] }
        else { options = deduped }
        if availableResolutions != options { availableResolutions = options }
        if options.isEmpty { selectedResolution = nil }
        else if let cur = selectedResolution, options.contains(where: { $0.id == cur.id }) { }
        else { selectedResolution = options.last }
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
    }
    
    private func generateShutterStops(for device: AVCaptureDevice) -> [CMTime] {
        let fmt = device.activeFormat
        let minSecs = CMTimeGetSeconds(fmt.minExposureDuration)
        let maxSecs = CMTimeGetSeconds(fmt.maxExposureDuration)
        let ts = fmt.minExposureDuration.timescale
        let stops: [Double] = [
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
        return stops.filter { $0 >= minSecs - 1e-9 && $0 <= maxSecs + 1e-9 }
            .map { CMTimeMakeWithSeconds($0, preferredTimescale: ts) }
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { withAnimation { self.isCapturing = false } }
        exposureDebounceTask?.cancel()
        _pendingCaptureModeBox.value = captureMode
        if !isAutoExposure, let d = device {
            let duration: CMTime = shutterSpeeds.indices.contains(shutterIndex)
            ? shutterSpeeds[shutterIndex]
            : CMTimeMake(value: 1, timescale: 60)
            let isoVal = max(d.activeFormat.minISO, min(d.activeFormat.maxISO, iso))
            try? d.lockForConfiguration()
            d.setExposureModeCustom(duration: duration, iso: isoVal) { [weak self] _ in
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
        let dims = selectedResolution?.dimensions ?? photoOutput.maxPhotoDimensions
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
                }; fallthrough
            case .heif:
                if photoOutput.availablePhotoCodecTypes.contains(.hevc) {
                    let s = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
                    s.maxPhotoDimensions = dims
                    applyFlashModeIfSupported(to: s)
                    return s
                }; fallthrough
            case .jpeg:
                let s = AVCapturePhotoSettings()
                s.maxPhotoDimensions = dims
                applyFlashModeIfSupported(to: s)
                return s
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
    
    // MARK: - Exposure
    func setAutoExposure() {
        guard let d = device else { return }
        try? d.lockForConfiguration()
        d.exposureMode = .continuousAutoExposure
        d.unlockForConfiguration()
        applyExposureBias()
    }
    
    func applyManualExposure() {
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
    
    func applyExposureBias() {
        guard let d = device else { return }
        let clamped = max(minExposureBias, min(maxExposureBias, exposureBias))
        try? d.lockForConfiguration()
        d.setExposureTargetBias(clamped, completionHandler: nil)
        d.unlockForConfiguration()
    }
    
    // MARK: - Focus
    func setAutoFocus() {
        guard let d = device else { return }
        try? d.lockForConfiguration()
        d.focusMode = .continuousAutoFocus
        d.unlockForConfiguration()
    }
    
    func applyManualFocus() {
        guard let d = device, d.isLockingFocusWithCustomLensPositionSupported else { return }
        try? d.lockForConfiguration()
        d.setFocusModeLocked(lensPosition: lensPosition) { _ in }
        d.unlockForConfiguration()
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
    
    // MARK: - Reset
    func resetControl(for control: ManualControl) {
        switch control {
            case .ev:
                if isAutoExposure {
                    exposureBias = 0.0
                    applyExposureBias()
                }
            case .iso:
                isAutoExposure = true
                setAutoExposure()
            case .ss:
                isAutoExposure = true
                setAutoExposure()
            case .f:
                isAutoFocus = true
                setAutoFocus()
            case .wb:
                isAutoWhiteBalance = true
        }
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
    
    // MARK: - Toggles
    func toggleManualControls() { showManualControls.toggle() }
    func cycleFlashMode() {
        guard supportsFlash else { flashMode = .off; return }
        let order: [AVCaptureDevice.FlashMode] = [.off, .auto, .on]
        let supported = photoOutput.supportedFlashModes
        let current = order.firstIndex(of: flashMode) ?? 0
        for offset in 1...order.count {
            let candidate = order[(current + offset) % order.count]
            if supported.contains(candidate) { flashMode = candidate; return }
        }
        flashMode = .off
    }
    
    func selectResolution(_ opt: ResolutionOption) { selectedResolution = opt }
}

// MARK: - AVCapturePhotoCaptureDelegate
extension LockedCameraModel: AVCapturePhotoCaptureDelegate {
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
        let isHeif = !photo.isRawPhoto && _pendingCaptureModeBox.value == .heif
        let url = _sessionContentURLBox.value  // read via box, same pattern as CaptureModeBox
        saveToSessionDirectory(data: data, isDNG: photo.isRawPhoto, isHEIF: isHeif, sessionURL: url)
    }
    
    private nonisolated func saveToSessionDirectory(data: Data, isDNG: Bool, isHEIF: Bool, sessionURL: URL?) {
        guard let sessionURL else {
            saveDirectlyToPhotos(data: data, isDNG: isDNG, isHEIF: isHEIF, sessionURL: sessionURL)
            return
        }
        
        let ext = isDNG ? "dng" : (isHEIF ? "heic" : "jpg")
        let filename = "IMG_\(Int(Date().timeIntervalSince1970)).\(ext)"
        let fileURL = sessionURL.appendingPathComponent(filename)
        
        do {
            try data.write(to: fileURL)
            // Also save immediately to camera roll so photo is available straight away
            saveDirectlyToPhotos(data: data, isDNG: isDNG, isHEIF: isHEIF, sessionURL: sessionURL)
        } catch {
            Task { @MainActor in self.errorMessage = error.localizedDescription; self.showError = true }
        }
    }
    
    private nonisolated func saveDirectlyToPhotos(data: Data, isDNG: Bool, isHEIF: Bool, sessionURL: URL?) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                Task { @MainActor in self.errorMessage = "Photos access denied."; self.showError = true }
                return
            }
            var placeholderID: String?
            PHPhotoLibrary.shared().performChanges({
                let opts = PHAssetResourceCreationOptions()
                opts.uniformTypeIdentifier = isDNG ? "com.adobe.raw-image" : (isHEIF ? "public.heic" : "public.jpeg")
                let req = PHAssetCreationRequest.forAsset()
                req.addResource(with: .photo, data: data, options: opts)
                placeholderID = req.placeholderForCreatedAsset?.localIdentifier
            }) { success, error in
                if success, let id = placeholderID, let sessionURL {
                    // Write the localIdentifier to a manifest file in the session dir
                    // so the main app can find the exact asset later
                    let manifestURL = sessionURL.appendingPathComponent("manifest.txt")
                    var existing = (try? String(contentsOf: manifestURL, encoding: .utf8)) ?? ""
                    existing += id + "\n"
                    try? existing.write(to: manifestURL, atomically: true, encoding: .utf8)
                }
                if let error {
                    Task { @MainActor in self.errorMessage = error.localizedDescription; self.showError = true }
                }
            }
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
// Identical pixel-reading and analysis logic to the main CameraModel.
extension LockedCameraModel: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(_ output: AVCaptureOutput,
                                   didOutput sampleBuffer: CMSampleBuffer,
                                   from connection: AVCaptureConnection) {
        Task { @MainActor in
            if let d = self.device {
                self.liveISO = d.iso
                self.liveShutter = Self.formatShutter(d.exposureDuration)
                let tnt = d.temperatureAndTintValues(for: d.deviceWhiteBalanceGains)
                self.liveWB = "\(Int(tnt.temperature))K"
                self.liveFocus = String(format: "%.2f", d.lensPosition)
            }
        }
    }
}
