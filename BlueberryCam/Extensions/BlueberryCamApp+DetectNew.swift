import Foundation
import LockedCameraCapture
internal import Photos

extension BlueberryCamApp {
    /// Tracks session URLs that have already been processed so the live stream
    /// and the snapshot scan don't double-count the same session.
    private static let processedURLs = ProcessedURLSet()
    
    func detectLockedCaptureSessions() async {
        for await update in LockedCameraCaptureManager.shared.sessionContentUpdates {
            switch update {
                case .initial(let urls):
                    for url in urls {
                        await processLockedCaptureSession(at: url)
                    }
                case .added(let url):
                    await processLockedCaptureSession(at: url)
                case .removed:
                    break
                @unknown default:
                    break
            }
        }
    }
    
    func scanExistingSessions() async {
        for url in LockedCameraCaptureManager.shared.sessionContentURLs {
            await processLockedCaptureSession(at: url)
        }
    }
    
    private func processLockedCaptureSession(at sessionURL: URL) async {
        guard Self.processedURLs.insert(sessionURL) else { return }
        
        let didHandle = await addSessionPhotosToAlbum(at: sessionURL)
        if !didHandle {
            Self.processedURLs.remove(sessionURL)
        }
    }
    
    @discardableResult
    func addSessionPhotosToAlbum(at sessionURL: URL) async -> Bool {
        let content = await waitForSessionContent(at: sessionURL)
        guard !content.assetIdentifiers.isEmpty || !content.filenames.isEmpty else {
            return false
        }
        
        // Only attempt album operations if we have read access (.readWrite).
        // Checking .addOnly here would trigger an implicit .readWrite prompt.
        let readStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        let canRead = readStatus == .authorized || readStatus == .limited
        
        if !content.assetIdentifiers.isEmpty {
            let photoCount = content.assetIdentifiers.count
            
            // Use the retry helper — Photos may not have indexed the assets yet
            // immediately after the locked camera extension saved them.
            if canRead {
                guard let assets = await fetchAllAssets(withIdentifiers: content.assetIdentifiers) else {
                    // Not ready yet. Keep the session content and allow a future scan/update to retry.
                    return false
                }
                
                await addAssetsToBlueberryAlbum(assets)
            }
            
            // Increment and invalidate — we confirmed the photos exist (or we have add-only access
            // and trust the manifest).
            await MainActor.run { self.shutterCount += photoCount }
            try? await LockedCameraCaptureManager.shared.invalidateSessionContent(at: sessionURL)
            return true
        }
        
        if !canRead {
            await MainActor.run { self.shutterCount += content.filenames.count }
            try? await LockedCameraCaptureManager.shared.invalidateSessionContent(at: sessionURL)
            return true
        }
        
        let assets = await fetchAssets(withOriginalFilenames: Set(content.filenames))
        guard assets.count == content.filenames.count else {
            // The PhotoKit save may still be in flight, or the extension may have been suspended
            // before PhotoKit wrote the asset. Keep this session around for a later retry.
            return false
        }
        
        await addAssetsToBlueberryAlbum(assets)
        await MainActor.run { self.shutterCount += assets.count }
        try? await LockedCameraCaptureManager.shared.invalidateSessionContent(at: sessionURL)
        return true
    }
    
    private func waitForSessionContent(at sessionURL: URL,
                                       maxAttempts: Int = 10,
                                       delay: Duration = .milliseconds(500)) async -> LockedCaptureSessionContent {
        var latest = readSessionContent(at: sessionURL)
        for attempt in 1...maxAttempts {
            if !latest.assetIdentifiers.isEmpty {
                return latest
            }
            
            guard attempt < maxAttempts else { break }
            try? await Task.sleep(for: delay)
            latest = readSessionContent(at: sessionURL)
        }
        return latest
    }
    
    private func readSessionContent(at sessionURL: URL) -> LockedCaptureSessionContent {
        let manifestURL = sessionURL.appendingPathComponent("manifest.txt")
        let capturesURL = sessionURL.appendingPathComponent("captures.txt")
        
        return LockedCaptureSessionContent(
            assetIdentifiers: readLines(from: manifestURL),
            filenames: readLines(from: capturesURL)
        )
    }
    
    private func readLines(from url: URL) -> [String] {
        ((try? String(contentsOf: url, encoding: .utf8)) ?? "")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
    
    private func addAssetsToBlueberryAlbum(_ assets: [PHAsset]) async {
        guard !assets.isEmpty else { return }
        
        let albumID = resolveAlbumID()
        let album = albumID.flatMap {
            PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [$0], options: nil).firstObject
        }
        
        guard let album else { return }
        
        let albumAssets = PHAsset.fetchAssets(in: album, options: nil)
        var albumIDs = Set<String>()
        albumAssets.enumerateObjects { asset, _, _ in
            albumIDs.insert(asset.localIdentifier)
        }
        
        let toAdd = assets.filter { !albumIDs.contains($0.localIdentifier) }
        guard !toAdd.isEmpty else { return }
        
        await withCheckedContinuation { continuation in
            PHPhotoLibrary.shared().performChanges({
                PHAssetCollectionChangeRequest(for: album)?.addAssets(toAdd as NSArray)
            }) { _, _ in
                continuation.resume()
            }
        }
    }
    
    private func addAssetsToBlueberryAlbum(_ assets: PHFetchResult<PHAsset>) async {
        var assetArray: [PHAsset] = []
        assets.enumerateObjects { asset, _, _ in
            assetArray.append(asset)
        }
        await addAssetsToBlueberryAlbum(assetArray)
    }
    
    private func fetchAssets(withOriginalFilenames filenames: Set<String>,
                             maxAttempts: Int = 10,
                             delay: Duration = .milliseconds(500)) async -> [PHAsset] {
        guard !filenames.isEmpty else { return [] }
        
        var matched: [String: PHAsset] = [:]
        
        for attempt in 1...maxAttempts {
            matched = fetchRecentAssets(withOriginalFilenames: filenames)
            if matched.count == filenames.count {
                return filenames.compactMap { matched[$0] }
            }
            
            guard attempt < maxAttempts else { break }
            try? await Task.sleep(for: delay)
        }
        
        return filenames.compactMap { matched[$0] }
    }
    
    private func fetchRecentAssets(withOriginalFilenames filenames: Set<String>) -> [String: PHAsset] {
        let options = PHFetchOptions()
        options.fetchLimit = 250
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        
        let result = PHAsset.fetchAssets(with: options)
        var matches: [String: PHAsset] = [:]
        result.enumerateObjects { asset, _, stop in
            let resources = PHAssetResource.assetResources(for: asset)
            for resource in resources where filenames.contains(resource.originalFilename) {
                matches[resource.originalFilename] = asset
                if matches.count == filenames.count {
                    stop.pointee = true
                }
                return
            }
        }
        
        return matches
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
            try? await Task.sleep(for: .seconds(delay))
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
    
    func remove(_ url: URL) {
        lock.lock()
        urls.remove(url)
        lock.unlock()
    }
}

private struct LockedCaptureSessionContent {
    let assetIdentifiers: [String]
    let filenames: [String]
}
