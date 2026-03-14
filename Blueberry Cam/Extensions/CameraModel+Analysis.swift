internal import AVFoundation
import Foundation
import CoreMedia

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
        
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        
        let pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        
        var hist = [Float](repeating: 0, count: 256)
        var rHist = [Float](repeating: 0, count: 256)
        var gHist = [Float](repeating: 0, count: 256)
        var bHist = [Float](repeating: 0, count: 256)
        var count: Float = 0
        let step = 8
        let sampleWidth = max(1, width  / step)
        let sampleHeight = max(1, height / step)
        let sampleCount  = sampleWidth * sampleHeight
        var lumaGrid = [Float](repeating: 0, count: sampleCount)
        var zebra = [UInt8](repeating: 0, count: sampleCount)
        var clipping = [UInt8](repeating: 0, count: sampleCount)
        
        // Waveform accumulators: X = horizontal position, Y = brightness level
        let wfCols = CameraModel.wfCols
        let wfRows = CameraModel.wfRows
        var wfRSum = [Float](repeating: 0, count: wfCols * wfRows)
        var wfGSum = [Float](repeating: 0, count: wfCols * wfRows)
        var wfBSum = [Float](repeating: 0, count: wfCols * wfRows)
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
                zebra[idx]    = (r >= 220 || g >= 220 || b >= 220) ? 1 : 0
                clipping[idx] = (r >= 250 || g >= 250 || b >= 250) ? 1 : 0
                hist[min(Int(luma), 255)]  += 1
                rHist[min(Int(r), 255)] += 1
                gHist[min(Int(g), 255)] += 1
                bHist[min(Int(b), 255)] += 1
                count += 1
                
                // Map to waveform cell: col = horizontal position, row = brightness
                let wfCol = min(wfCols - 1, px * wfCols / max(width, 1))
                let wfRow = min(wfRows - 1, Int(luma) * wfRows / 256)
                let wfIdx = wfRow * wfCols + wfCol
                wfRSum[wfIdx] += r / 255.0
                wfGSum[wfIdx] += g / 255.0
                wfBSum[wfIdx] += b / 255.0
                wfCount[wfIdx] += 1
            }
        }
        
        var peaking = [UInt8](repeating: 0, count: sampleCount)
        
        let depthGrid = (depthData != nil) ? extractDepthGrid(from: depthData!, targetWidth: sampleWidth, targetHeight: sampleHeight) : nil
        
        if sampleWidth > 4, sampleHeight > 4 {
            var edgeMap = [Float](repeating: 0, count: sampleCount)
            var edgeSum: Float = 0
            var edgeSumSquares: Float = 0
            var edgeCount: Float = 0
            var edgeMax: Float = 0
            
            for y in 1..<(sampleHeight - 1) {
                for x in 1..<(sampleWidth - 1) {
                    let i = y * sampleWidth + x
                    let tl = lumaGrid[(y-1) * sampleWidth + (x-1)]
                    let tc = lumaGrid[(y-1) * sampleWidth + x]
                    let tr = lumaGrid[(y-1) * sampleWidth + (x+1)]
                    let ml = lumaGrid[y * sampleWidth + (x-1)]
                    let mr = lumaGrid[y * sampleWidth + (x+1)]
                    let bl = lumaGrid[(y+1) * sampleWidth + (x-1)]
                    let bc = lumaGrid[(y+1) * sampleWidth + x]
                    let br = lumaGrid[(y+1) * sampleWidth + (x+1)]
                    
                    let gx = -tl - (2*ml) - bl + tr + (2*mr) + br
                    let gy = -tl - (2*tc) - tr + bl + (2*bc) + br
                    let edge = sqrt(gx*gx + gy*gy)
                    
                    // LiDAR Augmentation: Only count edges if they are "plausible" for the current focus
                    // Focus Distance Heuristic: maps 0.0 (infinity) to 1.0 (near) lensPosition 
                    // to a roughly usable depth range.
                    if let depth = depthGrid?[i] {
                        let curLens = self.lastLensPosition
                        // lensPosition 1.0 is near (~0.12m), 0.0 is infinity (~100m+)
                        // Simple inverse mapping for depth masking
                        // focalDepth is a rough estimate in meters
                        let focalDepth = 0.12 / max(0.001, Double(curLens)) 
                        let diff = abs(Double(depth) - focalDepth)
                        let tolerance = focalDepth * 0.5 // Wider tolerance for distant objects
                        
                        // If way out of focal plane, suppress edge magnitude
                        if diff > tolerance {
                            edgeMap[i] = edge * 0.3
                        } else {
                            edgeMap[i] = edge
                        }
                    } else {
                        edgeMap[i] = edge
                    }
                    
                    edgeSum += edgeMap[i]
                    edgeSumSquares += edgeMap[i] * edgeMap[i]
                    edgeCount += 1
                    if edgeMap[i] > edgeMax { edgeMax = edgeMap[i] }
                }
            }
            
            let edgeMean = edgeCount > 0 ? edgeSum / edgeCount : 0
            let variance = edgeCount > 0 ? max(0, (edgeSumSquares / edgeCount) - (edgeMean * edgeMean)) : 0
            let edgeSigma = sqrt(variance)
            
            let adaptiveThreshold = max(40, edgeMean + (1.5 * edgeSigma))
            let threshold = max(adaptiveThreshold, edgeMax * 0.25)
            
            var preliminaryPeaking = [UInt8](repeating: 0, count: sampleCount)
            for y in 2..<(sampleHeight - 2) {
                for x in 2..<(sampleWidth - 2) {
                    let i = y * sampleWidth + x
                    let edge = edgeMap[i]
                    guard edge >= threshold else { continue }
                    
                    // Local Maxima Suppression: Only peak if this is the absolute strongest in 3x3
                    let isLocalMaximum = edge >= edgeMap[i-1] && edge >= edgeMap[i+1] &&
                    edge >= edgeMap[i-sampleWidth] && edge >= edgeMap[i+sampleWidth] &&
                    edge >= edgeMap[i-sampleWidth-1] && edge >= edgeMap[i-sampleWidth+1] &&
                    edge >= edgeMap[i+sampleWidth-1] && edge >= edgeMap[i+sampleWidth+1]
                    
                    if isLocalMaximum { preliminaryPeaking[i] = 1 }
                }
            }
            
            for y in 2..<(sampleHeight - 2) {
                for x in 2..<(sampleWidth - 2) {
                    let i = y * sampleWidth + x
                    if preliminaryPeaking[i] == 1 {
                        peaking[i] = 1 // No clustering for now to maximize dots
                    }
                }
            }
            
//            let dotCount = peaking.filter { $0 == 1 }.count
//            if _frameCounter.next() % 30 == 0 {
//                print("DEBUG Analysis (Sensitive): dots=\(dotCount), max=\(Int(edgeMax)), thresh=\(Int(threshold))")
//            }
        }
        
        let normalizedHistogram: [Float]? = count > 0 ? hist.map  { $0 / count } : nil
        let normR = count > 0 ? rHist.map { $0 / count } : nil
        let normG = count > 0 ? gHist.map { $0 / count } : nil
        let normB = count > 0 ? bHist.map { $0 / count } : nil
        
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
                wfRGBN[i * 4] = wfRSum[i] / n
                wfRGBN[i * 4 + 1] = wfGSum[i] / n
                wfRGBN[i * 4 + 2] = wfBSum[i] / n
                wfRGBN[i * 4 + 3] = min(1, (n / cMax) * 1.4)
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
        let depthMap = depthData.depthDataMap
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }
        
        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        let format = CVPixelBufferGetPixelFormatType(depthMap)
        
        var result = [Float](repeating: 0, count: targetWidth * targetHeight)
        
        guard let baseAddress = CVPixelBufferGetBaseAddress(depthMap) else { return nil }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)
        
        for ty in 0..<targetHeight {
            let sy = min(height - 1, ty * height / targetHeight)
            let row = baseAddress.advanced(by: sy * bytesPerRow)
            
            for tx in 0..<targetWidth {
                let sx = min(width - 1, tx * width / targetWidth)
                var depthValue: Float = 0
                
                if format == kCVPixelFormatType_DepthFloat32 {
                    depthValue = row.assumingMemoryBound(to: Float32.self)[sx]
                } else if format == kCVPixelFormatType_DepthFloat16 {
                    // Float16 is a bit trickier in Swift without direct casting, but we can try
                    // For the sake of this implementation, we'll assume Float32 or convert if needed.
                    // Most LiDAR devices provide Float32 depth maps.
                    depthValue = Float(row.assumingMemoryBound(to: UInt16.self)[sx]) / 1000.0 // hacky fallback
                }
                
                result[ty * targetWidth + tx] = depthValue
            }
        }
        
        return result
    }
}
