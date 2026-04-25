internal import AVFoundation
import CoreImage
import Foundation
import UIKit

extension CameraModel: AVCaptureMetadataOutputObjectsDelegate {
    nonisolated func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        // Extract values before crossing isolation boundary (metadataObjects is non-Sendable)
        let firstString = (metadataObjects.first as? AVMetadataMachineReadableCodeObject)?.stringValue
        
        Task { @MainActor in
            guard self.recognizeBarcodes, !self.isTimerCountingDown else {
                self.detectedCodeURL = nil
                self.detectedCodeString = nil
                return
            }
            
            if let stringValue = firstString {
                
                // If it's the code we just ignored, check the cooldown
                if let ignoreDate = self.ignoredCodes[stringValue] {
                    if Date().timeIntervalSince(ignoreDate) < 30 {
                        return
                    } else {
                        // Cooldown expired, we can process it again
                        self.ignoredCodes.removeValue(forKey: stringValue)
                    }
                }
                
                let targetURL: URL?
                if let url = URL(string: stringValue), url.scheme != nil {
                    targetURL = url
                } else {
                    // It's a barcode (numbers/text), provide a search link
                    let encoded = stringValue.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? stringValue
                    targetURL = URL(string: "https://www.google.com/search?q=\(encoded)")
                }
                
                guard let finalURL = targetURL else { return }
                
                // Avoid rapid UI flickering if it's the same URL
                if self.detectedCodeURL != finalURL {
                    self.detectedCodeURL = finalURL
                    self.detectedCodeString = stringValue
                    UIPasteboard.general.string = stringValue
                }
                
                // Reset the task since we just saw the code
                self.barcodeResetTask?.cancel()
                self.barcodeResetTask = Task { @MainActor in
                    try? await Task.sleep(for: .seconds(2))
                    if !Task.isCancelled {
                        self.detectedCodeURL = nil
                        self.detectedCodeString = nil
                    }
                }
            }
        }
    }
    
    func updateMetadataOutputStatus() {
        let isEnabled = recognizeBarcodes && !isTimerCountingDown
        let types = supportedMetadataTypes
        
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            self.session.beginConfiguration()
            
            if isEnabled {
                let available = self.metadataOutput.availableMetadataObjectTypes
                let toSet = types.filter { available.contains($0) }
                self.metadataOutput.metadataObjectTypes = toSet
            } else {
                self.metadataOutput.metadataObjectTypes = []
            }
            
            self.session.commitConfiguration()
        }
        
        if !isEnabled {
            detectedCodeURL = nil
            detectedCodeString = nil
            barcodeResetTask?.cancel()
            barcodeResetTask = nil
        }
    }
}
