internal import AVFoundation
import CoreGraphics
import Foundation
import SwiftUI

extension CameraModel {
    private nonisolated var dualCameraCoverLeadInDuration: Duration { .milliseconds(90) }
    private nonisolated var dualCameraPreviewDetachDelay: TimeInterval { 0.12 }
    
    var previewSession: AVCaptureSession {
        if isDualCameraEnabled, let dualSession {
            return dualSession
        }
        
        return session
    }
    
    var activeCaptureSession: AVCaptureSession {
        previewSession
    }
    
    var mainPreviewRotationAngle: CGFloat {
        guard let device else { return 0 }
        return Lens.rotationAngle(for: device, lens: activeLens)
    }
    
    var isMainPreviewMirrored: Bool {
        guard let device else { return false }
        return Lens.isMirrored(device, lens: activeLens)
    }
    
    var pipPreviewRotationAngle: CGFloat {
        guard let secondaryDevice, let secondaryLens else { return 0 }
        return Lens.rotationAngle(for: secondaryDevice, lens: secondaryLens)
    }
    
    var dualCameraPipAspectRatio: CGFloat {
        captureAspectRatio
    }
    
    var shouldShowDualCameraTransitionCurtain: Bool {
        isDualCameraTransitionCoverVisible || isConfiguringDualCamera || isDetachingPreviewForReconfiguration || isDualCameraPreviewSettling
    }
    
    var isPipPreviewMirrored: Bool {
        guard let secondaryDevice, let secondaryLens else { return false }
        return Lens.isMirrored(secondaryDevice, lens: secondaryLens)
    }
    
    var supportsDualCamera: Bool {
        guard AVCaptureMultiCamSession.isMultiCamSupported,
              dualSession != nil,
              !ProcessInfo.processInfo.isiOSAppOnMac else { return false }
        return Lens.wide.captureDevice() != nil
        && (Lens.frontUltraWide.captureDevice() != nil || Lens.front.captureDevice() != nil)
    }
    
    func toggleDualCameraMode() {
        if isDualCameraEnabled {
            disableDualCamera()
        } else {
            enableDualCamera()
        }
    }
    
