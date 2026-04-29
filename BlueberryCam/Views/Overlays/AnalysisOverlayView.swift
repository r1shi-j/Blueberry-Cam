import SwiftUI

struct AnalysisOverlayView: View {
    enum Style {
        case focusPeaking
        case zebra
        case clipping
    }
    
    let mask: [UInt8]
    let gridSize: CGSize
    let style: Style
    
    var body: some View {
        GeometryReader { geo in
            Canvas { context, size in
                let cols = Int(gridSize.width)
                let rows = Int(gridSize.height)
                guard cols > 0, rows > 0, mask.count == cols * rows else {
                    return
                }
                
                let cellWidth = size.width / CGFloat(cols)
                let cellHeight = size.height / CGFloat(rows)
                
                for y in 0..<rows {
                    for x in 0..<cols {
                        let index = y * cols + x
                        let intensity = mask[index]
                        guard intensity > 0 else { continue }
                        
                        if style == .zebra, ((x + y) % 2 != 0) {
                            continue
                        }
                        
                        let rect = CGRect(
                            x: CGFloat(x) * cellWidth,
                            y: CGFloat(y) * cellHeight,
                            width: cellWidth + 0.5,
                            height: cellHeight + 0.5
                        )
                        
                        switch style {
                            case .focusPeaking:
                                let opacity = 0.35 + (Double(intensity) / 255.0) * 0.55
                                let diameter = max(1.8, min(cellWidth, cellHeight) * 0.64)
                                let dot = CGRect(
                                    x: rect.midX - diameter / 2,
                                    y: rect.midY - diameter / 2,
                                    width: diameter,
                                    height: diameter
                                )
                                context.fill(Path(ellipseIn: dot), with: .color(.green.opacity(opacity)))
                            case .zebra:
                                let r = max(0.75, min(cellWidth, cellHeight) * 0.45)
                                let dot = CGRect(x: rect.midX - r, y: rect.midY - r, width: r * 2, height: r * 2)
                                context.fill(Path(dot), with: .color(.gray.opacity(0.6)))
                            case .clipping:
                                let r = max(0.6, min(cellWidth, cellHeight) * 0.3)
                                let dot = CGRect(x: rect.midX - r, y: rect.midY - r, width: r * 2, height: r * 2)
                                context.fill(Path(ellipseIn: dot), with: .color(.red.opacity(0.9)))
                        }
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }
}
