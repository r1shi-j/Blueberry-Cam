internal import AVFoundation
import CoreMedia
import Foundation

extension CameraModel: AVCaptureDataOutputSynchronizerDelegate, AVCaptureVideoDataOutputSampleBufferDelegate {
    // FALLBACK: Used when LiDAR/Depth is not available or connections fail
    nonisolated func captureOutput(_ output: AVCaptureOutput,
                                   didOutput sampleBuffer: CMSampleBuffer,
                                   from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        processFrame(pixelBuffer: pixelBuffer, depthData: nil)
    }
    
    // MAIN: Used for LiDAR/Depth synchronized frames
    nonisolated func dataOutputSynchronizer(_ synchronizer: AVCaptureDataOutputSynchronizer,
                                            didOutput synchronizedDataCollection: AVCaptureSynchronizedDataCollection) {
        
        guard let syncedVideoData = synchronizedDataCollection.synchronizedData(for: videoOutput) as? AVFoundation.AVCaptureSynchronizedSampleBufferData,
              !syncedVideoData.sampleBufferWasDropped else { return }
        
        let sampleBuffer = syncedVideoData.sampleBuffer
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        let syncedDepthData = synchronizedDataCollection.synchronizedData(for: depthOutput) as? AVFoundation.AVCaptureSynchronizedDepthData
        let depthData = syncedDepthData?.depthData
        
        processFrame(pixelBuffer: pixelBuffer, depthData: depthData)
    }
    
    nonisolated func processFrame(pixelBuffer: CVPixelBuffer, depthData: AVDepthData?) {
        Task { @MainActor in
            if let d = self.device {
                self.liveISO = d.iso
                self.liveShutter = Self.formatShutter(d.exposureDuration)
                let tnt = d.temperatureAndTintValues(for: d.deviceWhiteBalanceGains)
                self.liveWB = "\(Int(tnt.temperature))K"
                self.liveFocus = String(format: "%.2f", d.lensPosition)
            }
        }
        
        let frameNumber = frameCounter.next()
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
        let wantsAnyAnalysis = wantsPeaking || wantsZebra || wantsClipping || wantsHistogramSmall || wantsHistogramLarge
        
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
            if !peakingTemporalScores.isEmpty {
                peakingTemporalScores = []
            }
            return
        }
        
