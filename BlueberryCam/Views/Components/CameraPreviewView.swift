import AVFoundation
import SwiftUI

final class PreviewViewProxy {
    weak var view: PreviewUIView?
    
    func captureDevicePoint(fromLayerPoint point: CGPoint) -> CGPoint? {
        view?.previewLayer.captureDevicePointConverted(fromLayerPoint: point)
    }
}

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    let proxy: PreviewViewProxy
    
    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        proxy.view = view
        // Always set session on main thread to avoid exclusivity conflicts
        DispatchQueue.main.async {
            view.setSession(session)
        }
        return view
    }
    
    func updateUIView(_ uiView: PreviewUIView, context: Context) {
        proxy.view = uiView
        // Re-apply session only if it has actually changed
        if uiView.previewLayer.session !== session {
            DispatchQueue.main.async {
                uiView.setSession(session)
            }
        }
    }
}

final class PreviewUIView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    
    var previewLayer: AVCaptureVideoPreviewLayer {
        // swiftlint:disable:next force_cast
        layer as! AVCaptureVideoPreviewLayer
    }
    
    /// Safely attach a session to the preview layer.
    /// Must be called on the main thread; does nothing if already set.
    func setSession(_ session: AVCaptureSession) {
        assert(Thread.isMainThread, "setSession must be called on the main thread")
        guard previewLayer.session !== session else { return }
        previewLayer.session = session
        previewLayer.videoGravity = .resizeAspect
        if let conn = previewLayer.connection, conn.isVideoMirroringSupported {
            conn.automaticallyAdjustsVideoMirroring = true
        }
    }
}
