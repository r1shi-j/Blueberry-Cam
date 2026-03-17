internal import AVFoundation
import Foundation
import Photos

extension LockedCameraModel: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput,
                                 didFinishProcessingPhoto photo: AVCapturePhoto,
                                 error: Error?) {
        if let error {
            Task { @MainActor in self.errorMessage = error.localizedDescription; self.showError = true }
            return
        }
        guard let data = photo.fileDataRepresentation() else {
            Task { @MainActor in self.errorMessage = "Failed to get photo data."; self.showError = true }
            return
        }
        let isHeif = !photo.isRawPhoto && _pendingCaptureModeBox.value == .heif
        let url = _sessionContentURLBox.value  // read via box, same pattern as CaptureModeBox
        saveToSessionDirectory(data: data, isDNG: photo.isRawPhoto, isHEIF: isHeif, sessionURL: url)
    }
    
    private nonisolated func saveToSessionDirectory(data: Data, isDNG: Bool, isHEIF: Bool, sessionURL: URL?) {
        guard let sessionURL else {
            saveDirectlyToPhotos(data: data, isDNG: isDNG, isHEIF: isHEIF, sessionURL: sessionURL)
            return
        }
        
        let ext = isDNG ? "dng" : (isHEIF ? "heic" : "jpg")
        let filename = "IMG_\(Int(Date().timeIntervalSince1970)).\(ext)"
        let fileURL = sessionURL.appendingPathComponent(filename)
        
        do {
            try data.write(to: fileURL)
            // Also save immediately to camera roll so photo is available straight away
            saveDirectlyToPhotos(data: data, isDNG: isDNG, isHEIF: isHEIF, sessionURL: sessionURL)
        } catch {
            Task { @MainActor in self.errorMessage = error.localizedDescription; self.showError = true }
        }
    }
    
    private nonisolated func saveDirectlyToPhotos(data: Data, isDNG: Bool, isHEIF: Bool, sessionURL: URL?) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                Task { @MainActor in self.errorMessage = "Photos access denied."; self.showError = true }
                return
            }
            var placeholderID: String?
            PHPhotoLibrary.shared().performChanges({
                let opts = PHAssetResourceCreationOptions()
                opts.uniformTypeIdentifier = isDNG ? "com.adobe.raw-image" : (isHEIF ? "public.heic" : "public.jpeg")
                let req = PHAssetCreationRequest.forAsset()
                req.addResource(with: .photo, data: data, options: opts)
                placeholderID = req.placeholderForCreatedAsset?.localIdentifier
            }) { success, error in
                if success, let id = placeholderID, let sessionURL {
                    // Write the localIdentifier to a manifest file in the session dir
                    // so the main app can find the exact asset later
                    let manifestURL = sessionURL.appendingPathComponent("manifest.txt")
                    var existing = (try? String(contentsOf: manifestURL, encoding: .utf8)) ?? ""
                    existing += id + "\n"
                    try? existing.write(to: manifestURL, atomically: true, encoding: .utf8)
                }
                if let error {
                    Task { @MainActor in self.errorMessage = error.localizedDescription; self.showError = true }
                }
            }
        }
    }
}
