import SwiftUI

struct CropOverlayView: View {
    let aspectRatio: CGFloat  // width/height e.g. 3/4 = 0.75
    
    var body: some View {
        GeometryReader { geo in
            let screenW = geo.size.width
            let screenH = geo.size.height
            let screenAspect = screenW / screenH
            
            // Compute crop rect — same logic as resizeAspect preview
            let cropW: CGFloat = aspectRatio < screenAspect ? screenH * aspectRatio : screenW
            let cropH: CGFloat = aspectRatio < screenAspect ? screenH : screenW / aspectRatio
            let cropX = (screenW - cropW) / 2
            let cropY = (screenH - cropH) / 2
            let cropRect = CGRect(x: cropX, y: cropY, width: cropW, height: cropH)
            
            ZStack {
                // Dim areas outside crop rect
                Color.black.opacity(0.5)
                    .reverseMask {
                        Rectangle()
                            .frame(width: cropW, height: cropH)
                            .position(x: cropRect.midX, y: cropRect.midY)
                    }
                
                // Corner marks
                CornerMarks(rect: cropRect)
                    .stroke(Color.white.opacity(0.8), lineWidth: 1.5)
            }
        }
    }
}

// Draws L-shaped corners at each corner of rect
struct CornerMarks: Shape {
    let rect: CGRect
    let len: CGFloat = 20
    
    func path(in _: CGRect) -> Path {
        var p = Path()
        let corners: [(CGPoint, CGFloat, CGFloat)] = [
            (rect.origin,                              1,  1),
            (CGPoint(x: rect.maxX, y: rect.minY),    -1,  1),
            (CGPoint(x: rect.minX, y: rect.maxY),     1, -1),
            (CGPoint(x: rect.maxX, y: rect.maxY),    -1, -1),
        ]
        for (origin, dx, dy) in corners {
            p.move(to: CGPoint(x: origin.x + dx * len, y: origin.y))
            p.addLine(to: origin)
            p.addLine(to: CGPoint(x: origin.x, y: origin.y + dy * len))
        }
        return p
    }
}

extension View {
    func reverseMask<M: View>(@ViewBuilder mask: () -> M) -> some View {
        self.mask(
            ZStack {
                Rectangle()
                mask().blendMode(.destinationOut)
            }
                .compositingGroup()
        )
    }
}