    func enableDualCamera() {
        guard supportsDualCamera else {
            errorMessage = "Dual camera is not supported on this device."
            showError = true
            return
        }
        
        guard beginDualCameraPreviewTransition() else { return }
        let coverLeadInDuration = dualCameraCoverLeadInDuration
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: coverLeadInDuration)
            guard let self else { return }
            let requestedLens = activeLens.isFront ? activeLens : switchableLensForDualCamera(activeLens)
            let mainLens = canUseDualCamera(mainLens: requestedLens) ? requestedLens : .wide
            configureDualCamera(mainLens: mainLens, transitionStarted: true)
        }
    }
    
    func disableDualCamera() {
        guard isDualCameraEnabled || isConfiguringDualCamera else { return }
        guard beginDualCameraPreviewTransition() else { return }
        let lens = activeLens
        let coverLeadInDuration = dualCameraCoverLeadInDuration
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: coverLeadInDuration)
            self?.configureSingleCamera(lens: lens, transitionStarted: true)
        }
    }
    
    func swapDualCameras() {
        guard isDualCameraEnabled,
              let secondaryLens else { return }
        guard beginDualCameraPreviewTransition() else { return }
        let coverLeadInDuration = dualCameraCoverLeadInDuration
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: coverLeadInDuration)
            self?.configureDualCamera(mainLens: secondaryLens, transitionStarted: true)
        }
    }
    
    func switchDualMainLens(to lens: Lens) {
        guard isDualCameraEnabled else { return }
        let lens = switchableLensForDualCamera(lens)
        guard lens.isFront == activeLens.isFront,
              lens != activeLens else { return }
        guard beginDualCameraPreviewTransition() else { return }
        let coverLeadInDuration = dualCameraCoverLeadInDuration
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: coverLeadInDuration)
            self?.configureDualCamera(mainLens: lens, transitionStarted: true)
        }
    }
    
    func moveDualCameraPip(by translation: CGSize, predictedTranslation: CGSize) {
        let threshold: CGFloat = 24
        let hasDeliberateDrag = abs(translation.width) >= threshold || abs(translation.height) >= threshold
        let snapTranslation = hasDeliberateDrag ? translation : predictedTranslation
        let nextPlacement = dualCameraPipPlacement.moved(by: snapTranslation, threshold: threshold)
        guard nextPlacement != dualCameraPipPlacement else { return }
        dualCameraPipPlacement = nextPlacement
    }
    
    @discardableResult
    private func beginDualCameraPreviewTransition() -> Bool {
        guard !isConfiguringDualCamera else { return false }
        dualCameraPreviewSettlingTask?.cancel()
        dualCameraPreviewSettlingTask = nil
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            isDualCameraPreviewSettling = true
            isConfiguringDualCamera = true
            isSwitchingLens = true
        }
        withAnimation(.easeOut(duration: 0.08)) {
            isDualCameraTransitionCoverVisible = true
        }
        return true
    }
    
    private func beginDualCameraPreviewTeardown() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            isDetachingPreviewForReconfiguration = true
            mainPreviewDeviceUniqueID = nil
            pipPreviewDeviceUniqueID = nil
        }
    }
    
    private func finishDualCameraPreviewTransition() {
        dualCameraPreviewSettlingTask?.cancel()
        dualCameraPreviewSettlingTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(240))
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.16)) {
                    self?.isDualCameraTransitionCoverVisible = false
                    self?.isDualCameraPreviewSettling = false
                }
                self?.dualCameraPreviewSettlingTask = nil
            } catch {
                return
            }
        }
    }
    
    private func cancelDualCameraPreviewTransition() {
        dualCameraPreviewSettlingTask?.cancel()
        dualCameraPreviewSettlingTask = nil
        isDualCameraTransitionCoverVisible = false
        isDualCameraPreviewSettling = false
    }
    
    private func configureDualCamera(mainLens requestedMainLens: Lens, transitionStarted: Bool = false) {
        guard dualSession != nil else {
            if transitionStarted {
                finishFailedDualCameraConfiguration(message: "Dual camera is not supported on this device.")
            }
            return
        }
        if !transitionStarted {
            guard beginDualCameraPreviewTransition() else { return }
        }
        
        let mainLens = switchableLensForDualCamera(requestedMainLens)
        let pipLens = preferredPipLens(for: mainLens)
        guard let mainCamera = mainLens.captureDevice(),
              let pipCamera = pipLens.captureDevice(),
              mainCamera.uniqueID != pipCamera.uniqueID,
              canUseDualCamera(mainLens: mainLens) else {
            finishFailedDualCameraConfiguration(message: "Could not find both front and back cameras for dual camera.")
            return
        }
        
        beginDualCameraPreviewTeardown()
        isDualCameraEnabled = true
        activeLens = mainLens
        secondaryLens = pipLens
        primeResolutionOptions(for: mainLens, device: mainCamera)
        
        let mainCameraID = mainCamera.uniqueID
        let pipCameraID = pipCamera.uniqueID
        let mainZoom = mainLens.zoomFactor
        let pipZoom = pipLens.zoomFactor
        
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard let multiCamSession = self.dualSession else { return }
            Thread.sleep(forTimeInterval: self.dualCameraPreviewDetachDelay)
            self.prepareOutputsForSessionReconfiguration()
            
            if self.session.isRunning {
                self.session.stopRunning()
            }
            self.removeAllSessionInputsAndOutputs(from: self.session)
            multiCamSession.beginConfiguration()
            self.removeAllSessionInputsAndOutputs(from: multiCamSession)
            
            guard let mainDevice = Lens.captureDevice(uniqueID: mainCameraID),
                  let pipDevice = Lens.captureDevice(uniqueID: pipCameraID),
                  let mainInput = try? AVCaptureDeviceInput(device: mainDevice),
                  let pipInput = try? AVCaptureDeviceInput(device: pipDevice),
                  let mainVideoPort = mainInput.ports.first(where: { $0.mediaType == .video }),
                  let pipVideoPort = pipInput.ports.first(where: { $0.mediaType == .video }),
                  multiCamSession.canAddInput(mainInput),
                  multiCamSession.canAddInput(pipInput),
                  multiCamSession.canAddOutput(self.photoOutput),
                  multiCamSession.canAddOutput(self.secondaryVideoOutput) else {
                multiCamSession.commitConfiguration()
                self.finishFailedDualCameraConfiguration(message: "Could not configure dual camera inputs.")
                return
            }
            
            self.configurePreferredMultiCamFormat(for: mainDevice)
            self.configurePreferredMultiCamFormat(for: pipDevice)
            
            multiCamSession.addInputWithNoConnections(mainInput)
            multiCamSession.addInputWithNoConnections(pipInput)
            multiCamSession.addOutputWithNoConnections(self.photoOutput)
            self.secondaryVideoOutput.alwaysDiscardsLateVideoFrames = true
            self.secondaryVideoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            multiCamSession.addOutputWithNoConnections(self.secondaryVideoOutput)
            
            let photoConnection = AVCaptureConnection(inputPorts: [mainVideoPort], output: self.photoOutput)
            let pipFrameConnection = AVCaptureConnection(inputPorts: [pipVideoPort], output: self.secondaryVideoOutput)
            guard multiCamSession.canAddConnection(photoConnection) else {
                multiCamSession.commitConfiguration()
                self.finishFailedDualCameraConfiguration(message: "Could not connect the main camera for photos.")
                return
            }
            multiCamSession.addConnection(photoConnection)
            if multiCamSession.canAddConnection(pipFrameConnection) {
                multiCamSession.addConnection(pipFrameConnection)
            }
            
            self.applyZoom(mainZoom, to: mainDevice)
            self.applyZoom(pipZoom, to: pipDevice)
            self.applyConnectionOrientation(for: mainDevice, lens: mainLens, connections: [photoConnection])
            self.applyConnectionOrientation(for: pipDevice, lens: pipLens, connections: [pipFrameConnection])
            self.enableLensSmudgeDetectionIfSupported(on: mainDevice)
            
            multiCamSession.commitConfiguration()
            self.updateMaxPhotoDimensions(for: mainDevice)
            self.secondaryVideoOutput.setSampleBufferDelegate(self, queue: self.pipFrameQueue)
            if !multiCamSession.isRunning {
                multiCamSession.startRunning()
            }
            let sessionIsRunning = multiCamSession.isRunning
            
            Task { @MainActor in
                self.isCaptureSessionRunning = sessionIsRunning
                self.device = mainDevice
                self.secondaryDevice = pipDevice
                self.activeLens = mainLens
                self.secondaryLens = pipLens
                self.mainPreviewDeviceUniqueID = mainDevice.uniqueID
                self.pipPreviewDeviceUniqueID = pipDevice.uniqueID
                self.captureRotationCoordinator = AVCaptureDevice.RotationCoordinator(device: mainDevice, previewLayer: nil)
                self.refreshCaptureAspectRatioOptions(for: mainDevice)
                self.updateCaptureOrientation()
                self.lensSwitchCompletionCount += 1
                self.configureLensSmudgeDetection(for: mainDevice)
                self.configureSubjectAreaMonitoring(for: mainDevice)
                self.updateDeviceRanges()
                self.normalizeFlashModeForCurrentDevice()
                self.buildAvailableFormats()
                self.setupCameraControls()
                self.isDetachingPreviewForReconfiguration = false
                self.isSwitchingLens = false
                self.isConfiguringDualCamera = false
                self.refreshSmartSelfieFraming()
                self.finishDualCameraPreviewTransition()
            }
        }
    }
    
    private func configureSingleCamera(lens requestedLens: Lens, transitionStarted: Bool = false) {
        if !transitionStarted {
            guard beginDualCameraPreviewTransition() else { return }
        }
        let lens = requestedLens
        guard let camera = lens.captureDevice() else {
            finishFailedDualCameraConfiguration(message: "Could not restore the camera.")
            return
        }
        
        beginDualCameraPreviewTeardown()
        isDualCameraEnabled = false
        _secondaryFrameStore.set(nil)
        secondaryDevice = nil
        secondaryLens = nil
        activeLens = lens
        
        let cameraID = camera.uniqueID
        let zoom = lens.zoomFactor
        let metadataTypes = supportedMetadataTypes
        let isMetadataEnabled = recognizeBarcodes && !isTimerCountingDown && !isBurstCapturing
        
        sessionQueue.async { [weak self] in
            guard let self else { return }
            Thread.sleep(forTimeInterval: self.dualCameraPreviewDetachDelay)
            self.prepareOutputsForSessionReconfiguration()
            
            if let dualSession = self.dualSession {
                if dualSession.isRunning {
                    dualSession.stopRunning()
                }
                self.removeAllSessionInputsAndOutputs(from: dualSession)
            }
            self.session.beginConfiguration()
            self.configureSupportedPhotoSessionPreset()
            self.removeAllSessionInputsAndOutputs(from: self.session)
            
            guard let device = Lens.captureDevice(uniqueID: cameraID) ?? lens.captureDevice(),
                  let input = try? AVCaptureDeviceInput(device: device),
                  self.session.canAddInput(input) else {
                self.session.commitConfiguration()
                self.finishFailedDualCameraConfiguration(message: "Could not restore the camera.")
                return
            }
            
            self.session.addInput(input)
            if self.session.canAddOutput(self.photoOutput) {
                self.session.addOutput(self.photoOutput)
            }
            self.configurePhotoOutputCapabilities()
            if self.session.canAddOutput(self.videoOutput) {
                self.session.addOutput(self.videoOutput)
                self.videoOutput.setSampleBufferDelegate(self, queue: self.analysisQueue)
            }
            if self.session.canAddOutput(self.metadataOutput) {
                self.session.addOutput(self.metadataOutput)
                self.metadataOutput.setMetadataObjectsDelegate(self, queue: .main)
                let available = self.metadataOutput.availableMetadataObjectTypes
                self.metadataOutput.metadataObjectTypes = isMetadataEnabled ? metadataTypes.filter { available.contains($0) } : []
            }
            
            self.applyZoom(zoom, to: device)
            self.enableLensSmudgeDetectionIfSupported(on: device)
            self.applyConnectionOrientation(
                for: device,
                lens: lens,
                connections: [
                    self.photoOutput.connection(with: .video),
                    self.videoOutput.connection(with: .video)
                ].compactMap { $0 }
            )
            
            self.session.commitConfiguration()
            self.updateMaxPhotoDimensions(for: device)
            if !self.session.isRunning {
                self.session.startRunning()
            }
            let sessionIsRunning = self.session.isRunning
            
            Task { @MainActor in
                self.isCaptureSessionRunning = sessionIsRunning
                self.device = device
                self.secondaryDevice = nil
                self.secondaryLens = nil
                self.dualCameraPipRotationAngle = 0
                self.captureRotationCoordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil)
                self.lensSwitchCompletionCount += 1
                self.refreshCaptureAspectRatioOptions(for: device)
                self.configureLensSmudgeDetection(for: device)
                self.configureSubjectAreaMonitoring(for: device)
                self.buildAvailableFormats()
                self.updateDeviceRanges()
                self.normalizeFlashModeForCurrentDevice()
                self.enforceExposureModeConstraints()
                self.setupCameraControls()
                self.isDetachingPreviewForReconfiguration = false
                self.isSwitchingLens = false
                self.isConfiguringDualCamera = false
                self.refreshSmartSelfieFraming()
                self.finishDualCameraPreviewTransition()
            }
        }
    }
    
    private func preferredPipLens(for mainLens: Lens) -> Lens {
        if mainLens.isFront {
            return .wide
        }
        
        if Lens.front.captureDevice() != nil {
            return .front
        }
        
        return .frontUltraWide
    }
    
    func canUseDualCamera(mainLens: Lens) -> Bool {
        let pipLens = preferredPipLens(for: mainLens)
        guard let mainDevice = mainLens.captureDevice(),
              let pipDevice = pipLens.captureDevice(),
              mainDevice.uniqueID != pipDevice.uniqueID else { return false }
        
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .builtInUltraWideCamera, .builtInTelephotoCamera, .builtInTrueDepthCamera],
            mediaType: .video,
            position: .unspecified
        )
        
        return discovery.supportedMultiCamDeviceSets.contains { deviceSet in
            deviceSet.contains(mainDevice) && deviceSet.contains(pipDevice)
        }
    }
    
    private func switchableLensForDualCamera(_ lens: Lens) -> Lens {
        if lens.isFront {
            return lens
        }
        
        switch lens {
            case .frontUltraWide, .front, .ultraWide, .wide, .tele2x, .tele4x, .tele8x:
                return lens
        }
    }
    
    private nonisolated func removeAllSessionInputsAndOutputs(from captureSession: AVCaptureSession) {
        for connection in captureSession.connections where connection.videoPreviewLayer == nil {
            captureSession.removeConnection(connection)
        }
        for output in captureSession.outputs {
            captureSession.removeOutput(output)
        }
        for input in captureSession.inputs {
            captureSession.removeInput(input)
        }
    }
    
    private nonisolated func prepareOutputsForSessionReconfiguration() {
        videoOutput.setSampleBufferDelegate(nil, queue: nil)
        secondaryVideoOutput.setSampleBufferDelegate(nil, queue: nil)
        metadataOutput.setMetadataObjectsDelegate(nil, queue: nil)
    }
    
    private nonisolated func configurePreferredMultiCamFormat(for device: AVCaptureDevice) {
        guard let format = preferredMultiCamFormat(for: device) else { return }
        try? device.lockForConfiguration()
        device.activeFormat = format
        device.unlockForConfiguration()
    }
    
    private nonisolated func preferredMultiCamFormat(for device: AVCaptureDevice) -> AVCaptureDevice.Format? {
        device.formats
            .filter(\.isMultiCamSupported)
            .max { lhs, rhs in
                let lhsScore = multiCamFormatScore(lhs)
                let rhsScore = multiCamFormatScore(rhs)
                if lhsScore.hasFourByThreePhoto != rhsScore.hasFourByThreePhoto {
                    return !lhsScore.hasFourByThreePhoto && rhsScore.hasFourByThreePhoto
                }
                if lhsScore.videoAspectPenalty != rhsScore.videoAspectPenalty {
                    return lhsScore.videoAspectPenalty > rhsScore.videoAspectPenalty
                }
                if lhsScore.photoPixels != rhsScore.photoPixels {
                    return lhsScore.photoPixels < rhsScore.photoPixels
                }
                return lhsScore.videoPixels < rhsScore.videoPixels
            }
    }
    
    private nonisolated func multiCamFormatScore(_ format: AVCaptureDevice.Format) -> (hasFourByThreePhoto: Bool, videoAspectPenalty: Double, photoPixels: Int, videoPixels: Int) {
        let photoDimensions = preferredPhotoDimensions(from: format.supportedMaxPhotoDimensions)
        let videoDimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
        let hasFourByThreePhoto = format.supportedMaxPhotoDimensions.contains(where: isFourByThree)
        let videoAspectPenalty = aspectPenalty(videoDimensions)
        return (
            hasFourByThreePhoto,
            videoAspectPenalty,
            Int(photoDimensions.width) * Int(photoDimensions.height),
            Int(videoDimensions.width) * Int(videoDimensions.height)
        )
    }
    
    private nonisolated func applyZoom(_ zoomFactor: CGFloat, to device: AVCaptureDevice) {
        guard zoomFactor > 1 else { return }
        try? device.lockForConfiguration()
        device.videoZoomFactor = min(device.activeFormat.videoMaxZoomFactor, zoomFactor)
        device.unlockForConfiguration()
    }
    
    private nonisolated func applyConnectionOrientation(for device: AVCaptureDevice,
                                                        lens: Lens,
                                                        connections: [AVCaptureConnection]) {
        let rotationAngle = Lens.rotationAngle(for: device, lens: lens)
        let isMirrored = Lens.isMirrored(device, lens: lens)
        for connection in connections {
            if connection.isVideoRotationAngleSupported(rotationAngle) {
                connection.videoRotationAngle = rotationAngle
            }
            if connection.isVideoMirroringSupported {
                connection.isVideoMirrored = connection.output === photoOutput ? false : isMirrored
            }
        }
    }
    
    private nonisolated func updateMaxPhotoDimensions(for device: AVCaptureDevice) {
        let largest = preferredPhotoDimensions(from: device.activeFormat.supportedMaxPhotoDimensions)
        guard largest.width > 0, largest.height > 0 else { return }
        photoOutput.maxPhotoDimensions = largest
    }
    
    private nonisolated func preferredPhotoDimensions(from dimensions: [CMVideoDimensions]) -> CMVideoDimensions {
        let fourByThree = dimensions.filter(isFourByThree)
        let candidates = fourByThree.isEmpty ? dimensions : fourByThree
        return candidates.max(by: {
            Int($0.width) * Int($0.height) < Int($1.width) * Int($1.height)
        }) ?? CMVideoDimensions(width: 0, height: 0)
    }
    
    private nonisolated func isFourByThree(_ dimensions: CMVideoDimensions) -> Bool {
        guard dimensions.width > 0, dimensions.height > 0 else { return false }
        let ratio = Double(max(dimensions.width, dimensions.height)) / Double(min(dimensions.width, dimensions.height))
        return abs(ratio - (4.0 / 3.0)) < 0.04
    }
    
    private nonisolated func aspectPenalty(_ dimensions: CMVideoDimensions) -> Double {
        guard dimensions.width > 0, dimensions.height > 0 else { return .greatestFiniteMagnitude }
        let ratio = Double(max(dimensions.width, dimensions.height)) / Double(min(dimensions.width, dimensions.height))
        return abs(ratio - (4.0 / 3.0))
    }
    
    private nonisolated func finishFailedDualCameraConfiguration(message: String) {
        Task { @MainActor in
            self.isDualCameraEnabled = false
            self.isSwitchingLens = false
            self.isConfiguringDualCamera = false
            self.secondaryDevice = nil
            self.secondaryLens = nil
            self.mainPreviewDeviceUniqueID = nil
            self.pipPreviewDeviceUniqueID = nil
            self._secondaryFrameStore.set(nil)
            self.isDetachingPreviewForReconfiguration = false
            self.cancelDualCameraPreviewTransition()
            self.errorMessage = message
            self.showError = true
        }
    }
}
