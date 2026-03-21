import Foundation
import LockedCameraCapture
internal import Photos

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
        
        // Always increment shutter count — we know photos were taken from the manifest
        let photoCount = ids.count
        
        // Only attempt album operations if we have read access
        let readStatus = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        let canRead = readStatus == .authorized || readStatus == .limited
        
        if canRead {
            let assets = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
            guard assets.count > 0 else {
                // Photos not yet in library, don't invalidate — retry next time
                DispatchQueue.main.async { self.shutterCount += photoCount }
                return
            }
            
            let albumID = resolveAlbumID()
            let album = albumID.flatMap {
                PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [$0], options: nil).firstObject
            }
            
            var toAdd: [PHAsset] = []
            if let album {
                let albumAssets = PHAsset.fetchAssets(in: album, options: nil)
                var albumIDs = Set<String>()
                albumAssets.enumerateObjects { a, _, _ in albumIDs.insert(a.localIdentifier) }
                assets.enumerateObjects { a, _, _ in
                    if !albumIDs.contains(a.localIdentifier) { toAdd.append(a) }
                }
            }
            
            await withCheckedContinuation { continuation in
                PHPhotoLibrary.shared().performChanges({
                    if let album, !toAdd.isEmpty {
                        PHAssetCollectionChangeRequest(for: album)?.addAssets(toAdd as NSArray)
                    }
                }) { _, _ in
                    continuation.resume()
                }
            }
        }
        
        // Increment regardless of read access
        DispatchQueue.main.async { self.shutterCount += photoCount }
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
