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
                
                // Rule-of-thirds grid (2 vertical + 2 horizontal inner lines only)
                Canvas { ctx, _ in
                    let lineColor = Color.white.opacity(0.25)
                    let style = StrokeStyle(lineWidth: 0.75)
                    let thirdW = cropW / 3
                    let thirdH = cropH / 3
                    
                    for i in 1...2 {
                        // Vertical
                        var v = Path()
                        let vx = cropX + thirdW * CGFloat(i)
                        v.move(to: CGPoint(x: vx, y: cropY))
                        v.addLine(to: CGPoint(x: vx, y: cropY + cropH))
                        ctx.stroke(v, with: .color(lineColor), style: style)
                        
                        // Horizontal
                        var h = Path()
                        let hy = cropY + thirdH * CGFloat(i)
                        h.move(to: CGPoint(x: cropX, y: hy))
                        h.addLine(to: CGPoint(x: cropX + cropW, y: hy))
                        ctx.stroke(h, with: .color(lineColor), style: style)
                    }
                }
                .allowsHitTesting(false)
                
                // Corner marks (inset slightly so they don't bleed off the screen edge)
                CornerMarks(rect: cropRect.insetBy(dx: 0.4, dy: 0.5))
                    .stroke(Color.white.opacity(0.75), lineWidth: 1.0)
            }
        }
    }
}

// Draws L-shaped corners at each corner of rect
struct CornerMarks: Shape {
    let rect: CGRect
    let len: CGFloat = 14
    
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
