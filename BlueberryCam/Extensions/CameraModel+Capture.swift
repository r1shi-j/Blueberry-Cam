internal import AVFoundation
import Foundation
import Photos

extension CameraModel: AVCapturePhotoCaptureDelegate {
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
        let isHeif = !photo.isRawPhoto && self._pendingCaptureModeBox.value == .heif
        Task {
            let loc = await MainActor.run { self.currentLocation }
            self.saveToPhotos(data: data, location: loc, isDNG: photo.isRawPhoto, isHEIF: isHeif)
        }
    }
    
    private nonisolated func saveToPhotos(data: Data, location: CLLocation?, isDNG: Bool, isHEIF: Bool = false) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                Task { @MainActor in self.errorMessage = "Photos access denied."; self.showError = true }
                return
            }
            
            // 1. Resolve the "Blueberry Cam" album, creating it only when necessary.
            let albumID = resolveAlbumID()
            let album = albumID.flatMap {
                PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [$0], options: nil).firstObject
            }
            
            PHPhotoLibrary.shared().performChanges({
                let opts = PHAssetResourceCreationOptions()
                opts.uniformTypeIdentifier = BundleIDs.UTI(isDNG: isDNG, isHEIF: isHEIF)
                let req = PHAssetCreationRequest.forAsset()
                if let loc = location {
                    req.location = loc
                }
                req.addResource(with: .photo, data: data, options: opts)
                
                // 2. Add the new asset to the album
                if let album, let placeholder = req.placeholderForCreatedAsset {
                    let albumReq = PHAssetCollectionChangeRequest(for: album)
                    albumReq?.addAssets([placeholder] as NSArray)
                }
            }) { success, error in
                Task { @MainActor in
                    if !success {
                        self.errorMessage = error?.localizedDescription ?? "Unknown save error."
                        self.showError = true
                    }
                }
            }
        }
    }
}
