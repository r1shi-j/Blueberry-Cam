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
        guard content.hasContent else {
            return false
        }
        
        // Only attempt album operations if we have read access (.readWrite).
        // Checking .addOnly here would trigger an implicit .readWrite prompt.
        let readStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        let canRead = readStatus == .authorized || readStatus == .limited
        
        if !content.assetIdentifiers.isEmpty {
            guard content.isReadyToProcess else {
                return false
            }
            
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
            return false
        }
        
        let assets = await fetchAssets(matching: content.captureRecords)
        guard assets.count == content.captureRecords.count else {
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
        var previous: LockedCaptureSessionContent?
        var stableReadyPollCount = 0
        
        for attempt in 1...maxAttempts {
            if latest.isReadyToProcess {
                if latest == previous {
                    stableReadyPollCount += 1
                } else {
                    stableReadyPollCount = 0
                }
                
                if stableReadyPollCount >= 1 {
                    return latest
                }
            } else {
                stableReadyPollCount = 0
            }
            
            guard attempt < maxAttempts else {
                return latest
            }
            
            previous = latest
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
            captureRecords: readCaptureRecords(from: capturesURL)
        )
    }
    
    private func readLines(from url: URL) -> [String] {
        ((try? String(contentsOf: url, encoding: .utf8)) ?? "")
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
    
    private func readCaptureRecords(from url: URL) -> [LockedCaptureRecord] {
        readLines(from: url).compactMap(LockedCaptureRecord.init(line:))
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
    
    private func fetchAssets(matching records: [LockedCaptureRecord],
                             maxAttempts: Int = 10,
                             delay: Duration = .milliseconds(500)) async -> [PHAsset] {
        guard !records.isEmpty else { return [] }
        
        var matched: [LockedCaptureRecord: PHAsset] = [:]
        
        for attempt in 1...maxAttempts {
            matched = fetchRecentAssets(matching: records)
            if matched.count == records.count {
                return records.compactMap { matched[$0] }
            }
            
            guard attempt < maxAttempts else { break }
            try? await Task.sleep(for: delay)
        }
        
        return records.compactMap { matched[$0] }
    }
    
    private func fetchRecentAssets(matching records: [LockedCaptureRecord]) -> [LockedCaptureRecord: PHAsset] {
        let options = PHFetchOptions()
        options.fetchLimit = 250
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        
        let recordsByFilename = Dictionary(grouping: records, by: \.filename)
        let result = PHAsset.fetchAssets(with: options)
        var matches: [LockedCaptureRecord: PHAsset] = [:]
        result.enumerateObjects { asset, _, stop in
            let resources = PHAssetResource.assetResources(for: asset)
            for resource in resources {
                let candidates = (recordsByFilename[resource.originalFilename] ?? [])
                    .filter { matches[$0] == nil }
                guard let record = bestRecord(for: asset, candidates: candidates) else { continue }
                matches[record] = asset
                if matches.count == records.count {
                    stop.pointee = true
                }
                return
            }
        }
        
        return matches
    }
    
    private func bestRecord(for asset: PHAsset, candidates: [LockedCaptureRecord]) -> LockedCaptureRecord? {
        guard let creationDate = asset.creationDate else {
            return candidates.first
        }
        
        return candidates.min { lhs, rhs in
            let lhsDistance = lhs.captureDate.map { abs($0.timeIntervalSince(creationDate)) } ?? .greatestFiniteMagnitude
            let rhsDistance = rhs.captureDate.map { abs($0.timeIntervalSince(creationDate)) } ?? .greatestFiniteMagnitude
            return lhsDistance < rhsDistance
        }
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
        
        return nil
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

private struct LockedCaptureSessionContent: Equatable {
    let assetIdentifiers: [String]
    let captureRecords: [LockedCaptureRecord]
    
    var hasContent: Bool {
        !assetIdentifiers.isEmpty || !captureRecords.isEmpty
    }
    
    var isReadyToProcess: Bool {
        guard !assetIdentifiers.isEmpty else { return false }
        return captureRecords.isEmpty || assetIdentifiers.count >= captureRecords.count
    }
}

private struct LockedCaptureRecord: Equatable, Hashable, Sendable {
    let filename: String
    let captureDate: Date?
    
    nonisolated init?(line: String) {
        let parts = line.split(separator: "|", maxSplits: 1).map(String.init)
        guard let filename = parts.first, !filename.isEmpty else { return nil }
        
        self.filename = filename
        if parts.count > 1, let milliseconds = Double(parts[1]) {
            self.captureDate = Date(timeIntervalSince1970: milliseconds / 1000)
        } else {
            self.captureDate = nil
        }
    }
}
