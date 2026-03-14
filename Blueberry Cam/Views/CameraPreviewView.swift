internal import AVFoundation
import AVKit
import SwiftUI

struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    let onCapture: () -> Void
    
    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.session = session
        view.onCapture = onCapture
        return view
    }
    
    func updateUIView(_ uiView: PreviewUIView, context: Context) {}
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
