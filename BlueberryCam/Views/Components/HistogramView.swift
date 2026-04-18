import SwiftUI

extension HistogramView {
    private var cornerRadius: CGFloat { size == .small ? 3 : 6 }
    
    private var backgroundOpacity: Double {
        size == .large && mode == .waveform ? 0.72 : 0.55
    }
    
    // MARK: - Bar histogram (luminance + color)
    private func drawBars(
        _ ctx: GraphicsContext, _ sz: CGSize,
        channels: [(data: [Float], color: Color)],
        buckets: Int?,
        opacity: Double
    ) {
        let gap: CGFloat = size == .small ? 0.4 : 0.3
        let minH: CGFloat = size == .small ? 0.8 : 0.5
        
        for (rawData, color) in channels {
            let data = buckets != nil ? downsample(rawData, into: buckets!) : rawData
            guard !data.isEmpty, let maxVal = data.max(), maxVal > 0 else { continue }
            let bw   = sz.width / CGFloat(data.count)
            let barW = max(bw - gap, 0.5)
            let capR = barW / 2.0
            
            for (i, v) in data.enumerated() {
                let h = max(minH, CGFloat(v / maxVal) * sz.height * 0.92)
                let x = CGFloat(i) * bw
                let bodyTop = sz.height - h
                
                if h > capR * 2 {
                    var path = Path()
                    path.addRect(CGRect(x: x, y: bodyTop + capR, width: barW, height: h - capR))
                    path.addArc(center: CGPoint(x: x + capR, y: bodyTop + capR),
                                radius: capR, startAngle: .degrees(180), endAngle: .degrees(0),
                                clockwise: false)
                    path.addRect(CGRect(x: x, y: bodyTop + capR, width: barW, height: capR))
                    ctx.fill(path, with: .color(color.opacity(opacity)))
                } else {
                    ctx.fill(Path(CGRect(x: x, y: bodyTop, width: barW, height: h)),
                             with: .color(color.opacity(opacity)))
                }
            }
        }
    }
    
    // MARK: - Parade
    private func drawParade(_ ctx: GraphicsContext, _ sz: CGSize, buckets: Int?) {
        let panelW = sz.width / 3
        let gap: CGFloat = size == .small ? 0.4 : 0.3
        let minH: CGFloat = size == .small ? 0.8 : 0.5
        let opacity: Double = size == .small ? 0.82 : 0.75
        let channels: [(data: [Float], color: Color)] = [
            (redData, .red), (greenData, .green), (blueData, .blue)
        ]
        for (panelIdx, (rawData, color)) in channels.enumerated() {
            let data = buckets != nil ? downsample(rawData, into: buckets!) : rawData
            guard !data.isEmpty, let maxVal = data.max(), maxVal > 0 else { continue }
            let offsetX = CGFloat(panelIdx) * panelW
            let bw = panelW / CGFloat(data.count)
            let barW = max(bw - gap, 0.4)
            let capR = barW / 2.0
            
            for (i, v) in data.enumerated() {
                let h = max(minH, CGFloat(v / maxVal) * sz.height * 0.92)
                let x = offsetX + CGFloat(i) * bw
                let bodyTop = sz.height - h
                
                if h > capR * 2 {
                    var path = Path()
                    path.addRect(CGRect(x: x, y: bodyTop + capR, width: barW, height: h - capR))
                    path.addArc(center: CGPoint(x: x + capR, y: bodyTop + capR),
                                radius: capR, startAngle: .degrees(180), endAngle: .degrees(0),
                                clockwise: false)
                    path.addRect(CGRect(x: x, y: bodyTop + capR, width: barW, height: capR))
                    ctx.fill(path, with: .color(color.opacity(opacity)))
                } else {
                    ctx.fill(Path(CGRect(x: x, y: bodyTop, width: barW, height: h)),
                             with: .color(color.opacity(opacity)))
                }
            }
            if panelIdx < 2 {
                ctx.fill(Path(CGRect(x: offsetX + panelW - 0.5, y: 0, width: 0.5, height: sz.height)),
                         with: .color(.white.opacity(0.12)))
            }
        }
    }
    
