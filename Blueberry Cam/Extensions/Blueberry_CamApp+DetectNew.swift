import Foundation
import LockedCameraCapture
import Photos

extension Blueberry_CamApp {
    func detectLockedCaptureSessions() async {
        for await update in LockedCameraCaptureManager.shared.sessionContentUpdates {
            if case .added(let url) = update {
                await addSessionPhotosToAlbum(at: url)
            }
        }
    }
    
    func addSessionPhotosToAlbum(at sessionURL: URL) async {
        let manifestURL = sessionURL.appendingPathComponent("manifest.txt")
        guard let manifest = try? String(contentsOf: manifestURL, encoding: .utf8) else {
            Task { try? await LockedCameraCaptureManager.shared.invalidateSessionContent(at: sessionURL) }
            return
        }
        
        let ids = manifest
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        
        guard !ids.isEmpty else {
            Task { try? await LockedCameraCaptureManager.shared.invalidateSessionContent(at: sessionURL) }
            return
        }
        
        let albumID = resolveAlbumID()
        let album = albumID.flatMap {
            PHAssetCollection.fetchAssetCollections(
                withLocalIdentifiers: [$0], options: nil
            ).firstObject
        }
        guard let album else { return }
        
        let assets = PHAsset.fetchAssets(
            withLocalIdentifiers: ids, options: nil
        )
        guard assets.count > 0 else {
            return  // don't invalidate — retry next time app opens
        }
        
        var toAdd: [PHAsset] = []
        let albumAssets = PHAsset.fetchAssets(in: album, options: nil)
        var albumIDs = Set<String>()
        albumAssets.enumerateObjects { a, _, _ in albumIDs.insert(a.localIdentifier) }
        assets.enumerateObjects { a, _, _ in
            if !albumIDs.contains(a.localIdentifier) { toAdd.append(a) }
        }
        
        guard !toAdd.isEmpty else {
            Task { try? await LockedCameraCaptureManager.shared.invalidateSessionContent(at: sessionURL) }
            return
        }
        
        await withCheckedContinuation { continuation in
            PHPhotoLibrary.shared().performChanges({
                PHAssetCollectionChangeRequest(for: album)?
                    .addAssets(toAdd as NSArray)
            }) { success, _ in
                if success {
                    DispatchQueue.main.async { self.shutterCount += toAdd.count }
                }
                continuation.resume()
            }
        }
        
        Task { try? await LockedCameraCaptureManager.shared.invalidateSessionContent(at: sessionURL) }
    }
}
