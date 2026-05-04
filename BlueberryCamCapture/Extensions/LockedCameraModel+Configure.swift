internal import AVFoundation
import Foundation
import LockedCameraCapture

extension LockedCameraModel {
    func configure(with lockedSession: LockedCameraCaptureSession) {
        _sessionContentURLBox.value = lockedSession.sessionContentURL
        
        setupSession()
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
    
    private func setupSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            
            self.session.beginConfiguration()
            self.session.sessionPreset = .photo
            
            guard let initialCamera = Lens.initialCaptureDevice(),
                  let input = try? AVCaptureDeviceInput(device: initialCamera.device),
                  self.session.canAddInput(input) else {
                self.session.commitConfiguration()
                return
            }
            
            let initialLens = initialCamera.lens
            let cam = initialCamera.device
            self.session.addInput(input)
            
            if self.session.canAddOutput(self.photoOutput) {
                self.session.addOutput(self.photoOutput)
            }
            
            self.videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "\(BundleIDs.appID).locked.videoQueue"))
            self.videoOutput.alwaysDiscardsLateVideoFrames = true
            if self.session.canAddOutput(self.videoOutput) {
                self.session.addOutput(self.videoOutput)
            }
            
            // Keep analysis output orientation aligned with preview from first launch.
            let rotationAngle = Lens.rotationAngle(for: cam, lens: initialLens)
            let isMirrored = Lens.isMirrored(cam, lens: initialLens)
            for conn in [photoOutput.connection(with: .video),
                         videoOutput.connection(with: .video)].compactMap({ $0 }) {
                if conn.isVideoRotationAngleSupported(rotationAngle) {
                    conn.videoRotationAngle = rotationAngle
                }
                conn.isVideoMirrored = isMirrored
            }
            
            self.session.commitConfiguration()
            
            if let largest = cam.activeFormat.supportedMaxPhotoDimensions.max(by: {
                Int($0.width) * Int($0.height) < Int($1.width) * Int($1.height)
            }) {
                self.photoOutput.maxPhotoDimensions = largest
            }
            
            Task { @MainActor in
                self.activeLens = initialLens
                self.device = cam
                self.configureSubjectAreaMonitoring(for: cam)
                self.buildAvailableFormats()
                self.updateDeviceRanges()
                self.normalizeFlashModeForCurrentDevice()
                self.enforceExposureModeConstraints()
                self.startSession()
            }
        }
    }
}
