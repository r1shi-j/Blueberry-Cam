internal import AVFoundation
import Foundation

extension CameraModel: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(_ output: AVCaptureOutput,
                                   didOutput sampleBuffer: CMSampleBuffer,
                                   from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        Task { @MainActor in
            if let d = self.device {
                self.liveISO = d.iso
                self.liveShutter = Self.formatShutter(d.exposureDuration)
                let tnt = d.temperatureAndTintValues(for: d.deviceWhiteBalanceGains)
                self.liveWB = "\(Int(tnt.temperature))K"
                self.liveFocus = String(format: "%.2f", d.lensPosition)
            }
        }
        
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        
        let pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        
        var hist  = [Float](repeating: 0, count: 256)
        var rHist = [Float](repeating: 0, count: 256)
        var gHist = [Float](repeating: 0, count: 256)
        var bHist = [Float](repeating: 0, count: 256)
        var count: Float = 0
        let step = 8
        let sampleWidth  = max(1, width  / step)
        let sampleHeight = max(1, height / step)
        let sampleCount  = sampleWidth * sampleHeight
        var lumaGrid = [Float](repeating: 0, count: sampleCount)
        var zebra    = [UInt8](repeating: 0, count: sampleCount)
        
        // Waveform accumulators: X = horizontal position, Y = brightness level
        let wfCols = CameraModel.wfCols
        let wfRows = CameraModel.wfRows
        var wfRSum  = [Float](repeating: 0, count: wfCols * wfRows)
        var wfGSum  = [Float](repeating: 0, count: wfCols * wfRows)
        var wfBSum  = [Float](repeating: 0, count: wfCols * wfRows)
        var wfCount = [Float](repeating: 0, count: wfCols * wfRows)
        
        let readPixel: (Int, Int) -> (r: Float, g: Float, b: Float, luma: Float)
        if pixelFormat == kCVPixelFormatType_32BGRA {
            let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
            guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return }
            readPixel = { x, y in
                let row = base.advanced(by: y * bytesPerRow).assumingMemoryBound(to: UInt8.self)
                let o = x * 4
                let b = Float(row[o]); let g = Float(row[o + 1]); let r = Float(row[o + 2])
                return (r, g, b, 0.299 * r + 0.587 * g + 0.114 * b)
            }
        } else if CVPixelBufferIsPlanar(pixelBuffer), CVPixelBufferGetPlaneCount(pixelBuffer) > 0 {
            let yW  = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
            let yH  = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
            let yBR = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
            guard let yBase = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0) else { return }
            readPixel = { x, y in
                let row = yBase.advanced(by: min(yH - 1, y) * yBR).assumingMemoryBound(to: UInt8.self)
                let l = Float(row[min(yW - 1, x)])
                return (l, l, l, l)   // planar YCbCr — luma only, treat as neutral grey
            }
        } else {
            return
        }
        
        for sy in 0..<sampleHeight {
            let py = min(height - 1, sy * step)
            for sx in 0..<sampleWidth {
                let px = min(width - 1, sx * step)
                let (r, g, b, luma) = readPixel(px, py)
                let idx = sy * sampleWidth + sx
                lumaGrid[idx] = luma
                zebra[idx] = luma >= 235 ? 1 : 0
                hist[min(Int(luma), 255)]  += 1
                rHist[min(Int(r), 255)] += 1
                gHist[min(Int(g), 255)] += 1
                bHist[min(Int(b), 255)] += 1
                count += 1
                
                // Map to waveform cell: col = horizontal position, row = brightness
                let wfCol = min(wfCols - 1, px * wfCols / max(width, 1))
                let wfRow = min(wfRows - 1, Int(luma) * wfRows / 256)
                let wfIdx = wfRow * wfCols + wfCol
                wfRSum[wfIdx]  += r / 255.0
                wfGSum[wfIdx]  += g / 255.0
                wfBSum[wfIdx]  += b / 255.0
                wfCount[wfIdx] += 1
            }
        }
        
        var peaking = [UInt8](repeating: 0, count: sampleCount)
        if sampleWidth > 4 && sampleHeight > 4 {
            var edgeMap = [Float](repeating: 0, count: sampleCount)
            var edgeSum: Float = 0
            var edgeSumSquares: Float = 0
            var edgeCount: Float = 0
            var edgeMax: Float = 0
            
            // Sobel edge magnitude gives a stronger, cleaner focus signal than a simple 2-axis diff.
            for y in 1..<(sampleHeight - 1) {
                for x in 1..<(sampleWidth - 1) {
                    let i = y * sampleWidth + x
                    let tl = lumaGrid[(y - 1) * sampleWidth + (x - 1)]
                    let tc = lumaGrid[(y - 1) * sampleWidth + x]
                    let tr = lumaGrid[(y - 1) * sampleWidth + (x + 1)]
                    let ml = lumaGrid[y * sampleWidth + (x - 1)]
                    let mr = lumaGrid[y * sampleWidth + (x + 1)]
                    let bl = lumaGrid[(y + 1) * sampleWidth + (x - 1)]
                    let bc = lumaGrid[(y + 1) * sampleWidth + x]
                    let br = lumaGrid[(y + 1) * sampleWidth + (x + 1)]
                    
                    let gx = -tl - (2 * ml) - bl + tr + (2 * mr) + br
                    let gy = -tl - (2 * tc) - tr + bl + (2 * bc) + br
                    let edge = sqrt((gx * gx) + (gy * gy))
                    edgeMap[i] = edge
                    edgeSum += edge
                    edgeSumSquares += edge * edge
                    edgeCount += 1
                    if edge > edgeMax { edgeMax = edge }
                }
            }
            
            let edgeMean = edgeCount > 0 ? edgeSum / edgeCount : 0
            let variance = edgeCount > 0 ? max(0, (edgeSumSquares / edgeCount) - (edgeMean * edgeMean)) : 0
            let edgeSigma = sqrt(variance)
            let adaptiveThreshold = max(115, edgeMean + (4.2 * edgeSigma))
            let threshold = max(adaptiveThreshold, edgeMax * 0.68)
            
            // Keep only local maxima and sparsify points to achieve precise "dot" peaking.
            for y in 2..<(sampleHeight - 2) {
                for x in 2..<(sampleWidth - 2) {
                    let i = y * sampleWidth + x
                    let edge = edgeMap[i]
                    guard edge >= threshold else { continue }
                    guard lumaGrid[i] > 28 else { continue }
                    
                    let left = edgeMap[i - 1]
                    let right = edgeMap[i + 1]
                    let up = edgeMap[i - sampleWidth]
                    let down = edgeMap[i + sampleWidth]
                    let upLeft = edgeMap[i - sampleWidth - 1]
                    let upRight = edgeMap[i - sampleWidth + 1]
                    let downLeft = edgeMap[i + sampleWidth - 1]
                    let downRight = edgeMap[i + sampleWidth + 1]
                    
                    let isLocalMaximum = edge >= left &&
                    edge >= right &&
                    edge >= up &&
                    edge >= down &&
                    edge >= upLeft &&
                    edge >= upRight &&
                    edge >= downLeft &&
                    edge >= downRight
                    
                    if isLocalMaximum {
                        peaking[i] = 1
                    }
                }
            }
            
            // Remove isolated speckles; keep only clustered peaks so out-of-focus scenes
            // don't show random noise dots.
            var clustered = [UInt8](repeating: 0, count: sampleCount)
            for y in 2..<(sampleHeight - 2) {
                for x in 2..<(sampleWidth - 2) {
                    let i = y * sampleWidth + x
                    guard peaking[i] == 1 else { continue }
                    
                    var neighbors = 0
                    for ny in (y - 1)...(y + 1) {
                        for nx in (x - 1)...(x + 1) {
                            if nx == x && ny == y { continue }
                            if peaking[ny * sampleWidth + nx] == 1 {
                                neighbors += 1
                            }
                        }
                    }
                    
                    if neighbors >= 2 {
                        clustered[i] = 1
                    }
                }
            }
            peaking = clustered
        }
        
        let normalizedHistogram: [Float]? = count > 0 ? hist.map  { $0 / count } : nil
        let normR = count > 0 ? rHist.map { $0 / count } : nil
        let normG = count > 0 ? gHist.map { $0 / count } : nil
        let normB = count > 0 ? bHist.map { $0 / count } : nil
        
        // Build RGBN waveform: per-cell avg colour + per-COLUMN normalised density.
        // Normalising per column (not globally) means every column lights up regardless
        // of how many pixels mapped there — gives a continuous oscilloscope-style trace.
        var colMax = [Float](repeating: 0, count: wfCols)
        for col in 0..<wfCols {
            for row in 0..<wfRows {
                let n = wfCount[row * wfCols + col]
                if n > colMax[col] { colMax[col] = n }
            }
        }
        var wfRGBN = [Float](repeating: 0, count: wfCols * wfRows * 4)
        for col in 0..<wfCols {
            let cMax = colMax[col]
            guard cMax > 0 else { continue }
            for row in 0..<wfRows {
                let i = row * wfCols + col
                let n = wfCount[i]
                guard n > 0 else { continue }
                wfRGBN[i * 4] = wfRSum[i] / n   // avg r (0–1)
                wfRGBN[i * 4 + 1] = wfGSum[i] / n   // avg g (0–1)
                wfRGBN[i * 4 + 2] = wfBSum[i] / n   // avg b (0–1)
                                                    // density relative to the busiest row in this column — smooth falloff
                wfRGBN[i * 4 + 3] = min(1, (n / cMax) * 1.4)
            }
        }
        
        let analysisSize  = CGSize(width: sampleWidth, height: sampleHeight)
        let peakingMask   = peaking
        let zebraMask     = zebra
        let capturedWfRGBN = wfRGBN   // local copy so Swift 6 is happy crossing isolation boundary
        
        Task { @MainActor in
            if let normalizedHistogram { self.histogramData  = normalizedHistogram }
            if let normR { self.redHistogram   = normR }
            if let normG { self.greenHistogram = normG }
            if let normB { self.blueHistogram  = normB }
            self.waveformData = capturedWfRGBN
            self.analysisGridSize = analysisSize
            self.focusPeakingMask = peakingMask
            self.zebraMask = zebraMask
        }
    }
}
