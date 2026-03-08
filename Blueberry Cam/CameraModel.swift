import AVFoundation
import SwiftUI
import Photos
import ImageIO
import UniformTypeIdentifiers
import Combine

@MainActor
class CameraModel: NSObject, ObservableObject {
    
    // MARK: - Session
    nonisolated let session = AVCaptureSession()
    private var device: AVCaptureDevice?
    nonisolated private let photoOutput = AVCapturePhotoOutput()
    nonisolated private let videoOutput = AVCaptureVideoDataOutput()
    nonisolated private let sessionQueue = DispatchQueue(label: "com.rawcam.sessionQueue")
    
    // MARK: - Capture format
    @Published var captureMode: CaptureMode = .raw
    @Published var availableFormats: [CaptureMode] = []
    
    // MARK: - Manual controls
    @Published var iso: Float = 100
    @Published var isAutoExposure: Bool = true
    @Published var showManualControls: Bool = false
    @Published var showHistogram: Bool = true
    @Published var lensPosition: Float = 1.0
    @Published var isAutoFocus: Bool = true
    private var exposureDebounceTask: Task<Void, Never>?
    
    var supportsManualFocus: Bool {
        device?.isLockingFocusWithCustomLensPositionSupported ?? false
    }
    
    @Published var minISO: Float = 25
    @Published var maxISO: Float = 6400
    @Published var shutterSpeeds: [CMTime] = []
    @Published var shutterIndex: Int = 0
    @Published var activeLens: Lens = .wide
    
    // MARK: - UI State
    @Published var isCapturing: Bool = false
    @Published var showSaveAlert: Bool = false
    @Published var showError: Bool = false
    @Published var saveMessage: String = ""
    @Published var errorMessage: String = ""
    @Published var histogramData: [Float] = Array(repeating: 0, count: 256)
    @Published var liveISO: Float = 0
    @Published var liveShutter: String = ""
    
    // Always portrait 3:4
    var captureAspectRatio: CGFloat { 3.0 / 4.0 }
    
    // MARK: - Configure
    func configure() {
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
        
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
        }
        
        videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "com.rawcam.videoQueue"))
        videoOutput.alwaysDiscardsLateVideoFrames = true
        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
        }
        
        session.commitConfiguration()
        
        Task.detached(priority: .userInitiated) {
            self.session.startRunning()
            Task { @MainActor in
                self.device = cam
                self.buildAvailableFormats()
                self.updateDeviceRanges()
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
            
            if !cam.isLockingFocusWithCustomLensPositionSupported {
                self.isAutoFocus = true
            }
        }}
    }
    
    // MARK: - Formats & ranges
    private func buildAvailableFormats() {
        let zoomBlocksRAW = (device?.videoZoomFactor ?? 1.0) > 1.0
        
        var modes: [CaptureMode] = [.jpeg]
        if !photoOutput.availableRawPhotoPixelFormatTypes.isEmpty && !zoomBlocksRAW {
            modes.append(.raw)
        }
        availableFormats = modes
        if !modes.contains(captureMode) { captureMode = .jpeg }
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
            1/1.6,    1/1.3,   1.0
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
        photoOutput.capturePhoto(with: buildPhotoSettings(), delegate: self)
    }
    
    private func buildPhotoSettings() -> AVCapturePhotoSettings {
        let zoomBlocksRAW = (device?.videoZoomFactor ?? 1.0) > 1.0
        
        if captureMode == .raw && !zoomBlocksRAW,
           let fmt = photoOutput.availableRawPhotoPixelFormatTypes.first(where: {
               !AVCapturePhotoOutput.isAppleProRAWPixelFormat($0)
           }) ?? photoOutput.availableRawPhotoPixelFormatTypes.first {
            let s = AVCapturePhotoSettings(rawPixelFormatType: fmt)
            s.maxPhotoDimensions = captureDimensions()
            return s
        }
        let s = AVCapturePhotoSettings()
        s.maxPhotoDimensions = captureDimensions()
        return s
    }
    
    private func captureDimensions() -> CMVideoDimensions {
        guard let d = device else { return photoOutput.maxPhotoDimensions }
        let outputMax = photoOutput.maxPhotoDimensions
        return d.activeFormat.supportedMaxPhotoDimensions
            .filter { $0.width <= outputMax.width && $0.height <= outputMax.height }
            .max { Int($0.width) * Int($0.height) < Int($1.width) * Int($1.height) }
        ?? outputMax
    }
    
    // MARK: - Manual Exposure
    func applyManualExposure() {
        exposureDebounceTask?.cancel()
        exposureDebounceTask = Task {
            try? await Task.sleep(nanoseconds: 50_000_000)
            guard !Task.isCancelled, let d = device, shutterSpeeds.indices.contains(shutterIndex) else { return }
            try? d.lockForConfiguration()
            d.setExposureModeCustom(duration: shutterSpeeds[shutterIndex], iso: iso, completionHandler: nil)
            d.unlockForConfiguration()
        }
    }
    
    func setAutoExposure() {
        guard let d = device else { return }
        try? d.lockForConfiguration()
        d.exposureMode = .continuousAutoExposure
        d.unlockForConfiguration()
    }
    
    // MARK: - Manual Focus
    func applyManualFocus() {
        guard let d = device else { return }
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
        try? d.lockForConfiguration()
        d.focusMode = .continuousAutoFocus
        d.unlockForConfiguration()
    }
    
    func toggleManualControls() { showManualControls.toggle() }
    func toggleHistogram()      { showHistogram.toggle() }
    
    // MARK: - Naming
    private func nextImageName() -> String {
        let key = "com.rawcam.imgCounter"
        let next = UserDefaults.standard.integer(forKey: key) + 1
        UserDefaults.standard.set(next, forKey: key)
        return String(format: "IMG_%04d", next)
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
        saveToPhotos(data: data, isDNG: photo.isRawPhoto)
    }
    
    private nonisolated func saveToPhotos(data: Data, isDNG: Bool) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                Task { @MainActor in self.errorMessage = "Photos access denied."; self.showError = true }
                return
            }
            
            if isDNG {
                let sem = DispatchSemaphore(value: 0)
                nonisolated(unsafe) var imgName = "IMG_0000"
                Task { @MainActor in
                    imgName = self.nextImageName()
                    sem.signal()
                }
                sem.wait()
                
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent(imgName)
                    .appendingPathExtension("dng")
                
                do { try data.write(to: url) } catch {
                    Task { @MainActor in
                        self.errorMessage = "Failed to write DNG: \(error.localizedDescription)"
                        self.showError = true
                    }
                    return
                }
                
                PHPhotoLibrary.shared().performChanges({
                    let req = PHAssetCreationRequest.forAsset()
                    let opts = PHAssetResourceCreationOptions()
                    opts.shouldMoveFile = true
                    req.addResource(with: .photo, fileURL: url, options: opts)
                }) { success, error in
                    try? FileManager.default.removeItem(at: url)
                    Task { @MainActor in
                        if success {
                            self.saveMessage = "RAW DNG saved to Photos."
                            self.showSaveAlert = true
                        } else {
                            self.errorMessage = error?.localizedDescription ?? "Unknown save error."
                            self.showError = true
                        }
                    }
                }
            } else {
                PHPhotoLibrary.shared().performChanges({
                    PHAssetCreationRequest.forAsset().addResource(with: .photo, data: data, options: nil)
                }) { success, error in
                    Task { @MainActor in
                        if success {
                            self.saveMessage = "JPEG saved to Photos."
                            self.showSaveAlert = true
                        } else {
                            self.errorMessage = error?.localizedDescription ?? "Unknown save error."
                            self.showError = true
                        }
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
            }
        }
        
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        
        let width       = CVPixelBufferGetWidth(pixelBuffer)
        let height      = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        guard let base  = CVPixelBufferGetBaseAddress(pixelBuffer) else { return }
        
        var hist  = [Float](repeating: 0, count: 256)
        var count: Float = 0
        let step  = 8
        
        for y in stride(from: 0, to: height, by: step) {
            let row = base.advanced(by: y * bytesPerRow).assumingMemoryBound(to: UInt8.self)
            for x in stride(from: 0, to: width * 4, by: step * 4) {
                let luma = Int(0.299 * Float(row[x + 2]) +
                               0.587 * Float(row[x + 1]) +
                               0.114 * Float(row[x]))
                hist[min(luma, 255)] += 1
                count += 1
            }
        }
        
        if count > 0 {
            let normalized = hist.map { $0 / count }
            Task { @MainActor in self.histogramData = normalized }
        }
    }
}

// MARK: - CaptureMode
enum CaptureMode: String, CaseIterable, Identifiable {
    case jpeg = "JPEG"
    case raw  = "RAW"
    var id: String { rawValue }
}

// MARK: - Lens
enum Lens: String, CaseIterable {
    case frontUltraWide, front, ultraWide, wide, tele2x, tele4x, tele8x
    
    var label: String {
        switch self {
            case .frontUltraWide: return "0.5"
            case .front:          return "SELF"
            case .ultraWide:      return "0.5"
            case .wide:           return "1"
            case .tele2x:         return "2"
            case .tele4x:         return "4"
            case .tele8x:         return "8"
        }
    }
    
    var isFront: Bool { self == .front || self == .frontUltraWide }
    
    var deviceType: AVCaptureDevice.DeviceType {
        switch self {
            case .frontUltraWide:      return .builtInUltraWideCamera
            case .front:               return .builtInWideAngleCamera
            case .ultraWide:           return .builtInUltraWideCamera
            case .wide, .tele2x:       return .builtInWideAngleCamera
            case .tele4x, .tele8x:     return .builtInTelephotoCamera
        }
    }
    
    var position: AVCaptureDevice.Position { isFront ? .front : .back }
    
    var zoomFactor: CGFloat {
        switch self {
            case .tele2x: return 2.0
            case .tele8x: return 2.0
            default:      return 1.0
        }
    }
}
