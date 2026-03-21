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
        switch PHPhotoLibrary.authorizationStatus(for: .addOnly) {
            case .authorized, .limited:
                photosStatus = .granted
            case .notDetermined:
                let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
                photosStatus = (status == .authorized || status == .limited) ? .granted : .denied
            default:
                photosStatus = .denied
        }
    }
}
