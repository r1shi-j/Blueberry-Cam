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
    let session: AVCaptureSession
    let onCapture: () -> Void
    let proxy: PreviewViewProxy
    
    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.session = session
        view.onCapture = onCapture
        proxy.view = view
        return view
    }
    
    func updateUIView(_ uiView: PreviewUIView, context: Context) {
        proxy.view = uiView
    }
}

final class PreviewUIView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    
    var onCapture: (() -> Void)?
    private var eventInteraction: AVCaptureEventInteraction?
    
    var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }
    
    var session: AVCaptureSession? {
        get { previewLayer.session }
        set {
            previewLayer.session = newValue
            previewLayer.videoGravity = .resizeAspect
            
            if let conn = previewLayer.connection, conn.isVideoMirroringSupported {
                conn.automaticallyAdjustsVideoMirroring = true
            }
            
            setupInteraction()
        }
    }
    
    private func setupInteraction() {
        if eventInteraction == nil {
            let interaction = AVCaptureEventInteraction { [weak self] event in
                if event.phase == .ended {
                    self?.onCapture?()
                }
            }
            addInteraction(interaction)
            eventInteraction = interaction
        }
    }
}
