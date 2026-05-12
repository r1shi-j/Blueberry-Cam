internal import AVFoundation
import AVKit
import SwiftUI

final class PreviewViewProxy {
    weak var view: PreviewUIView?
    
    func captureDevicePoint(fromLayerPoint point: CGPoint) -> CGPoint? {
        view?.previewLayer.captureDevicePointConverted(fromLayerPoint: point)
    }
}

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession?
    let onCapture: () -> Void
    let proxy: PreviewViewProxy
    var deviceUniqueID: String?
    var rotationAngle: CGFloat = 0
    var isMirrored = false
    var handlesCaptureEvents = true
    
    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.configure(
            session: session,
            deviceUniqueID: deviceUniqueID,
            rotationAngle: rotationAngle,
            isMirrored: isMirrored,
            handlesCaptureEvents: handlesCaptureEvents
        )
        view.onCapture = onCapture
        proxy.view = view
        return view
    }
    
    func updateUIView(_ uiView: PreviewUIView, context: Context) {
        uiView.onCapture = onCapture
        uiView.configure(
            session: session,
            deviceUniqueID: deviceUniqueID,
            rotationAngle: rotationAngle,
            isMirrored: isMirrored,
            handlesCaptureEvents: handlesCaptureEvents
        )
        proxy.view = uiView
    }
}

final class PreviewUIView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    
    var onCapture: (() -> Void)?
    private var eventInteraction: AVCaptureEventInteraction?
    private var previewConnection: AVCaptureConnection?
    private var connectedDeviceUniqueID: String?
    
    var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }
    
    deinit {
        removePreviewConnectionIfNeeded(from: previewLayer.session)
    }
    
    func configure(session: AVCaptureSession,
                   deviceUniqueID: String?,
                   rotationAngle: CGFloat,
                   isMirrored: Bool,
                   handlesCaptureEvents: Bool) {
        previewLayer.videoGravity = deviceUniqueID == nil ? .resizeAspect : .resizeAspectFill
        
        if let deviceUniqueID {
            configureManualConnection(
                session: session,
                deviceUniqueID: deviceUniqueID,
                rotationAngle: rotationAngle,
                isMirrored: isMirrored
            )
        } else {
            removePreviewConnectionIfNeeded(from: previewLayer.session)
            previewLayer.session = session
            connectedDeviceUniqueID = nil
            if let connection = previewLayer.connection, connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = true
            }
        }
        
        updateCaptureEventInteraction(isEnabled: handlesCaptureEvents)
    }
    
    func configure(session: AVCaptureSession?,
                   deviceUniqueID: String?,
                   rotationAngle: CGFloat,
                   isMirrored: Bool,
                   handlesCaptureEvents: Bool) {
        guard let session else {
            removePreviewConnectionIfNeeded(from: previewLayer.session)
            previewLayer.session = nil
            connectedDeviceUniqueID = nil
            updateCaptureEventInteraction(isEnabled: false)
            return
        }
        
        configure(
            session: session,
            deviceUniqueID: deviceUniqueID,
            rotationAngle: rotationAngle,
            isMirrored: isMirrored,
            handlesCaptureEvents: handlesCaptureEvents
        )
    }
    
    private func configureManualConnection(session: AVCaptureSession,
                                           deviceUniqueID: String,
                                           rotationAngle: CGFloat,
                                           isMirrored: Bool) {
        if previewLayer.session !== session {
            removePreviewConnectionIfNeeded(from: previewLayer.session)
            previewLayer.setSessionWithNoConnection(session)
            connectedDeviceUniqueID = nil
        }
        
        if connectedDeviceUniqueID != deviceUniqueID || previewConnection.map({ !session.connections.contains($0) }) != false {
            removePreviewConnectionIfNeeded(from: session)
            guard let port = videoPort(for: deviceUniqueID, in: session) else { return }
            let connection = AVCaptureConnection(inputPort: port, videoPreviewLayer: previewLayer)
            guard session.canAddConnection(connection) else { return }
            session.addConnection(connection)
            previewConnection = connection
            connectedDeviceUniqueID = deviceUniqueID
        }
        
        guard let connection = previewConnection else { return }
        if connection.isVideoRotationAngleSupported(rotationAngle) {
            connection.videoRotationAngle = rotationAngle
        }
        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = isMirrored
        }
    }
    
    private func videoPort(for deviceUniqueID: String, in session: AVCaptureSession) -> AVCaptureInput.Port? {
        session.inputs
            .compactMap { $0 as? AVCaptureDeviceInput }
            .first(where: { $0.device.uniqueID == deviceUniqueID })?
            .ports
            .first(where: { $0.mediaType == .video })
    }
    
    private func removePreviewConnectionIfNeeded(from session: AVCaptureSession?) {
        guard let previewConnection else { return }
        if session?.connections.contains(previewConnection) == true {
            session?.removeConnection(previewConnection)
        }
        self.previewConnection = nil
    }
    
    private func updateCaptureEventInteraction(isEnabled: Bool) {
        guard isEnabled else {
            if let eventInteraction {
                removeInteraction(eventInteraction)
                self.eventInteraction = nil
            }
            return
        }
        
        if eventInteraction == nil {
            let interaction = AVCaptureEventInteraction { [weak self] event in
                guard event.phase == .ended else { return }
                self?.onCapture?()
            }
            addInteraction(interaction)
            self.eventInteraction = interaction
        }
        
        eventInteraction?.isEnabled = true
    }
}
