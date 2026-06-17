import Foundation

struct FileSaveDestination: Sendable {
    let url: URL
    private let accessedURL: URL?
    
    nonisolated init(url: URL, accessedURL: URL?) {
        self.url = url
        self.accessedURL = accessedURL
    }
    
    nonisolated func stopAccessing() {
        accessedURL?.stopAccessingSecurityScopedResource()
    }
}

enum FileSaveLocationStore {
    private nonisolated static let bookmarkKey = "fileSaveLocationBookmark"
    private nonisolated static let folderNameKey = "fileSaveLocationName"
    private nonisolated static let folderIsExternalKey = "fileSaveLocationIsExternal"
    private nonisolated static let filenameLock = NSLock()
    private nonisolated static let knownPhotoExtensions = ["jpg", "jpeg", "heic", "dng"]
    
    nonisolated static var defaultDirectoryURL: URL {
        URL.documentsDirectory
    }
    
    nonisolated static func displayName() -> String {
        UserDefaults.standard.string(forKey: folderNameKey) ?? BundleIDs.appName
    }
    
    nonisolated static func resetToDefault() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: bookmarkKey)
        defaults.removeObject(forKey: folderNameKey)
        defaults.removeObject(forKey: folderIsExternalKey)
        try? ensureDefaultDirectoryExists()
    }
    
    nonisolated static func prepareDefaultLocationIfNeeded() throws {
        guard UserDefaults.standard.data(forKey: bookmarkKey) == nil else { return }
        try ensureDefaultDirectoryExists()
    }
    
    nonisolated static func storeCustomLocation(_ url: URL) throws {
        if isDefaultDirectory(url) {
            resetToDefault()
            return
        }
        
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
        
        try ensureDirectoryIsWritable(at: url)
        let bookmark = try url.bookmarkData(
            options: [],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        
        let defaults = UserDefaults.standard
        defaults.set(bookmark, forKey: bookmarkKey)
        defaults.set(displayName(for: url), forKey: folderNameKey)
        defaults.set(isExternalVolume(url), forKey: folderIsExternalKey)
    }
    
    nonisolated static func validateCurrentLocation() throws {
        let directory = try resolveDirectory()
        defer { directory.stopAccessing() }
        try ensureDirectoryIsWritable(at: directory.url)
    }
    
    nonisolated static func resetToDefaultAndValidate() throws {
        resetToDefault()
        try validateCurrentLocation()
    }
    
    nonisolated static func makeDestinationURL(isDNG: Bool, isHEIF: Bool) throws -> FileSaveDestination {
        let directory = try resolveDirectory()
        
        do {
            try ensureDirectoryIsWritable(at: directory.url)
            let fileURL = try nextAvailableFileURL(
                in: directory.url,
                fileExtension: fileExtension(isDNG: isDNG, isHEIF: isHEIF)
            )
            return FileSaveDestination(url: fileURL, accessedURL: directory.accessedURL)
        } catch {
            directory.stopAccessing()
            throw error
        }
    }
    
    nonisolated static func currentLocationIsExternal() -> Bool {
        UserDefaults.standard.bool(forKey: folderIsExternalKey)
    }
    
    nonisolated static func currentDirectoryURL() -> URL? {
        do {
            let directory = try resolveDirectory()
            defer { directory.stopAccessing() }
            return directory.url
        } catch {
            return nil
        }
    }
    
    private nonisolated static func resolveDirectory() throws -> ResolvedDirectory {
        guard let bookmark = UserDefaults.standard.data(forKey: bookmarkKey) else {
            try ensureDefaultDirectoryExists()
            return ResolvedDirectory(url: defaultDirectoryURL, accessedURL: nil)
        }
        
        var isStale = false
        let url = try URL(
            resolvingBookmarkData: bookmark,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        
        if isStale {
            let refreshedBookmark = try url.bookmarkData(
                options: [],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(refreshedBookmark, forKey: bookmarkKey)
        }
        
        return ResolvedDirectory(url: url, accessedURL: didStartAccessing ? url : nil)
    }
    
    private nonisolated static func ensureDefaultDirectoryExists() throws {
        try FileManager.default.createDirectory(
            at: defaultDirectoryURL,
            withIntermediateDirectories: true
        )
    }
    
    private nonisolated static func ensureDirectoryIsWritable(at url: URL) throws {
        if isInTrash(url) {
            throw FileSaveLocationError.folderInRecentlyDeleted
        }
        
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw FileSaveLocationError.folderUnavailable
        }
        
        let testURL = url.appending(path: ".blueberrycam-\(UUID().uuidString)")
        do {
            try Data().write(to: testURL, options: .atomic)
            try? FileManager.default.removeItem(at: testURL)
        } catch {
            throw FileSaveLocationError.notWritable
        }
    }
    
    private nonisolated static func isDefaultDirectory(_ url: URL) -> Bool {
        comparablePath(for: url) == comparablePath(for: defaultDirectoryURL)
    }
    
    private nonisolated static func comparablePath(for url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }
    
    private nonisolated static func isInTrash(_ url: URL) -> Bool {
        if url.path.localizedStandardContains("Recently Deleted")
            || url.path.localizedStandardContains(".Trash") {
            return true
        }
        
        var relationship: FileManager.URLRelationship = .other
        guard (try? FileManager.default.getRelationship(
            &relationship,
            of: .trashDirectory,
            in: [],
            toItemAt: url
        )) != nil else {
            return false
        }
        
        return relationship == .contains || relationship == .same
    }
    
    private nonisolated static func nextAvailableFileURL(in directoryURL: URL, fileExtension: String) throws -> URL {
        filenameLock.lock()
        defer { filenameLock.unlock() }
        
        var counter = nextCounterAfterExistingFiles(in: directoryURL)
        
        while true {
            let stem = fileStem(for: counter)
            if !fileStemExists(stem, in: directoryURL) {
                return directoryURL.appending(path: "\(stem).\(fileExtension)")
            }
            counter += 1
        }
    }
    
    private nonisolated static func fileStem(for counter: Int) -> String {
        let digits = String(max(0, counter))
        let padding = String(repeating: "0", count: max(0, 4 - digits.count))
        return "IMG_\(padding)\(digits)"
    }
    
    private nonisolated static func nextCounterAfterExistingFiles(in directoryURL: URL) -> Int {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        
        let highestCounter = urls.compactMap(existingCounter).max()
        return highestCounter.map { $0 + 1 } ?? 0
    }
    
    private nonisolated static func existingCounter(for url: URL) -> Int? {
        guard knownPhotoExtensions.contains(url.pathExtension.lowercased()) else { return nil }
        let stem = url.deletingPathExtension().lastPathComponent
        guard stem.hasPrefix("IMG_") else { return nil }
        
        let suffix = stem.dropFirst(4)
        guard !suffix.isEmpty, suffix.allSatisfy(\.isNumber) else { return nil }
        return Int(suffix)
    }
    
    private nonisolated static func fileStemExists(_ stem: String, in directoryURL: URL) -> Bool {
        knownPhotoExtensions.contains { fileExtension in
            let candidate = directoryURL.appending(path: "\(stem).\(fileExtension)")
            return FileManager.default.fileExists(atPath: candidate.path)
        }
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
    
    private nonisolated static func displayName(for url: URL) -> String {
        if isDefaultDirectory(url) {
            return BundleIDs.appName
        }
        
        let volumeName = volumeName(for: url)
        if let localizedName = try? url.resourceValues(forKeys: [.localizedNameKey]).localizedName,
           !localizedName.isEmpty {
            if isExternalVolume(url),
               let volumeName,
               looksLikeSystemVolumeIdentifier(localizedName) {
                return volumeName
            }
            return localizedName
        }
        
        let fileManagerName = FileManager.default.displayName(atPath: url.path)
        if !fileManagerName.isEmpty {
            if isExternalVolume(url),
               let volumeName,
               looksLikeSystemVolumeIdentifier(fileManagerName) {
                return volumeName
            }
            return fileManagerName
        }
        
        if let volumeName, isExternalVolume(url) {
            return volumeName
        }
        
        return url.lastPathComponent
    }
    
    private nonisolated static func isExternalVolume(_ url: URL) -> Bool {
        let keys: Set<URLResourceKey> = [.volumeIsRemovableKey, .volumeIsEjectableKey]
        guard let values = try? url.resourceValues(forKeys: keys) else { return false }
        return values.volumeIsRemovable == true || values.volumeIsEjectable == true
    }
    
    private nonisolated static func volumeName(for url: URL) -> String? {
        guard let name = try? url.resourceValues(forKeys: [.volumeLocalizedNameKey]).volumeLocalizedName,
              !name.isEmpty else { return nil }
        return name
    }
    
    private nonisolated static func looksLikeSystemVolumeIdentifier(_ name: String) -> Bool {
        if UUID(uuidString: name) != nil { return true }
        let compact = name.replacing("-", with: "")
        guard compact.count >= 8 else { return false }
        return compact.allSatisfy(\.isHexDigit)
    }
}

private struct ResolvedDirectory: Sendable {
    let url: URL
    let accessedURL: URL?
    
    nonisolated func stopAccessing() {
        accessedURL?.stopAccessingSecurityScopedResource()
    }
}

private enum FileSaveLocationError: LocalizedError {
    case folderUnavailable
    case folderInRecentlyDeleted
    case notWritable
    
    var errorDescription: String? {
        switch self {
            case .folderUnavailable:
                "The selected save folder is no longer available."
            case .folderInRecentlyDeleted:
                "The selected save folder is in Recently Deleted."
            case .notWritable:
                "Blueberry Cam cannot write to the selected save folder."
        }
    }
}
