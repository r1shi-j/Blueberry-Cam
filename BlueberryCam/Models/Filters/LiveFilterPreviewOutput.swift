import CoreVideo
import Foundation

protocol LiveFilterPreviewFrameRenderer: AnyObject {
    nonisolated func render(pixelBuffer: CVPixelBuffer, filter: PhotoFilter, referenceSize: CGSize)
}

final class LiveFilterPreviewOutput: @unchecked Sendable {
    private let lock = NSLock()
    nonisolated(unsafe) private weak var renderer: LiveFilterPreviewFrameRenderer?
    
    nonisolated init() {}
    
    nonisolated func setRenderer(_ renderer: LiveFilterPreviewFrameRenderer?) {
        lock.lock()
        self.renderer = renderer
        lock.unlock()
    }
    
    nonisolated func render(pixelBuffer: CVPixelBuffer, filter: PhotoFilter, referenceSize: CGSize) {
        lock.lock()
        let renderer = renderer
        lock.unlock()
        
        renderer?.render(pixelBuffer: pixelBuffer, filter: filter, referenceSize: referenceSize)
    }
}
