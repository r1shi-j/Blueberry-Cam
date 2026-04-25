internal import AVFoundation
import Foundation

extension LockedCameraModel: AVCaptureVideoDataOutputSampleBufferDelegate {
    nonisolated func captureOutput(_ output: AVCaptureOutput,
                                   didOutput sampleBuffer: CMSampleBuffer,
                                   from connection: AVCaptureConnection) {
        Task { @MainActor in
            if let d = self.device {
                self.liveISO = d.iso
                self.liveShutter = Self.formatShutter(d.exposureDuration)
                let tnt = d.temperatureAndTintValues(for: d.deviceWhiteBalanceGains)
                self.liveWB = "\(Int(tnt.temperature))K"
                self.liveFocus = Double(d.lensPosition).formatted(.number.precision(.fractionLength(2)))
            }
        }
    }
}
