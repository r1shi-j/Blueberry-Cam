internal import AVFoundation
internal import Photos
import SwiftUI

@MainActor @Observable
final class PermissionModel {
    enum Status {
        case undetermined, granted, denied
    }
    
    var cameraStatus: Status = .undetermined
    var photosStatus: Status = .undetermined
    
    var allGranted: Bool {
        cameraStatus == .granted && photosStatus == .granted
    }
    
    var anyDenied: Bool {
        cameraStatus == .denied || photosStatus == .denied
    }
    
    func checkAndRequest() async {
        await checkCamera()
        await checkPhotos()
    }
    
    private func checkCamera() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized:
                cameraStatus = .granted
            case .notDetermined:
                let granted = await AVCaptureDevice.requestAccess(for: .video)
                cameraStatus = granted ? .granted : .denied
            default:
                cameraStatus = .denied
        }
    }
    
    private func checkPhotos() async {
        // Step 1: Ensure at least add-only access for saving photos.
        var addStatus = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        if addStatus == .notDetermined {
            addStatus = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        }
        guard addStatus == .authorized || addStatus == .limited else {
            photosStatus = .denied
            return
        }
        photosStatus = .granted
        
        // Step 2: Ask for read/write once (enables album management).
        // iOS only shows this prompt once — if declined, add-only access
        // remains and photos save to the camera roll without album sorting.
        let readWriteStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if readWriteStatus == .notDetermined {
            _ = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        }
    }
}
