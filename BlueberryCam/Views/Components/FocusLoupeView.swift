import CoreImage
import SwiftUI

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
