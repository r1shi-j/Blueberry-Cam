import AVFoundation
import CoreImage
import Foundation
import UIKit

extension CameraModel: AVCaptureMetadataOutputObjectsDelegate {
    nonisolated func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        let firstString = (metadataObjects.first as? AVMetadataMachineReadableCodeObject)?.stringValue
        
        Task { @MainActor in
            guard self.recognizeBarcodes else {
                self.detectedCodeURL = nil
                return
            }
            
            if let stringValue = firstString {
                if let ignoreDate = self.ignoredCodes[stringValue] {
                    if Date().timeIntervalSince(ignoreDate) < 30 {
                        return
                    } else {
                        self.ignoredCodes.removeValue(forKey: stringValue)
                    }
                }
                
                let targetURL: URL?
                if let url = URL(string: stringValue), url.scheme != nil {
                    targetURL = url
                } else {
                    let encoded = stringValue.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? stringValue
                    targetURL = URL(string: "https://www.google.com/search?q=\(encoded)")
                }
                
                guard let finalURL = targetURL else { return }
                
                if self.detectedCodeURL != finalURL {
                    self.detectedCodeURL = finalURL
                    self.detectedCodeString = stringValue
                    UIPasteboard.general.string = stringValue
                }
                
                self.barcodeResetTask?.cancel()
                self.barcodeResetTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    if !Task.isCancelled {
                        self.detectedCodeURL = nil
                        self.detectedCodeString = nil
                    }
                }
            }
        }
    }
    
    func updateMetadataOutputStatus() {
        let isEnabled = recognizeBarcodes
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
        
        if !recognizeBarcodes {
            detectedCodeURL = nil
            detectedCodeString = nil
            barcodeResetTask?.cancel()
        }
    }
}
