import Foundation
import LockedCameraCapture
internal import Photos

extension BlueberryCamApp {
    /// Tracks session URLs that have already been processed so the live stream
    /// and the snapshot scan don't double-count the same session.
    private static let processedURLs = ProcessedURLSet()
    
    func detectLockedCaptureSessions() async {
        for await update in LockedCameraCaptureManager.shared.sessionContentUpdates {
            if case .added(let url) = update {
                guard Self.processedURLs.insert(url) else { continue }
                await addSessionPhotosToAlbum(at: url)
            }
        }
    }
    
    func scanExistingSessions() async {
        for url in LockedCameraCaptureManager.shared.sessionContentURLs {
            guard Self.processedURLs.insert(url) else { continue }
            await addSessionPhotosToAlbum(at: url)
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
        
        let photoCount = ids.count
        
        // Only attempt album operations if we have read access (.readWrite).
        // Checking .addOnly here would trigger an implicit .readWrite prompt.
        let readStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        let canRead = readStatus == .authorized || readStatus == .limited
        
        if canRead {
            // Use the retry helper — Photos may not have indexed the assets yet
            // immediately after the locked camera extension saved them.
            guard let assets = await fetchAllAssets(withIdentifiers: ids) else {
                // Exhausted retries — photos were likely deleted or are inaccessible.
                // Invalidate the session so it isn't reprocessed on every launch.
                Task { try? await LockedCameraCaptureManager.shared.invalidateSessionContent(at: sessionURL) }
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
        
        // Increment and invalidate — we confirmed the photos exist (or we have add-only access
        // and trust the manifest).
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
            try? await Task.sleep(for: .seconds(1))
            delay = min(delay * 2, 4.0)
        }
        
        let partial = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        return partial.count > 0 ? partial : nil
    }
}

// MARK: - Thread-safe set to track processed session URLs
final class ProcessedURLSet: @unchecked Sendable {
    private var urls = Set<URL>()
    private let lock = NSLock()
    
    /// Returns `true` if the URL was newly inserted, `false` if it was already present.
    func insert(_ url: URL) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return urls.insert(url).inserted
    }
}
