import SwiftUI

struct HistogramView: View {
    let mode: HistogramMode
    let lumaData: [Float]
    let redData: [Float]
    let greenData: [Float]
    let blueData: [Float]
    let waveformData: [Float]
    let waveformCols: Int
    let waveformRows: Int

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                // Background
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.black.opacity(0.5))

                // Content
                Canvas { context, size in
                    switch mode {
                    case .luminance:
                        drawLuminance(context: context, size: size)
                    case .color:
                        drawColor(context: context, size: size)
                    case .waveform:
                        drawWaveform(context: context, size: size)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 6))

                // Mode label
                HStack {
                    Text(mode.rawValue)
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.5))
                    Spacer()
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 3)
            }
        }
    }
    
    // MARK: - Luminance
    private func drawLuminance(context: GraphicsContext, size: CGSize) {
        guard !lumaData.isEmpty else { return }
        let maxVal = lumaData.max() ?? 1
        let barWidth = size.width / CGFloat(lumaData.count)
        
        for (i, val) in lumaData.enumerated() {
            let normalized = maxVal > 0 ? CGFloat(val / maxVal) : 0
            let barHeight = normalized * size.height * 0.9
            let x = CGFloat(i) * barWidth
            let rect = CGRect(x: x, y: size.height - barHeight,
                              width: max(barWidth - 0.3, 0.5), height: barHeight)
            
            let color = Color.white.opacity(0.7)
            context.fill(Path(rect), with: .color(color))
        }
    }
    
    // MARK: - Color (RGB overlay)
    private func drawColor(context: GraphicsContext, size: CGSize) {
        let channels: [(data: [Float], color: Color)] = [
            (redData,   Color.red.opacity(0.6)),
            (greenData, Color.green.opacity(0.6)),
            (blueData,  Color.blue.opacity(0.6)),
        ]
        
        for (data, color) in channels {
            guard !data.isEmpty else { continue }
            let maxVal = data.max() ?? 1
            let barWidth = size.width / CGFloat(data.count)
            
            for (i, val) in data.enumerated() {
                let normalized = maxVal > 0 ? CGFloat(val / maxVal) : 0
                let barHeight = normalized * size.height * 0.9
                let x = CGFloat(i) * barWidth
                let rect = CGRect(x: x, y: size.height - barHeight,
                                  width: max(barWidth - 0.3, 0.5), height: barHeight)
                context.fill(Path(rect), with: .color(color))
            }
        }
    }
    
    // MARK: - Waveform
    private func drawWaveform(context: GraphicsContext, size: CGSize) {
        guard !waveformData.isEmpty, waveformCols > 0, waveformRows > 0 else { return }
        guard waveformData.count == waveformCols * waveformRows else { return }
        
        let cellW = size.width / CGFloat(waveformCols)
        let cellH = size.height / CGFloat(waveformRows)
        
        for row in 0..<waveformRows {
            for col in 0..<waveformCols {
                let val = waveformData[row * waveformCols + col]
                guard val > 0.01 else { continue }
                
                // Waveform drawn bottom-up: row 0 = shadows (bottom), row max = highlights (top)
                let x = CGFloat(col) * cellW
                let y = size.height - CGFloat(row + 1) * cellH
                let rect = CGRect(x: x, y: y, width: cellW + 0.5, height: cellH + 0.5)
                
                let brightness = min(1.0, Double(val) * 2.0)
                let color = Color.green.opacity(brightness * 0.8)
                context.fill(Path(rect), with: .color(color))
            }
        }
    }
}
