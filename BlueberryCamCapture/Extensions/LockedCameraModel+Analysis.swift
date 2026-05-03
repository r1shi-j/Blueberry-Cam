internal import AVFoundation
import Foundation

extension LockedCameraModel: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(_ output: AVCaptureOutput,
                                   didOutput sampleBuffer: CMSampleBuffer,
                                   from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        processFrame(pixelBuffer: pixelBuffer)
    }
    
    nonisolated func processFrame(pixelBuffer: CVPixelBuffer) {
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