    // MARK: - Waveform (shared for both sizes, parameterised by outCols)
    // Renders a density-weighted field of dots. The large waveform uses the full
    // analysis resolution so it scales the small waveform up cleanly instead of
    // exposing the intermediate column grid as visible vertical stripes.
    private func drawWaveform(_ ctx: GraphicsContext, _ sz: CGSize, outCols: Int) {
        let wfCols = WaveformConstants.wfCols
        let wfRows = WaveformConstants.wfRows
        guard waveformData.count == wfCols * wfRows * 4 else { return }
        
        let clampedCols = min(outCols, wfCols)
        guard clampedCols > 0, wfRows > 0, sz.width > 0, sz.height > 0 else { return }
        
        let cellW = sz.width  / CGFloat(clampedCols)
        let cellH = sz.height / CGFloat(wfRows)
        let dotW = size == .small ? max(1.0, cellW * 0.72) : max(0.9, cellW * 1.35)
        let dotH = size == .small ? max(0.6, cellH * 0.72) : max(0.75, cellH * 0.92)
        let padX = (cellW - dotW) * 0.5
        let padY = (cellH - dotH) * 0.5
        let densityThreshold: Float = size == .small ? 0.018 : 0.010
        let alphaScale: Double = size == .small ? 0.88 : 0.98
        
        for outCol in 0..<clampedCols {
            let srcStart = Int((CGFloat(outCol) * CGFloat(wfCols) / CGFloat(clampedCols)).rounded(.down))
            let srcEnd = min(
                wfCols,
                max(
                    srcStart + 1,
                    Int((CGFloat(outCol + 1) * CGFloat(wfCols) / CGFloat(clampedCols)).rounded(.up))
                )
            )
            guard srcStart < srcEnd else { continue }
            
            var rowWeightedR = [Float](repeating: 0, count: wfRows)
            var rowWeightedG = [Float](repeating: 0, count: wfRows)
            var rowWeightedB = [Float](repeating: 0, count: wfRows)
            var rowDensitySum = [Float](repeating: 0, count: wfRows)
            var rowPeakDensity = [Float](repeating: 0, count: wfRows)
            let sourceCount = Float(srcEnd - srcStart)
            
            for srcCol in srcStart..<srcEnd {
                for row in 0..<wfRows {
                    let base = (row * wfCols + srcCol) * 4
                    let d = waveformData[base + 3]
                    guard d > 0 else { continue }
                    rowDensitySum[row] += d
                    rowPeakDensity[row] = max(rowPeakDensity[row], d)
                    rowWeightedR[row] += waveformData[base] * d
                    rowWeightedG[row] += waveformData[base + 1] * d
                    rowWeightedB[row] += waveformData[base + 2] * d
                }
            }
            
            let cx = CGFloat(outCol) * cellW + padX
            
            for row in 0..<wfRows {
                let densitySum = rowDensitySum[row]
                guard densitySum > 0 else { continue }
                
                let mergedDensity = max(rowPeakDensity[row], densitySum / sourceCount)
                guard mergedDensity > densityThreshold else { continue }
                
                let cy = sz.height - CGFloat(row + 1) * cellH + padY
                let rect = CGRect(x: cx, y: cy, width: dotW, height: dotH)
                let alpha = pow(Double(min(mergedDensity, 1.0)), 0.78) * alphaScale
                ctx.fill(Path(rect), with: .color(Color(
                    red: Double(rowWeightedR[row] / densitySum),
                    green: Double(rowWeightedG[row] / densitySum),
                    blue: Double(rowWeightedB[row] / densitySum)
                ).opacity(alpha)))
            }
        }
    }
    
    
    // MARK: - Helpers
    private var rgbChannels: [(data: [Float], color: Color)] {
        [(redData, .red), (greenData, .green), (blueData, .blue)]
    }
    
    private func downsample(_ data: [Float], into buckets: Int) -> [Float] {
        guard !data.isEmpty, buckets > 0 else { return [] }
        let step = max(1, data.count / buckets)
        return (0..<buckets).map { b in
            let start = b * step
            let end   = min(start + step, data.count)
            return data[start..<end].reduce(0, +)
        }
    }
}

struct HistogramView: View {
    let mode: HistogramMode
    let size: HistogramSize
    let lumaData: [Float]
    let redData: [Float]
    let greenData: [Float]
    let blueData: [Float]
    let waveformData: [Float]
    
    var body: some View {
        GeometryReader { _ in
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.black.opacity(backgroundOpacity))
                
                if size == .small {
                    Canvas { ctx, sz in
                        switch mode {
                            case .luminance: drawBars(ctx, sz, channels: [(lumaData, .white)], buckets: 64,  opacity: 0.85)
                            case .color: drawBars(ctx, sz, channels: rgbChannels, buckets: 64,  opacity: 0.72)
                            case .waveform: drawWaveform(ctx, sz, outCols: 80)
                            case .parade: drawParade(ctx, sz, buckets: 32)
                            case .none: return
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                    .frame(width: 80, height: 30)
                } else {
                    Canvas { ctx, sz in
                        switch mode {
                            case .luminance: drawBars(ctx, sz, channels: [(lumaData, .white)], buckets: nil, opacity: 0.78)
                            case .color: drawBars(ctx, sz, channels: rgbChannels, buckets: nil, opacity: 0.65)
                            case .waveform: drawWaveform(ctx, sz, outCols: WaveformConstants.wfCols)
                            case .parade: drawParade(ctx, sz, buckets: nil)
                            case .none: return
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                    
                    Text(mode.rawValue.uppercased())
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundColor(.white.opacity(0.45))
                        .padding(.horizontal, 6)
                        .padding(.bottom, 3)
                }
            }
        }
    }
}
