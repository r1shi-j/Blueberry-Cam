import AVFoundation
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
        let wantsZebra = zebraEnabledForAnalysis
        let wantsClipping = clippingEnabledForAnalysis
        let modeSmall = histogramModeForAnalysisSmall
        let modeLarge = histogramModeForAnalysisLarge
        let wantsHistogramSmall = modeSmall != .none
        let wantsHistogramLarge = modeLarge != .none
        let wantsWaveform = modeSmall == .waveform || modeLarge == .waveform
        let wantsColorHistogram = modeSmall == .color || modeSmall == .parade || modeLarge == .color || modeLarge == .parade
        let wantsAnyAnalysis = wantsZebra || wantsClipping || wantsHistogramSmall || wantsHistogramLarge
        
        // Generate loupe image from center crop (every 4th frame for performance)
        if wantsLoupe, frameNumber.isMultiple(of: 4) {
            let fullW = CVPixelBufferGetWidth(pixelBuffer)
            let fullH = CVPixelBufferGetHeight(pixelBuffer)
            let pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
            
            if pixelFormat == kCVPixelFormatType_32BGRA {
                CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
                let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
                guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else {
                    CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
                    return
                }
                
                let cropSize = min(fullW, fullH) / 9
                let cropX = (fullW - cropSize) / 2
                let cropY = (fullH - cropSize) / 2
                let outSize = 200
                
                if let ctx = CGContext(
                    data: nil,
                    width: outSize,
                    height: outSize,
                    bitsPerComponent: 8,
                    bytesPerRow: outSize * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
                ) {
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
                    if let cgImage = cgImage {
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
        
        guard wantsAnyAnalysis else { return }
        
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
        let step = 8
        let sampleWidth = max(1, width  / step)
        let sampleHeight = max(1, height / step)
        let sampleCount  = sampleWidth * sampleHeight
        var zebra = wantsZebra ? [UInt8](repeating: 0, count: sampleCount) : []
        var clipping = wantsClipping ? [UInt8](repeating: 0, count: sampleCount) : []
        
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
                return (l, l, l, l)
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
        let zebraMask = zebra
        let capturedWfRGBN = wfRGBN
        let clipMask = clipping
        
        Task { @MainActor in
            if let normalizedHistogram = normalizedHistogram { self.histogramData = normalizedHistogram }
            if let normR = normR { self.redHistogram = normR }
            if let normG = normG { self.greenHistogram = normG }
            if let normB = normB { self.blueHistogram = normB }
            self.waveformData = capturedWfRGBN
            self.analysisGridSize = analysisSize
            self.zebraMask = zebraMask
            self.clippingMask = clipMask
        }
    }
}
