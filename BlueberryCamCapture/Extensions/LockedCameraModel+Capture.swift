internal import AVFoundation
import Foundation
internal import Photos

extension LockedCameraModel: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput,
                                 didFinishProcessingPhoto photo: AVCapturePhoto,
                                 error: Error?) {
        if let error {
            Task { @MainActor in self.errorMessage = error.localizedDescription; self.showError = true }
            return
        }
        guard let data = photo.fileDataRepresentation() else {
            Task { @MainActor in self.errorMessage = "Failed to get photo data."; self.showError = true }
            return
        }
        let isHeif = !photo.isRawPhoto && _pendingCaptureModeBox.value == .heif
        let url = _sessionContentURLBox.value
        saveToSessionDirectory(data: data, isDNG: photo.isRawPhoto, isHEIF: isHeif, sessionURL: url)
    }
    
    private nonisolated func saveToSessionDirectory(data: Data, isDNG: Bool, isHEIF: Bool, sessionURL: URL?) {
        guard let sessionURL else {
            saveDirectlyToPhotos(data: data, isDNG: isDNG, isHEIF: isHEIF, sessionURL: nil)
            return
        }
        
        let ext = isDNG ? "dng" : (isHEIF ? "heic" : "jpg")
        let filename = "IMG_\(Int(Date().timeIntervalSince1970)).\(ext)"
        let fileURL = sessionURL.appendingPathComponent(filename)
        
        do {
            try data.write(to: fileURL)
        } catch {
            Task { @MainActor in self.errorMessage = error.localizedDescription; self.showError = true }
            // Still attempt to save directly to Photos even if the session file write fails.
        }
        
        // Always save to Photos — the manifest write happens inside the completion handler
        // once we have a confirmed localIdentifier, so the ordering is guaranteed.
        saveDirectlyToPhotos(data: data, isDNG: isDNG, isHEIF: isHEIF, sessionURL: sessionURL)
    }
    
    private nonisolated func saveDirectlyToPhotos(data: Data, isDNG: Bool, isHEIF: Bool, sessionURL: URL?) {
        let currentStatus = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        
        guard currentStatus == .authorized || currentStatus == .limited else {
            Task { @MainActor in
                self.errorMessage = "Photos access denied. Please enable in Settings."
                self.showError = true
            }
            return
        }
        
        performDirectSave(data: data, isDNG: isDNG, isHEIF: isHEIF, sessionURL: sessionURL)
    }

    private nonisolated func performDirectSave(data: Data, isDNG: Bool, isHEIF: Bool, sessionURL: URL?) {
        // Use a local to capture the placeholder ID safely within the performChanges closure.
        // Declared as a class wrapper so it can be mutated inside the closure without a data race.
        final class Box<T>: @unchecked Sendable { var value: T; init(_ v: T) { value = v } }
        let placeholderBox = Box<String?>(nil)
        
        PHPhotoLibrary.shared().performChanges({
            let opts = PHAssetResourceCreationOptions()
            opts.uniformTypeIdentifier = BundleIDs.UTI(isDNG: isDNG, isHEIF: isHEIF)
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
        let manifestURL = sessionURL.appendingPathComponent("manifest.txt")
        
        // Serialize manifest writes for this session URL using a dedicated queue.
        // The label includes the session path so different sessions get different queues.
        let queue = manifestQueue(for: sessionURL)
        queue.sync {
            var existing = (try? String(contentsOf: manifestURL, encoding: .utf8)) ?? ""
            // Guard against duplicate entries (e.g. a retry that already wrote this ID).
            guard !existing.contains(id) else { return }
            existing += id + "\n"
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
