import CoreImage
import SwiftUI

/// A circular magnifying loupe that shows a zoomed-in crop of the center
/// of the camera feed, rendered from the existing video output frames.
/// No second AVCaptureVideoPreviewLayer — avoids session conflicts.
struct FocusLoupeView: View {
    let loupeImage: CGImage?
    
    var body: some View {
        if let loupeImage {
            Image(decorative: loupeImage, scale: 1.0)
                .resizable()
                .scaledToFill()
        }
    }
}
