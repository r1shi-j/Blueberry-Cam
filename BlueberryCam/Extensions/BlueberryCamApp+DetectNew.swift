import Foundation
import LockedCameraCapture
import Photos

extension BlueberryCamApp {
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
        guard let albumID, let album = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [albumID], options: nil).firstObject else { return }
        guard let assets = await fetchAllAssets(withIdentifiers: ids) else { return }
        
        let albumAssets = PHAsset.fetchAssets(in: album, options: nil)
        var existingIDs = Set<String>()
        albumAssets.enumerateObjects { asset, _, _ in existingIDs.insert(asset.localIdentifier) }
        
        var toAdd: [PHAsset] = []
        assets.enumerateObjects { asset, _, _ in
            if !existingIDs.contains(asset.localIdentifier) {
                toAdd.append(asset)
            }
        }
        
        guard !toAdd.isEmpty else {
            Task { try? await LockedCameraCaptureManager.shared.invalidateSessionContent(at: sessionURL) }
            return
        }
        
        await withCheckedContinuation { continuation in
            PHPhotoLibrary.shared().performChanges({
                PHAssetCollectionChangeRequest(for: album)?
                    .addAssets(toAdd as NSArray)
            }) { success, error in
                if success {
                    DispatchQueue.main.async {
                        self.shutterCount += toAdd.count
                    }
                }
                continuation.resume()
            }
        }
        
        Task { try? await LockedCameraCaptureManager.shared.invalidateSessionContent(at: sessionURL) }
    }
    
    // MARK: - Retry helper
    
    private func fetchAllAssets(withIdentifiers ids: [String],
                                maxAttempts: Int = 6,
                                initialDelaySeconds: Double = 0.3) async -> PHFetchResult<PHAsset>? {
        let expectedCount = ids.count
        var delay = initialDelaySeconds
        
        for attempt in 1...maxAttempts {
            let result = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
            if result.count >= expectedCount {
                return result
            }
            guard attempt < maxAttempts else { break }
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            delay = min(delay * 2, 4.0)
        }
        
        let partial = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        return partial.count > 0 ? partial : nil
    }
}
