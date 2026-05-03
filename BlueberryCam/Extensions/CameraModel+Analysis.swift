internal import AVFoundation
import CoreMedia
import Foundation

extension CameraModel: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(_ output: AVCaptureOutput,
                                   didOutput sampleBuffer: CMSampleBuffer,
                                   from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        processFrame(pixelBuffer: pixelBuffer)
    }
    
    nonisolated func processFrame(pixelBuffer: CVPixelBuffer) {
        guard !shouldPauseAnalysis else { return }
        
        let frameNumber = frameCounter.next()
        if frameNumber.isMultiple(of: 3) {
            Task { @MainActor in
                if let d = self.device {
                    self.liveISO = d.iso
                    self.liveShutter = Self.formatShutter(d.exposureDuration)
                    let tnt = d.temperatureAndTintValues(for: d.deviceWhiteBalanceGains)
                    self.liveWB = "\(Int(tnt.temperature))K"
                    self.liveFocus = Double(d.lensPosition).formatted(.number.precision(.fractionLength(2)))
                    self.syncAutoRulerValues(
                        iso: d.iso,
                        exposureDuration: d.exposureDuration,
                        whiteBalanceTemperature: tnt.temperature,
                        lensPosition: d.lensPosition
                    )
                }
            }
        }
        
        if frameNumber.isMultiple(of: 6),
           let isBright = sampledViewfinderIsBright(pixelBuffer: pixelBuffer) {
            Task { @MainActor in
                if self.isViewfinderBright != isBright {
                    self.isViewfinderBright = isBright
                }
            }
        }
        
        let wantsLoupe = loupeEnabledForAnalysis
        let wantsPeaking = peakingEnabledForAnalysis
        let wantsZebra = zebraEnabledForAnalysis
        let wantsClipping = clippingEnabledForAnalysis
        let modeSmall = histogramModeForAnalysisSmall
        let modeLarge = histogramModeForAnalysisLarge
        let wantsHistogramSmall = modeSmall != .none
        let wantsHistogramLarge = modeLarge != .none
        let wantsWaveform = modeSmall == .waveform || modeLarge == .waveform
        let wantsColorHistogram = modeSmall == .color || modeSmall == .parade || modeLarge == .color || modeLarge == .parade
        let shouldComputePeaking = wantsPeaking
        let wantsAnyAnalysis = shouldComputePeaking || wantsZebra || wantsClipping || wantsHistogramSmall || wantsHistogramLarge
        
        // Generate loupe image from center crop (every 4th frame for performance)
        if wantsLoupe, frameNumber.isMultiple(of: 4) {
            let fullW = CVPixelBufferGetWidth(pixelBuffer)
            let fullH = CVPixelBufferGetHeight(pixelBuffer)
            let pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
            
            // Only support BGRA for direct crop
            if pixelFormat == kCVPixelFormatType_32BGRA {
                CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
                let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
                guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else {
                    CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
                    return
                }
                
                // Crop center 1/9th of frame → 3× magnification
                let cropSize = min(fullW, fullH) / 9
                let cropX = (fullW - cropSize) / 2
                let cropY = (fullH - cropSize) / 2
                let outSize = 200 // Small output for the loupe circle
                
                if let ctx = CGContext(
                    data: nil,
                    width: outSize,
                    height: outSize,
                    bitsPerComponent: 8,
                    bytesPerRow: outSize * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
                ) {
                    // Scale and draw the crop directly
                    let srcPtr = base.advanced(by: cropY * bytesPerRow + cropX * 4)
                    for dy in 0..<outSize {
                        let sy = dy * cropSize / outSize
                        let srcRow = srcPtr.advanced(by: sy * bytesPerRow)
                        let dstRow = ctx.data!.advanced(by: dy * outSize * 4)
                        for dx in 0..<outSize {
                            let sx = dx * cropSize / outSize
                            dstRow.advanced(by: dx * 4).copyMemory(
                                from: srcRow.advanced(by: sx * 4),
                                byteCount: 4
                            )
                        }
                    }
                    let cgImage = ctx.makeImage()
                    CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
                    if let cgImage {
                        Task { @MainActor in self.loupeImage = cgImage }
                    }
                } else {
                    CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
                }
            }
        } else if !wantsLoupe {
            Task { @MainActor in
                if self.loupeImage != nil { self.loupeImage = nil }
            }
        }
        
        guard wantsAnyAnalysis else {
            if !wantsPeaking, !peakingTemporalScores.isEmpty {
                peakingTemporalScores = []
            }
            return
        }
        
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        
        let pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        
        var hist = (wantsHistogramSmall || wantsHistogramLarge) ? [Float](repeating: 0, count: 256) : []
        var rHist = wantsColorHistogram ? [Float](repeating: 0, count: 256) : []
        var gHist = wantsColorHistogram ? [Float](repeating: 0, count: 256) : []
        var bHist = wantsColorHistogram ? [Float](repeating: 0, count: 256) : []
        var count: Float = 0
        let step = wantsPeaking ? 5 : 8
        let sampleWidth = max(1, width  / step)
        let sampleHeight = max(1, height / step)
        let sampleCount  = sampleWidth * sampleHeight
        var lumaGrid = shouldComputePeaking ? [Float](repeating: 0, count: sampleCount) : []
        var zebra = wantsZebra ? [UInt8](repeating: 0, count: sampleCount) : []
        var clipping = wantsClipping ? [UInt8](repeating: 0, count: sampleCount) : []
        
        // Waveform accumulators: X = horizontal position, Y = brightness level
        let wfCols = CameraModel.wfCols
        let wfRows = CameraModel.wfRows
        var wfRSum = wantsWaveform ? [Float](repeating: 0, count: wfCols * wfRows) : []
        var wfGSum = wantsWaveform ? [Float](repeating: 0, count: wfCols * wfRows) : []
        var wfBSum = wantsWaveform ? [Float](repeating: 0, count: wfCols * wfRows) : []
        var wfCount = wantsWaveform ? [Float](repeating: 0, count: wfCols * wfRows) : []
        
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
                if shouldComputePeaking {
                    lumaGrid[idx] = luma
                }
                if wantsZebra {
                    zebra[idx] = (r >= 230 || g >= 230 || b >= 230) ? 1 : 0
                }
                if wantsClipping {
                    clipping[idx] = (r >= 250 || g >= 250 || b >= 250) ? 1 : 0
                }
                if wantsHistogramSmall || wantsHistogramLarge {
                    hist[min(Int(luma), 255)] += 1
                    count += 1
                }
                if wantsColorHistogram {
                    rHist[min(Int(r), 255)] += 1
                    gHist[min(Int(g), 255)] += 1
                    bHist[min(Int(b), 255)] += 1
                }
                if wantsWaveform {
                    let wfCol = min(wfCols - 1, px * wfCols / max(width, 1))
                    let wfRow = min(wfRows - 1, Int(luma) * wfRows / 256)
                    let wfIdx = wfRow * wfCols + wfCol
                    wfRSum[wfIdx] += r / 255.0
                    wfGSum[wfIdx] += g / 255.0
                    wfBSum[wfIdx] += b / 255.0
                    wfCount[wfIdx] += 1
                }
            }
        }
        
        var peakingMaskToPublish: [UInt8]?
        
        if shouldComputePeaking, sampleWidth > 5, sampleHeight > 5 {
            var peaking = [UInt8](repeating: 0, count: sampleCount)
            var scoreMap = [Float](repeating: 0, count: sampleCount)
            var directionMap = [UInt8](repeating: 0, count: sampleCount)
            var scoreSum: Float = 0
            var scoreSumSquares: Float = 0
            var scoreCount: Float = 0
            var scoreMax: Float = 0
            
            for y in 2..<(sampleHeight - 2) {
                for x in 2..<(sampleWidth - 2) {
                    let i = y * sampleWidth + x
                    let tl = lumaGrid[(y - 1) * sampleWidth + (x - 1)]
                    let tc = lumaGrid[(y - 1) * sampleWidth + x]
                    let tr = lumaGrid[(y - 1) * sampleWidth + (x + 1)]
                    let ml = lumaGrid[y * sampleWidth + (x - 1)]
                    let mc = lumaGrid[i]
                    let mr = lumaGrid[y * sampleWidth + (x + 1)]
                    let bl = lumaGrid[(y + 1) * sampleWidth + (x - 1)]
                    let bc = lumaGrid[(y + 1) * sampleWidth + x]
                    let br = lumaGrid[(y + 1) * sampleWidth + (x + 1)]
                    let tc2 = lumaGrid[(y - 2) * sampleWidth + x]
                    let ml2 = lumaGrid[y * sampleWidth + (x - 2)]
                    let mr2 = lumaGrid[y * sampleWidth + (x + 2)]
                    let bc2 = lumaGrid[(y + 2) * sampleWidth + x]
                    let ringMean = (tc2 + ml2 + mr2 + bc2) * 0.25
                    
                    let gx = -tl - (2 * ml) - bl + tr + (2 * mr) + br
                    let gy = -tl - (2 * tc) - tr + bl + (2 * bc) + br
                    let gradientMagnitude = abs(gx) + abs(gy)
                    let laplacian = abs((4 * mc) - tc - bc - ml - mr)
                    let broadGradient = abs(mr2 - ml2) + abs(bc2 - tc2)
                    let broadContrast = abs(mc - ringMean)
                    let fineResponse = max(0, (laplacian * 2.6) - (broadGradient * 0.58) - (broadContrast * 0.42))
                    var score = fineResponse * (laplacian + (gradientMagnitude * 0.08))
                    
                    if peakingTemporalScores.count == sampleCount {
                        score = max(score, peakingTemporalScores[i] * 0.06)
                    }
                    
                    scoreMap[i] = score
                    directionMap[i] = quantizedGradientDirection(gx: gx, gy: gy)
                    scoreSum += score
                    scoreSumSquares += score * score
                    scoreCount += 1
                    if score > scoreMax { scoreMax = score }
                }
            }
            
            peakingTemporalScores = scoreMap.map { $0 * 0.16 }
            
            let scoreMean = scoreCount > 0 ? scoreSum / scoreCount : 0
            let variance = scoreCount > 0 ? max(0, (scoreSumSquares / scoreCount) - (scoreMean * scoreMean)) : 0
            let scoreSigma = sqrt(variance)
            let percentileThreshold = percentile(of: scoreMap, at: 0.91, sampleStride: 3)
            let threshold = max(scoreMean + (scoreSigma * 0.95), percentileThreshold * 0.78, scoreMax * 0.045, 55)
            let highThreshold = max(threshold * 1.45, scoreMax * 0.28)
            
            for y in 2..<(sampleHeight - 2) {
                for x in 2..<(sampleWidth - 2) {
                    let i = y * sampleWidth + x
                    let score = scoreMap[i]
                    guard score >= threshold else { continue }
                    let isStrongEdge = score >= highThreshold * 0.72
                    guard isStrongEdge || isDirectionalMaximum(scoreMap, index: i, rowStride: sampleWidth, direction: directionMap[i]) else {
                        continue
                    }
                    
                    let normalized = min(1, max(0, (score - threshold) / max(highThreshold - threshold, 1)))
                    peaking[i] = UInt8(max(120, Int(120 + (normalized * 135))))
                }
            }
            peakingMaskToPublish = peaking
        } else {
            if !wantsPeaking {
                peakingTemporalScores = []
                peakingMaskToPublish = []
            }
        }
        
        let normalizedHistogram: [Float]? = (wantsHistogramSmall || wantsHistogramLarge) && count > 0 ? hist.map  { $0 / count } : nil
        let normR = wantsColorHistogram && count > 0 ? rHist.map { $0 / count } : nil
        let normG = wantsColorHistogram && count > 0 ? gHist.map { $0 / count } : nil
        let normB = wantsColorHistogram && count > 0 ? bHist.map { $0 / count } : nil
        
        var wfRGBN: [Float] = []
        if wantsWaveform {
            var colMax = [Float](repeating: 0, count: wfCols)
            for col in 0..<wfCols {
                for row in 0..<wfRows {
                    let n = wfCount[row * wfCols + col]
                    if n > colMax[col] { colMax[col] = n }
                }
            }
            wfRGBN = [Float](repeating: 0, count: wfCols * wfRows * 4)
            for col in 0..<wfCols {
                let cMax = colMax[col]
                guard cMax > 0 else { continue }
                for row in 0..<wfRows {
                    let i = row * wfCols + col
                    let n = wfCount[i]
                    guard n > 0 else { continue }
                    wfRGBN[i * 4] = wfRSum[i] / n
                    wfRGBN[i * 4 + 1] = wfGSum[i] / n
                    wfRGBN[i * 4 + 2] = wfBSum[i] / n
                    wfRGBN[i * 4 + 3] = min(1, (n / cMax) * 1.4)
                }
            }
        }
        
        let analysisSize = CGSize(width: sampleWidth, height: sampleHeight)
        let peakingMask = peakingMaskToPublish
        let zebraMask = zebra
        let capturedWfRGBN = wfRGBN
        let clipMask = clipping
        
        Task { @MainActor in
            if let normalizedHistogram { self.histogramData = normalizedHistogram }
            if let normR { self.redHistogram = normR }
            if let normG { self.greenHistogram = normG }
            if let normB { self.blueHistogram = normB }
            self.waveformData = capturedWfRGBN
            self.analysisGridSize = analysisSize
            if let peakingMask { self.focusPeakingMask = peakingMask }
            self.zebraMask = zebraMask
            self.clippingMask = clipMask
        }
    }
    
    nonisolated func quantizedGradientDirection(gx: Float, gy: Float) -> UInt8 {
        let ax = abs(gx)
        let ay = abs(gy)
        if ax > ay * 2 { return 0 }
        if ay > ax * 2 { return 1 }
        return (gx * gy) >= 0 ? 2 : 3
    }
    
    nonisolated func isDirectionalMaximum(_ scoreMap: [Float], index: Int, rowStride: Int, direction: UInt8) -> Bool {
        let score = scoreMap[index]
        switch direction {
            case 0:
                return score >= scoreMap[index - 1] && score >= scoreMap[index + 1]
            case 1:
                return score >= scoreMap[index - rowStride] && score >= scoreMap[index + rowStride]
            case 2:
                return score >= scoreMap[index - rowStride - 1] && score >= scoreMap[index + rowStride + 1]
            default:
                return score >= scoreMap[index - rowStride + 1] && score >= scoreMap[index + rowStride - 1]
        }
    }
    
    nonisolated func percentile(of values: [Float], at percentile: Float, sampleStride: Int = 1) -> Float {
        var positives: [Float] = []
        positives.reserveCapacity(max(1, values.count / max(1, sampleStride)))
        for index in stride(from: 0, to: values.count, by: max(1, sampleStride)) {
            let value = values[index]
            if value > 0 {
                positives.append(value)
            }
        }
        guard !positives.isEmpty else { return 0 }
        let sorted = positives.sorted()
        let index = min(sorted.count - 1, max(0, Int(Float(sorted.count - 1) * percentile)))
        return sorted[index]
    }
    
    nonisolated private func sampledViewfinderIsBright(pixelBuffer: CVPixelBuffer) -> Bool? {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        
        let pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        guard width > 0, height > 0 else { return nil }
        
        let cropMinX = width / 5
        let cropMaxX = width - cropMinX
        let cropMinY = height / 5
        let cropMaxY = height - cropMinY
        let sampleStep = 24
        var lumaTotal: Float = 0
        var sampleCount: Float = 0
        
        if pixelFormat == kCVPixelFormatType_32BGRA {
            let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
            guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
            
            for y in stride(from: cropMinY, to: cropMaxY, by: sampleStep) {
                let row = base.advanced(by: y * bytesPerRow).assumingMemoryBound(to: UInt8.self)
                for x in stride(from: cropMinX, to: cropMaxX, by: sampleStep) {
                    let offset = x * 4
                    let b = Float(row[offset])
                    let g = Float(row[offset + 1])
                    let r = Float(row[offset + 2])
                    lumaTotal += 0.299 * r + 0.587 * g + 0.114 * b
                    sampleCount += 1
                }
            }
        } else if CVPixelBufferIsPlanar(pixelBuffer), CVPixelBufferGetPlaneCount(pixelBuffer) > 0 {
            let yWidth = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
            let yHeight = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
            let yBytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
            guard let yBase = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0) else { return nil }
            
            let maxY = min(cropMaxY, yHeight)
            let maxX = min(cropMaxX, yWidth)
            for y in stride(from: min(cropMinY, yHeight - 1), to: maxY, by: sampleStep) {
                let row = yBase.advanced(by: y * yBytesPerRow).assumingMemoryBound(to: UInt8.self)
                for x in stride(from: min(cropMinX, yWidth - 1), to: maxX, by: sampleStep) {
                    lumaTotal += Float(row[x])
                    sampleCount += 1
                }
            }
        } else {
            return nil
        }
        
        guard sampleCount > 0 else { return nil }
        let averageLuma = lumaTotal / sampleCount
        if isViewfinderBrightForAnalysis {
            return averageLuma > 112
        } else {
            return averageLuma > 145
        }
    }
}
