import Foundation
internal import Photos

// Same resolveAlbumID logic as CameraModel — finds or creates "Blueberry Cam" album
nonisolated func resolveAlbumID() -> String? {
    let key = BundleIDs.photoAlbumStorageKey
    let defaults = UserDefaults.standard
    
    // Check for a cached ID first
    if let savedID = defaults.string(forKey: key) {
        let existing = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [savedID], options: nil)
        if existing.firstObject != nil {
            return savedID  // Found it – even if the user moved it to a folder
        }
        // ID is stale (album was deleted), fall through to create a new one
    }
    
    // Try to find an existing album with our name
    let fetch = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: nil)
    var foundID: String?
    fetch.enumerateObjects { col, _, stop in
        if col.localizedTitle == BundleIDs.appName {
            foundID = col.localIdentifier
            stop.pointee = true
        }
    }
    if let foundID {
        defaults.set(foundID, forKey: key)
        return foundID
    }
    
    // Create a brand new album
    var newID: String?
    try? PHPhotoLibrary.shared().performChangesAndWait {
        let createReq = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: BundleIDs.appName)
        newID = createReq.placeholderForCreatedAssetCollection.localIdentifier
    }
    
    // Resolve placeholder → real localIdentifier
    if let placeholder = newID {
        let created = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [placeholder], options: nil)
        let realID = created.firstObject?.localIdentifier ?? placeholder
        defaults.set(realID, forKey: key)
        return realID
    }
    return nil
}
