import Foundation

extension CameraModel {
    func ensureDefaultFileSaveLocation() {
        try? FileSaveLocationStore.prepareDefaultLocationIfNeeded()
        refreshFileSaveLocationDisplay()
    }
    
    func resetFileSaveLocationToDefault() {
        FileSaveLocationStore.resetToDefault()
        refreshFileSaveLocationDisplay()
        validateFilesSaveLocation()
    }
    
    func selectFileSaveLocation(_ url: URL) {
        do {
            try FileSaveLocationStore.storeCustomLocation(url)
            refreshFileSaveLocationDisplay()
            validateFilesSaveLocation()
        } catch {
            recoverFromFileSaveLocationFailure(error)
        }
    }
    
    func validateFilesSaveLocation() {
        guard saveLocation == .files else {
            isFileSaveLocationAvailable = true
            fileSaveLocationIssue = nil
            return
        }
        
        do {
            try FileSaveLocationStore.validateCurrentLocation()
            isFileSaveLocationAvailable = true
            fileSaveLocationIssue = nil
        } catch {
            recoverFromFileSaveLocationFailure(error)
        }
        
        refreshFileSaveLocationDisplay()
    }
    
    func refreshFileSaveLocationDisplay() {
        fileSaveLocationName = FileSaveLocationStore.displayName()
    }
    
    func recoverFromFileSaveLocationFailure(_ error: Error) {
        let reason = userFacingFileSaveLocationReason(for: error)
        
        do {
            try FileSaveLocationStore.resetToDefaultAndValidate()
            refreshFileSaveLocationDisplay()
            isFileSaveLocationAvailable = true
            fileSaveLocationIssue = nil
            errorMessage = "\(reason) Reverting to \(BundleIDs.appName) folder."
            showError = true
        } catch {
            saveLocation = .photos
            refreshFileSaveLocationDisplay()
            isFileSaveLocationAvailable = false
            fileSaveLocationIssue = error.localizedDescription
            errorMessage = "\(reason) Blueberry Cam could not restore its Files folder, so Save Location was changed to Photos."
            showError = true
        }
    }
    
    private func userFacingFileSaveLocationReason(for error: Error) -> String {
        let nsError = error as NSError
        if FileSaveLocationStore.currentLocationIsExternal()
            && (nsError.domain == "NSFileProviderErrorDomain" || error.localizedDescription.localizedStandardContains("No valid file provider")) {
            return "The save folder on the external drive has been disconnected."
        }
        
        if error.localizedDescription.localizedStandardContains("com.apple.filesystems.UserFS.FileProvider") {
            return "The save folder on the external drive has been disconnected."
        }
        
        if nsError.domain == "NSFileProviderErrorDomain"
            || error.localizedDescription.localizedStandardContains("No valid file provider") {
            return "The selected save folder is no longer available."
        }
        
        return error.localizedDescription
    }
}
