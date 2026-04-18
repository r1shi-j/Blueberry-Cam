import AVFoundation
import Photos
import SwiftUI
internal import Combine

@MainActor
final class PermissionModel: ObservableObject {
    enum Status {
        case undetermined, granted, denied
    }
    
    @Published var cameraStatus: Status = .undetermined
    @Published var photosStatus: Status = .undetermined
    
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
        var addStatus = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        if addStatus == .notDetermined {
            addStatus = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        }
        guard addStatus == .authorized || addStatus == .limited else {
            photosStatus = .denied
            return
        }
        photosStatus = .granted
        
        let readWriteStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if readWriteStatus == .notDetermined {
            _ = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        }
    }
}
