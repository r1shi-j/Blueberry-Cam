import AVFoundation
import SwiftUI
import Photos
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
    
    // Ranges — populated from device at runtime
    @Published var minISO: Float = 25
    @Published var maxISO: Float = 6400
    @Published var shutterSpeeds: [CMTime] = []
    @Published var shutterIndex: Int = 0
    
    // MARK: - UI State
    @Published var isCapturing: Bool = false
    @Published var showSaveAlert: Bool = false
    @Published var showError: Bool = false
    @Published var saveMessage: String = ""
    @Published var errorMessage: String = ""
    @Published var histogramData: [Float] = Array(repeating: 0, count: 256)
    @Published var liveISO: Float = 0
    @Published var liveShutter: String = ""
    
    // MARK: - Configure
    func configure() {
        checkPermissions()
    }
    
    private func checkPermissions() {
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
    
    // Runs on sessionQueue (not MainActor)
    private func setupSession() {
        session.beginConfiguration()
        session.sessionPreset = .photo
        
        guard let cam = bestCamera(),
              let input = try? AVCaptureDeviceInput(device: cam),
              session.canAddInput(input) else {
            session.commitConfiguration()
            return
        }
        session.addInput(input)
        
        // Lock to best full-res format before adding outputs
        if let best = bestPhotoFormat(for: cam) {
            try? cam.lockForConfiguration()
            cam.activeFormat = best
            cam.unlockForConfiguration()
        }
        
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
        }
        
        Task { @MainActor in
            self.device = cam
            self.buildAvailableFormats()
            self.updateDeviceRanges()
        }
    }
    
    private func bestCamera() -> AVCaptureDevice? {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
        ?? AVCaptureDevice.default(for: .video)
    }
    
    // Full native sensor resolution, highest ISO ceiling, P3 color preferred
    private func bestPhotoFormat(for device: AVCaptureDevice) -> AVCaptureDevice.Format? {
        device.formats
            .filter {
                let d = $0.formatDescription.dimensions
                return d.width >= 4000 && d.height >= 3000
            }
            .max {
                if $0.maxISO != $1.maxISO { return $0.maxISO < $1.maxISO }
                return !$0.supportedColorSpaces.contains(.P3_D65) &&
                $1.supportedColorSpaces.contains(.P3_D65)
            }
    }
    
    private func buildAvailableFormats() {
        var modes: [CaptureMode] = [.jpeg]
        if !photoOutput.availableRawPhotoPixelFormatTypes.isEmpty {
            modes.append(.raw)
        }
        availableFormats = modes
        captureMode = modes.contains(.raw) ? .raw : .jpeg
    }
    
    private func updateDeviceRanges() {
        guard let d = device else { return }
        minISO = d.activeFormat.minISO
        maxISO = d.activeFormat.maxISO
        
        let stops = generateShutterStops(for: d)
        shutterSpeeds = stops
        
        // Default to stop nearest 1/60s
        let target = 1.0 / 60.0
        shutterIndex = stops.indices.min(by: {
            abs(CMTimeGetSeconds(stops[$0]) - target) <
                abs(CMTimeGetSeconds(stops[$1]) - target)
        }) ?? 0
        
        liveISO = d.iso
        liveShutter = Self.formatShutter(d.exposureDuration)
    }
    
    private func generateShutterStops(for device: AVCaptureDevice) -> [CMTime] {
        let fmt = device.activeFormat
        let minSecs = CMTimeGetSeconds(fmt.minExposureDuration)
        let maxSecs = CMTimeGetSeconds(fmt.maxExposureDuration)
        let timescale = fmt.minExposureDuration.timescale
        
        // 1/3-stop grid from 1/100000s to 1s — filtered to what the device actually supports
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
    
    // Used by live overlay, manual controls label, and anywhere else needing a display string
    static func formatShutter(_ time: CMTime) -> String {
        let secs = CMTimeGetSeconds(time)
        guard secs.isFinite && secs > 0 else { return "—" }
        if secs >= 1.0 { return String(format: "%.1fs", secs) }
        return "1/\(Int(round(1.0 / secs)))"
    }
    
    // MARK: - Capture
    func capturePhoto() {
        // Flash animation on main actor
        withAnimation { isCapturing = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation { self.isCapturing = false }
        }
        let settings = buildPhotoSettings()
        photoOutput.capturePhoto(with: settings, delegate: self)
    }
    
    private func buildPhotoSettings() -> AVCapturePhotoSettings {
        if captureMode == .raw,
           let fmt = photoOutput.availableRawPhotoPixelFormatTypes.first(where: {
               !AVCapturePhotoOutput.isAppleProRAWPixelFormat($0)
           }) ?? photoOutput.availableRawPhotoPixelFormatTypes.first {
            let s = AVCapturePhotoSettings(rawPixelFormatType: fmt)
            if let dims = bestCaptureDimensions() { s.maxPhotoDimensions = dims }
            return s
        }
        let s = AVCapturePhotoSettings()
        if let dims = bestCaptureDimensions() { s.maxPhotoDimensions = dims }
        return s
    }
    
    // Largest pixel dimensions both the format and output agree on
    private func bestCaptureDimensions() -> CMVideoDimensions? {
        guard let d = device else { return nil }
        let maxOut = photoOutput.maxPhotoDimensions
        return d.activeFormat.supportedMaxPhotoDimensions
            .filter { $0.width <= maxOut.width && $0.height <= maxOut.height }
            .max { Int($0.width) * Int($0.height) < Int($1.width) * Int($1.height) }
        ?? maxOut
    }
    
    // MARK: - Manual Exposure
    func applyManualExposure() {
        guard let d = device, shutterSpeeds.indices.contains(shutterIndex) else { return }
        try? d.lockForConfiguration()
        d.setExposureModeCustom(duration: shutterSpeeds[shutterIndex], iso: iso, completionHandler: nil)
        d.unlockForConfiguration()
    }
    
    func setAutoExposure() {
        guard let d = device else { return }
        try? d.lockForConfiguration()
        d.exposureMode = .continuousAutoExposure
        d.unlockForConfiguration()
    }
    
    func toggleManualControls() { showManualControls.toggle() }
    func toggleHistogram()      { showHistogram.toggle() }
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
    
    // DNG must be saved via a file URL — passing raw DNG Data causes PHPhotosErrorDomain 3302
    private nonisolated func saveToPhotos(data: Data, isDNG: Bool) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                Task { @MainActor in
                    self.errorMessage = "Photos access denied."
                    self.showError = true
                }
                return
            }
            PHPhotoLibrary.shared().performChanges({
                let req = PHAssetCreationRequest.forAsset()
                let opts = PHAssetResourceCreationOptions()
                opts.uniformTypeIdentifier = isDNG ? "com.adobe.raw-image" : "public.jpeg"
                req.addResource(with: isDNG ? .photo : .photo, data: data, options: opts)
            }) { success, error in
                Task { @MainActor in
                    if success {
                        self.saveMessage = isDNG ? "RAW DNG saved to Photos." : "JPEG saved to Photos."
                        self.showSaveAlert = true
                    } else {
                        self.errorMessage = error?.localizedDescription ?? "Unknown error saving photo."
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
