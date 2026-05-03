internal import AVFoundation
import Foundation
internal import Photos

extension LockedCameraModel: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput,
                                 willCapturePhotoFor resolvedSettings: AVCaptureResolvedPhotoSettings) {
        guard let onCapture = _captureContextStore.context(for: resolvedSettings.uniqueID)?.onCapture else { return }
        
        Task { @MainActor in
            onCapture()
        }
    }
    
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput,
                                 didFinishProcessingPhoto photo: AVCapturePhoto,
                                 error: Error?) {
        let uniqueID = photo.resolvedSettings.uniqueID
        let context = _captureContextStore.removeContext(for: uniqueID) ?? LockedPhotoCaptureContext(
            captureMode: _pendingCaptureModeBox.value,
            onCapture: nil
        )
        
        if let error {
            Task { @MainActor in self.errorMessage = error.localizedDescription; self.showError = true }
            return
        }
        guard let data = photo.fileDataRepresentation() else {
            Task { @MainActor in self.errorMessage = "Failed to get photo data."; self.showError = true }
            return
        }
        let isHeif = !photo.isRawPhoto && context.captureMode == .heif
        let url = _sessionContentURLBox.value
        Task {
            saveToSessionDirectory(data: data, isDNG: photo.isRawPhoto, isHEIF: isHeif, sessionURL: url)
        }
    }
    
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput,
                                 didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings,
                                 error: Error?) {
        guard let error,
              _captureContextStore.removeContext(for: resolvedSettings.uniqueID) != nil else { return }
        
        Task { @MainActor in
            self.errorMessage = error.localizedDescription
            self.showError = true
        }
    }
    
    private nonisolated func saveToSessionDirectory(data: Data, isDNG: Bool, isHEIF: Bool, sessionURL: URL?) {
        guard let sessionURL else {
            saveDirectlyToPhotos(data: data, isDNG: isDNG, isHEIF: isHEIF, sessionURL: nil)
            return
        }
        
        let captureDate = Date()
        let filename = Self.nextLockedCaptureFilename(sessionURL: sessionURL, isDNG: isDNG, isHEIF: isHEIF)
        let fileURL = sessionURL.appendingPathComponent(filename)
        
        do {
            try data.write(to: fileURL)
            Self.appendToCaptureList(filename: filename, captureDate: captureDate, sessionURL: sessionURL)
        } catch {
            Task { @MainActor in self.errorMessage = error.localizedDescription; self.showError = true }
            // Still attempt to save directly to Photos even if the session file write fails.
        }
        
        // Always save to Photos — the manifest write happens inside the completion handler
        // once we have a confirmed localIdentifier, so the ordering is guaranteed.
        saveDirectlyToPhotos(data: data, isDNG: isDNG, isHEIF: isHEIF, sessionURL: sessionURL, originalFilename: filename)
    }
    
    private nonisolated func saveDirectlyToPhotos(data: Data, isDNG: Bool, isHEIF: Bool, sessionURL: URL?, originalFilename: String? = nil) {
        let currentStatus = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        
        guard currentStatus == .authorized || currentStatus == .limited else {
            Task { @MainActor in
                self.errorMessage = "Photos access denied. Please enable in Settings."
                self.showError = true
            }
            return
        }
        
        performDirectSave(data: data, isDNG: isDNG, isHEIF: isHEIF, sessionURL: sessionURL, originalFilename: originalFilename)
    }
    
    private nonisolated func performDirectSave(data: Data, isDNG: Bool, isHEIF: Bool, sessionURL: URL?, originalFilename: String?) {
        // Use a local to capture the placeholder ID safely within the performChanges closure.
        // Declared as a class wrapper so it can be mutated inside the closure without a data race.
        final class Box<T>: @unchecked Sendable { var value: T; init(_ v: T) { value = v } }
        let placeholderBox = Box<String?>(nil)
        
        PHPhotoLibrary.shared().performChanges({
            let opts = PHAssetResourceCreationOptions()
            opts.uniformTypeIdentifier = BundleIDs.UTI(isDNG: isDNG, isHEIF: isHEIF)
            opts.originalFilename = originalFilename
            let req = PHAssetCreationRequest.forAsset()
            req.addResource(with: .photo, data: data, options: opts)
            // Capture the identifier while still inside the performChanges block —
            // this is the only safe place to read placeholderForCreatedAsset.
            placeholderBox.value = req.placeholderForCreatedAsset?.localIdentifier
        }) { success, error in
            if let error {
                Task { @MainActor in self.errorMessage = error.localizedDescription; self.showError = true }
                return
            }
            guard success, let id = placeholderBox.value, let sessionURL else { return }
            
            // Write the localIdentifier to the manifest atomically so a concurrent
            // write from rapid-fire captures doesn't corrupt the file.
            Self.appendToManifest(id: id, sessionURL: sessionURL)
        }
    }
    
    /// Appends a single asset local identifier to the session manifest file.
    /// Uses a file-system-level atomic replace so rapid concurrent calls never corrupt the file.
    private nonisolated static func appendToManifest(id: String, sessionURL: URL) {
        appendLine(id, to: "manifest.txt", sessionURL: sessionURL)
    }
    
    /// Appends a captured filename to a lightweight recovery list before PhotoKit finishes.
    private nonisolated static func appendToCaptureList(filename: String, captureDate: Date, sessionURL: URL) {
        let milliseconds = Int(captureDate.timeIntervalSince1970 * 1000)
        appendLine("\(filename)|\(milliseconds)", to: "captures.txt", sessionURL: sessionURL)
    }
    
    private nonisolated static func appendLine(_ line: String, to fileName: String, sessionURL: URL) {
        let manifestURL = sessionURL.appendingPathComponent(fileName)
        
        // Serialize manifest writes for this session URL using a dedicated queue.
        // The label includes the session path so different sessions get different queues.
        let queue = manifestQueue(for: sessionURL)
        queue.sync {
            var existing = (try? String(contentsOf: manifestURL, encoding: .utf8)) ?? ""
            // Guard against duplicate entries (e.g. a retry that already wrote this ID).
            guard !existing.components(separatedBy: "\n").contains(line) else { return }
            existing += line + "\n"
            // Write atomically — replaces the file as a single operation so a crash mid-write
            // leaves the previous version intact rather than a partial file.
            try? existing.write(to: manifestURL, atomically: true, encoding: .utf8)
        }
    }
    
    /// Returns a serial DispatchQueue dedicated to manifest I/O for the given session directory.
    /// Multiple calls with the same URL return the same queue, kept alive in a static dictionary.
    private nonisolated static func manifestQueue(for sessionURL: URL) -> DispatchQueue {
        let key = sessionURL.path
        return manifestQueues.withLock { dict in
            if let existing = dict[key] { return existing }
            let q = DispatchQueue(label: "\(BundleIDs.appID).manifest.\(sessionURL.lastPathComponent)")
            dict[key] = q
            return q
        }
    }
    
    // MARK: - Static storage for per-session manifest queues
    // Using a simple Lock wrapper to avoid importing Synchronization on older toolchains.
    private nonisolated static let manifestQueues = ManifestQueueRegistry()
    private nonisolated static let lockedFilenameLock = NSLock()
    private nonisolated static let lockedFilenameCounterKey = "lockedCaptureFilenameCounter"
    private nonisolated static let lockedFilenameExtensions = ["jpg", "jpeg", "heic", "dng"]
    
    private nonisolated static func nextLockedCaptureFilename(sessionURL: URL, isDNG: Bool, isHEIF: Bool) -> String {
        lockedFilenameLock.lock()
        defer { lockedFilenameLock.unlock() }
        
        let defaults = UserDefaults.standard
        let storedCounter = defaults.object(forKey: lockedFilenameCounterKey) as? Int ?? 0
        var counter = max(
            storedCounter,
            nextCounterAfterExistingLockedCaptures(in: sessionURL),
            nextCounterAfterRecentPhotoLibraryAssets()
        )
        
        while true {
            let stem = lockedFileStem(for: counter)
            if !lockedFileStemExists(stem, in: sessionURL) {
                defaults.set(counter + 1, forKey: lockedFilenameCounterKey)
                return "\(stem).\(fileExtension(isDNG: isDNG, isHEIF: isHEIF))"
            }
            counter += 1
        }
    }
    
    private nonisolated static func nextCounterAfterExistingLockedCaptures(in sessionURL: URL) -> Int {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: sessionURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        
        let highestCounter = urls.compactMap(lockedCounter).max()
        return highestCounter.map { $0 + 1 } ?? 0
    }
    
    private nonisolated static func nextCounterAfterRecentPhotoLibraryAssets() -> Int {
        let status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard status == .authorized || status == .limited else { return 0 }
        
        let options = PHFetchOptions()
        options.fetchLimit = 1_000
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        
        let assets = PHAsset.fetchAssets(with: options)
        var highestCounter: Int?
        assets.enumerateObjects { asset, _, _ in
            for resource in PHAssetResource.assetResources(for: asset) {
                guard let counter = lockedCounter(fromFilename: resource.originalFilename) else { continue }
                highestCounter = max(highestCounter ?? counter, counter)
            }
        }
        
        return highestCounter.map { $0 + 1 } ?? 0
    }
    
    private nonisolated static func lockedCounter(for url: URL) -> Int? {
        guard lockedFilenameExtensions.contains(url.pathExtension.lowercased()) else { return nil }
        return lockedCounter(fromFilename: url.lastPathComponent)
    }
    
    private nonisolated static func lockedCounter(fromFilename filename: String) -> Int? {
        let url = URL(fileURLWithPath: filename)
        guard lockedFilenameExtensions.contains(url.pathExtension.lowercased()) else { return nil }
        
        var stem = url.deletingPathExtension().lastPathComponent
        if stem.hasSuffix("_LC") {
            stem.removeLast(3)
        }
        guard stem.hasPrefix("IMG_") else { return nil }
        
        let suffix = stem.dropFirst(4)
        guard !suffix.isEmpty, suffix.allSatisfy(\.isNumber) else { return nil }
        return Int(suffix)
    }
    
    private nonisolated static func lockedFileStemExists(_ stem: String, in sessionURL: URL) -> Bool {
        lockedFilenameExtensions.contains { fileExtension in
            FileManager.default.fileExists(atPath: sessionURL.appendingPathComponent("\(stem).\(fileExtension)").path)
        }
    }
    
    private nonisolated static func lockedFileStem(for counter: Int) -> String {
        let digits = String(max(0, counter))
        let padding = String(repeating: "0", count: max(0, 4 - digits.count))
        return "IMG_\(padding)\(digits)_LC"
    }
    
    private nonisolated static func fileExtension(isDNG: Bool, isHEIF: Bool) -> String {
        if isDNG {
            return "dng"
        } else if isHEIF {
            return "heic"
        } else {
            return "jpg"
        }
    }
}

// MARK: - Thread-safe dictionary for manifest serial queues
final class ManifestQueueRegistry: @unchecked Sendable {
    private var dict: [String: DispatchQueue] = [:]
    private let lock = NSLock()
    
    func withLock<T>(_ body: (inout [String: DispatchQueue]) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body(&dict)
    }
}