        if wantsPeaking, frameNumber.isMultiple(of: 2) {
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
        let step = wantsPeaking ? 6 : 8
        let sampleWidth = max(1, width  / step)
        let sampleHeight = max(1, height / step)
        let sampleCount  = sampleWidth * sampleHeight
        var lumaGrid = wantsPeaking ? [Float](repeating: 0, count: sampleCount) : []
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
                if wantsPeaking {
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
        
        var peaking = [UInt8](repeating: 0, count: sampleCount)
        
        let depthGrid = wantsPeaking ? depthData.flatMap {
            extractDepthGrid(from: $0, targetWidth: sampleWidth, targetHeight: sampleHeight)
        } : nil
        
        if wantsPeaking, sampleWidth > 5, sampleHeight > 5 {
            var scoreMap = [Float](repeating: 0, count: sampleCount)
            var directionMap = [UInt8](repeating: 0, count: sampleCount)
            var scoreSum: Float = 0
            var scoreSumSquares: Float = 0
            var scoreCount: Float = 0
            var scoreMax: Float = 0
            let focusDepth = focusDistanceEstimate(
                lensPosition: lastLensPosition,
                minimumFocusDistance: minimumFocusDistanceForAnalysis
            )
            
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
                    
                    let gx = -3 * tl - 10 * ml - 3 * bl + 3 * tr + 10 * mr + 3 * br
                    let gy = -3 * tl - 10 * tc - 3 * tr + 3 * bl + 10 * bc + 3 * br
                    let gradient = sqrt(gx * gx + gy * gy)
                    let laplacian = abs((4 * mc) - tc - bc - ml - mr)
                    let wideGradient = sqrt(pow(mr2 - ml2, 2) + pow(bc2 - tc2, 2))
                    let coarseContrast = abs(mc - ringMean)
                    let microResponse = max(0, (laplacian * 2.8) - (wideGradient * 1.35) - (coarseContrast * 1.15))
                    let narrowness = max(0, gradient - (wideGradient * 1.1))
                    var score = microResponse + (narrowness * 0.22)
                    
                    if let depthGrid {
                        let depth = depthGrid[i]
                        if depth.isFinite, depth > 0 {
                            score *= depthWeight(
                                for: depth,
                                focusDepth: focusDepth,
                                depthGrid: depthGrid,
                                index: i,
                                rowStride: sampleWidth
                            )
                        }
                    }
                    
                    if peakingTemporalScores.count == sampleCount {
                        score = max(score, peakingTemporalScores[i] * 0.55)
                    }
                    
                    scoreMap[i] = score
                    directionMap[i] = quantizedGradientDirection(gx: gx, gy: gy)
                    scoreSum += score
                    scoreSumSquares += score * score
                    scoreCount += 1
                    if score > scoreMax { scoreMax = score }
                }
            }
            
            peakingTemporalScores = scoreMap.map { $0 * 0.78 }
            
            let scoreMean = scoreCount > 0 ? scoreSum / scoreCount : 0
            let variance = scoreCount > 0 ? max(0, (scoreSumSquares / scoreCount) - (scoreMean * scoreMean)) : 0
            let scoreSigma = sqrt(variance)
            let percentileThreshold = percentile(of: scoreMap, at: 0.97)
            let threshold = max(scoreMean + (scoreSigma * 1.6), percentileThreshold * 0.92, scoreMax * 0.3)
            let highThreshold = max(threshold * 1.35, scoreMax * 0.45)
            
            var preliminaryPeaking = [UInt8](repeating: 0, count: sampleCount)
            for y in 2..<(sampleHeight - 2) {
                for x in 2..<(sampleWidth - 2) {
                    let i = y * sampleWidth + x
                    let score = scoreMap[i]
                    guard score >= threshold else { continue }
                    guard isDirectionalMaximum(scoreMap, index: i, rowStride: sampleWidth, direction: directionMap[i]) else {
                        continue
                    }
                    
                    let normalized = min(1, max(0, (score - threshold) / max(highThreshold - threshold, 1)))
                    let intensity = UInt8(max(140, Int(140 + (normalized * 115))))
                    preliminaryPeaking[i] = intensity
                }
            }
            
            for y in 2..<(sampleHeight - 2) {
                for x in 2..<(sampleWidth - 2) {
                    let i = y * sampleWidth + x
                    let intensity = preliminaryPeaking[i]
                    guard intensity > 0 else { continue }
                    
                    peaking[i] = max(peaking[i], intensity)
                    if intensity > 220 {
                        peaking[i - 1] = max(peaking[i - 1], intensity / 4)
                        peaking[i + 1] = max(peaking[i + 1], intensity / 4)
                        peaking[i - sampleWidth] = max(peaking[i - sampleWidth], intensity / 4)
                        peaking[i + sampleWidth] = max(peaking[i + sampleWidth], intensity / 4)
                    }
                }
            }
        } else {
            peakingTemporalScores = []
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
        let peakingMask = peaking
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
            self.focusPeakingMask = peakingMask
            self.zebraMask = zebraMask
            self.clippingMask = clipMask
        }
    }
    
    nonisolated func extractDepthGrid(from depthData: AVDepthData, targetWidth: Int, targetHeight: Int) -> [Float]? {
        let convertedDepth = depthData.converting(toDepthDataType: kCVPixelFormatType_DepthFloat32)
        let depthMap = convertedDepth.depthDataMap
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }
        
        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        
        var result = [Float](repeating: 0, count: targetWidth * targetHeight)
        
        guard let baseAddress = CVPixelBufferGetBaseAddress(depthMap) else { return nil }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)
        let rowStride = bytesPerRow / MemoryLayout<Float32>.stride
        let floatBase = baseAddress.assumingMemoryBound(to: Float32.self)
        
        for ty in 0..<targetHeight {
            let fy = (Float(ty) + 0.5) * Float(height) / Float(targetHeight) - 0.5
            let y0 = max(0, min(height - 1, Int(floor(fy))))
            let y1 = min(height - 1, y0 + 1)
            let wy = fy - Float(y0)
            
            for tx in 0..<targetWidth {
                let fx = (Float(tx) + 0.5) * Float(width) / Float(targetWidth) - 0.5
                let x0 = max(0, min(width - 1, Int(floor(fx))))
                let x1 = min(width - 1, x0 + 1)
                let wx = fx - Float(x0)
                
                let d00 = floatBase[(y0 * rowStride) + x0]
                let d10 = floatBase[(y0 * rowStride) + x1]
                let d01 = floatBase[(y1 * rowStride) + x0]
                let d11 = floatBase[(y1 * rowStride) + x1]
                
                let top = d00 + ((d10 - d00) * wx)
                let bottom = d01 + ((d11 - d01) * wx)
                let depthValue = top + ((bottom - top) * wy)
                result[ty * targetWidth + tx] = depthValue.isFinite && depthValue > 0 ? depthValue : 0
            }
        }
        
        return result
    }
    
    nonisolated func focusDistanceEstimate(lensPosition: Float, minimumFocusDistance: Float) -> Float? {
        guard minimumFocusDistance > 0 else { return nil }
        
        let clampedLens = min(max(lensPosition, 0), 1)
        let nearDistance = max(0.08, minimumFocusDistance)
        let farDistance: Float = 8.0
        let nearDiopters = 1 / nearDistance
        let farDiopters = 1 / farDistance
        
        // AVCaptureDevice documents 0.0 as nearest focus and 1.0 as furthest.
        // Interpolating in diopters behaves much closer to real focus travel than linear meters.
        let t = pow(1 - clampedLens, 1.35)
        let diopters = farDiopters + ((nearDiopters - farDiopters) * t)
        return diopters > 0 ? (1 / diopters) : nil
    }
    
    nonisolated func depthWeight(for depth: Float,
                                 focusDepth: Float?,
                                 depthGrid: [Float],
                                 index: Int,
                                 rowStride: Int) -> Float {
        var weight: Float = 1.0
        
        if let focusDepth, focusDepth.isFinite, focusDepth > 0 {
            let tolerance = max(0.05, focusDepth * 0.16)
            let delta = abs(depth - focusDepth)
            let normalized = delta / tolerance
            let planeWeight = exp(-(normalized * normalized) * 0.9)
            weight *= max(0.03, planeWeight)
        }
        
        let left = depthGrid[index - 1]
        let right = depthGrid[index + 1]
        let up = depthGrid[index - rowStride]
        let down = depthGrid[index + rowStride]
        let neighborhood = [left, right, up, down].filter { $0.isFinite && $0 > 0 }
        if !neighborhood.isEmpty {
            let averageDelta = neighborhood.reduce(0) { $0 + abs($1 - depth) } / Float(neighborhood.count)
            let discontinuityPenalty = min(1, averageDelta / max(depth * 0.08, 0.03))
            weight *= 1.0 - (discontinuityPenalty * 0.22)
        }
        
        return max(0.02, min(weight, 1.02))
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
    
    nonisolated func percentile(of values: [Float], at percentile: Float) -> Float {
        let positives = values.filter { $0 > 0 }
        guard !positives.isEmpty else { return 0 }
        let sorted = positives.sorted()
        let index = min(sorted.count - 1, max(0, Int(Float(sorted.count - 1) * percentile)))
        return sorted[index]
    }
}
