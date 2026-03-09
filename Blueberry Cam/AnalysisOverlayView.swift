import SwiftUI

struct AnalysisOverlayView: View {
    enum Style {
        case focusPeaking
        case zebra
    }
    
    let mask: [UInt8]
    let gridSize: CGSize
    let style: Style
    
    var body: some View {
        GeometryReader { geo in
            Canvas { context, size in
                let cols = Int(gridSize.width)
                let rows = Int(gridSize.height)
                guard cols > 0, rows > 0, mask.count == cols * rows else { return }
                
                let cellWidth = size.width / CGFloat(cols)
                let cellHeight = size.height / CGFloat(rows)
                
                for y in 0..<rows {
                    for x in 0..<cols {
                        let index = y * cols + x
                        guard mask[index] > 0 else { continue }
                        
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
                            context.fill(Path(rect), with: .color(Color.yellow.opacity(0.85)))
                        case .zebra:
                            context.fill(Path(rect), with: .color(Color.white.opacity(0.45)))
                        }
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }
}
