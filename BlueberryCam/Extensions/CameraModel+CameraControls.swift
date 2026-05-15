internal import AVFoundation
import Foundation
import UIKit

extension CameraModel {
    func setupCameraControls() {
        // Surgical removal to prevent duplicates
        removeCameraControls()
        
        guard supportsHardwareCameraControls else {
            return
        }
        activeCaptureSession.setControlsDelegate(self, queue: DispatchQueue.main)
        
        // Early Exit: If settings sheet is active, we don't want any camera controls visible
        if self.appView == .settings {
            return
        }
        
        // App View Picker
        let titles = AppView.allCases.map(\.rawValue) // ["Standard", "Clean", "Settings"]
        let picker = AVCaptureIndexPicker("View", symbolName: "square.arrowtriangle.4.outward", localizedIndexTitles: titles)
        picker.setActionQueue(.main) { [weak self] index in
            guard let self else { return }
            self.appView = AppView.fromIndex(index)
        }
        picker.selectedIndex = self.appView.index
        if addCameraControl(picker) {
            self.cleanUIControl = picker
        }
        
        // Lens Picker
        let availableLenses = Lens.allCases.filter { len in
            AVCaptureDevice.default(len.deviceType, for: .video, position: len.position) != nil
        }
        if !availableLenses.isEmpty {
            let titles = availableLenses.map { "\($0.label)x" }
            let picker = AVCaptureIndexPicker("Cameras", symbolName: "camera.aperture", localizedIndexTitles: titles)
            picker.setActionQueue(.main) { [weak self] index in
                guard let self else { return }
                guard index >= 0 && index < availableLenses.count else { return }
                self.switchLens(to: availableLenses[index])
            }
            if let activeIndex = availableLenses.firstIndex(of: activeLens) {
                picker.selectedIndex = activeIndex
            }
            if addCameraControl(picker) {
                self.lensControl = picker
            }
        }
        
        guard !isDualCameraEnabled else {
            updateCameraControlsMode()
            return
        }
        
        if !isDualCameraEnabled {
            // Filter Picker
            let availableFilters = PhotoFilter.allCases
            let filterTitles = availableFilters.map(\.rawValue)
            let filterPicker = AVCaptureIndexPicker("Filters", symbolName: "camera.filters", localizedIndexTitles: filterTitles)
            filterPicker.setActionQueue(.main) { [weak self] index in
                guard let self else { return }
                guard index >= 0 && index < availableFilters.count else { return }
                self.changePhotoFilter(to: availableFilters[index])
            }
            if let selectedIndex = availableFilters.firstIndex(of: selectedPhotoFilter) {
                filterPicker.selectedIndex = selectedIndex
            }
            if addCameraControl(filterPicker) {
                self.filterControl = filterPicker
            }
            
            // EV Slider (created but not added yet — updateCameraControlsMode will add if needed)
            let ev = AVCaptureSlider("Exposure", symbolName: "plusminus", in: CameraModel.minEV...CameraModel.maxEV, step: 0.1)
            ev.prominentValues = [-4.0, -3.5, -3.0, -2.5, -2.0, -1.5, -1.0, -0.5, 0.0, 0.5, 1.0, 1.5, 2.0, 2.5, 3.0, 3.5, 4.0]
            ev.localizedValueFormat = "%@ EV"
            let clampedEV = max(CameraModel.minEV, min(CameraModel.maxEV, exposureBias))
            ev.value = round(clampedEV * 10) / 10.0
            ev.setActionQueue(.main) { [weak self] value in
                guard let self, !self.isUpdatingHardwareControl else { return }
                self.setExposureBias(value)
            }
            self.evControl = ev
            
            // ISO Index Picker - mirrors the app ruler stops instead of exposing a long raw hardware range.
            let isoPickerStops = isoStops.isEmpty ? availableISOStops : isoStops
            if !isoPickerStops.isEmpty {
                let isoPicker = AVCaptureIndexPicker("ISO", symbolName: "film", numberOfIndexes: isoPickerStops.count) { index in
                    guard isoPickerStops.indices.contains(index) else { return "" }
                    return Self.formatISO(isoPickerStops[index])
                }
                isoPicker.selectedIndex = nearestISOStopIndex(in: isoPickerStops, to: iso) ?? 0
                isoPicker.setActionQueue(.main) { [weak self] index in
                    guard let self, !self.isUpdatingHardwareControl else { return }
                    let stops = self.isoStops.isEmpty ? self.availableISOStops : self.isoStops
                    guard stops.indices.contains(index) else { return }
                    
                    let nextISO = stops[index]
                    if abs(self.iso - nextISO) > 0.1 {
                        self.iso = nextISO
                        self.applyManualExposure()
                    }
                }
                self.isoControl = isoPicker
            }
            
            // Shutter Speed Index Picker - index 0 is slowest, max index is fastest.
            // This solves both the negative sign formatting limitations of AVCaptureSlider
            // and ensures we only select valid stops for the current camera.
            if shutterSpeeds.count > 0 {
                let ssPicker = AVCaptureIndexPicker("Shutter Speed", symbolName: "lightspectrum.horizontal", numberOfIndexes: shutterSpeeds.count) { [weak self] index in
                    guard let self else { return "" }
                    guard index >= 0 && index < self.shutterSpeeds.count else { return "" }
                    return Self.formatCameraControlShutter(self.shutterSpeeds[index])
                }
                // Seed to current shutterIndex
                let clampedIdx = max(0, min(shutterSpeeds.count - 1, shutterIndex))
                ssPicker.selectedIndex = clampedIdx
                ssPicker.setActionQueue(.main) { [weak self] index in
                    guard let self, !self.isUpdatingHardwareControl else { return }
                    if self.shutterIndex != index {
                        self.shutterIndex = index
                        self.applyManualExposure()
                    }
                }
                self.ssControl = ssPicker
            }
            
            // Focus slider (created but not added yet — updateCameraControlsMode will add if needed)
            let focus = AVCaptureSlider("Focus", symbolName: "scope", in: 0...1, step: 0.01)
            focus.value = lensPosition
            focus.setActionQueue(.main) { [weak self] value in
                guard let self, !self.isUpdatingHardwareControl, !self.isAutoFocus else { return }
                let normalized = max(0.0, min(1.0, value))
                if abs(self.lensPosition - normalized) >= 0.005 {
                    self.lensPosition = normalized
                    self.applyManualFocus()
                }
            }
            self.focusControl = focus
            
            // White Balance Slider (created but not added yet — updateCameraControlsMode will add if needed)
            let wb = AVCaptureSlider("White Balance", symbolName: "thermometer.sun.fill", in: CameraModel.minWhiteBalance...CameraModel.maxWhiteBalance, step: 100)
            wb.localizedValueFormat = "%@K"
            wb.value = max(CameraModel.minWhiteBalance, min(CameraModel.maxWhiteBalance, whiteBalanceTargetKelvin))
            wb.setActionQueue(.main) { [weak self] value in
                guard let self, !self.isUpdatingHardwareControl else { return }
                if abs(self.whiteBalanceTargetKelvin - value) > 10 {
                    self.whiteBalanceTargetKelvin = value
                    // Setting whiteBalanceTargetKelvin triggers applyManualWhiteBalance() via didSet if manual WB
                }
            }
            self.wbControl = wb
        }
        
        updateCameraControlsMode()
    }
    
    private var supportsHardwareCameraControls: Bool {
        UIDevice.current.userInterfaceIdiom == .phone && activeCaptureSession.supportsControls
    }
    
    @discardableResult
    private func addCameraControl(_ control: AVCaptureControl) -> Bool {
        let captureSession = activeCaptureSession
        guard supportsHardwareCameraControls, captureSession.canAddControl(control) else {
            return false
        }
        
        captureSession.addControl(control)
        return true
    }
    
    private func removeCameraControls() {
        let controls = [
            cleanUIControl,
            lensControl,
            filterControl,
            evControl,
            isoControl,
            ssControl,
            focusControl,
            wbControl
        ].compactMap { $0 }
        
        for control in controls {
            if session.controls.contains(control) {
                session.removeControl(control)
            }
            if let dualSession, dualSession.controls.contains(control) {
                dualSession.removeControl(control)
            }
        }
        
        // Final wipe of any orphans just in case.
        session.controls.forEach { session.removeControl($0) }
        dualSession?.controls.forEach { dualSession?.removeControl($0) }
        
        cleanUIControl = nil
        lensControl = nil
        filterControl = nil
        evControl = nil
        isoControl = nil
        ssControl = nil
        focusControl = nil
        wbControl = nil
    }
    
    /// Adds or removes a single control from the active capture session based on a condition.
    private func setControlPresence(_ control: AVCaptureControl?, shouldBePresent: Bool) {
        guard let control else { return }
        let captureSession = activeCaptureSession
        let isPresent = captureSession.controls.contains(control)
        
        if shouldBePresent && !isPresent {
            if captureSession.canAddControl(control) {
                captureSession.addControl(control)
            }
        } else if !shouldBePresent && isPresent {
            captureSession.removeControl(control)
        }
    }
    
    func updateCameraControlsMode() {
        let notDual = !isDualCameraEnabled
        
        // Always-on controls
        cleanUIControl?.isEnabled = true
        lensControl?.isEnabled = true
        
        // Filter: present when not dual, enabled when not RAW-like
        setControlPresence(filterControl, shouldBePresent: notDual)
        filterControl?.isEnabled = notDual && !captureMode.isRawLike
        
        // EV: only shown in auto exposure mode
        let showEV = notDual && isAutoExposure
        setControlPresence(evControl, shouldBePresent: showEV)
        
        // ISO & Shutter Speed: only shown in manual exposure mode
        let showManualExposure = notDual && !isAutoExposure && !isFilterRestrictingCaptureOptions
        setControlPresence(isoControl, shouldBePresent: showManualExposure)
        setControlPresence(ssControl, shouldBePresent: showManualExposure)
        
        // Focus: only shown in manual focus mode
        let showFocus = notDual && !isAutoFocus
        setControlPresence(focusControl, shouldBePresent: showFocus)
        
        // White Balance: only shown in manual WB mode
        let showWB = notDual && !isAutoWhiteBalance
        setControlPresence(wbControl, shouldBePresent: showWB)
    }
    
    // MARK: - Bidirectional Sync Helpers
    func syncPhotoFilterToHardware() {
        guard let ctrl = filterControl,
              let selectedIndex = PhotoFilter.allCases.firstIndex(of: selectedPhotoFilter) else { return }
        if ctrl.selectedIndex != selectedIndex {
            isUpdatingHardwareControl = true
            ctrl.selectedIndex = selectedIndex
            isUpdatingHardwareControl = false
        }
    }
    
    func syncEVToHardware() {
        guard let ctrl = evControl else { return }
        let clamped = max(CameraModel.minEV, min(CameraModel.maxEV, exposureBias))
        let snapped = round(clamped * 10.0) / 10.0
        if abs(ctrl.value - snapped) > 0.01 {
            isUpdatingHardwareControl = true
            ctrl.value = snapped
            isUpdatingHardwareControl = false
        }
    }
    
    func syncISOToHardware() {
        guard let ctrl = isoControl else { return }
        let stops = isoStops.isEmpty ? availableISOStops : isoStops
        guard let selectedIndex = nearestISOStopIndex(in: stops, to: iso) else { return }
        
        if ctrl.selectedIndex != selectedIndex {
            isUpdatingHardwareControl = true
            ctrl.selectedIndex = selectedIndex
            isUpdatingHardwareControl = false
        }
    }
    
    func syncShutterToHardware() {
        guard let ctrl = ssControl, shutterSpeeds.indices.contains(shutterIndex) else { return }
        if ctrl.selectedIndex != shutterIndex {
            isUpdatingHardwareControl = true
            ctrl.selectedIndex = shutterIndex
            isUpdatingHardwareControl = false
        }
    }
    
    func syncFocusToHardware() {
        guard let ctrl = focusControl else { return }
        let clamped = max(0.0, min(1.0, lensPosition))
        if abs(ctrl.value - clamped) >= 0.005 {
            isUpdatingHardwareControl = true
            ctrl.value = clamped
            isUpdatingHardwareControl = false
        }
    }
    
    func syncWBToHardware() {
        guard let ctrl = wbControl else { return }
        let clamped = max(CameraModel.minWhiteBalance, min(CameraModel.maxWhiteBalance, whiteBalanceTargetKelvin))
        if abs(ctrl.value - clamped) > 1.0 {
            isUpdatingHardwareControl = true
            ctrl.value = clamped
            isUpdatingHardwareControl = false
        }
    }
}

// MARK: - Camera Control Delegate
extension CameraModel {
    func sessionControlsDidBecomeActive(_ session: AVCaptureSession) {
        // Called when the controls of an AVCaptureSession instance become active and are available for interaction.
    }
    
    func sessionControlsWillEnterFullscreenAppearance(_ session: AVCaptureSession) {
        // Called when the controls will enter a fullscreen appearance.
    }
    
    func sessionControlsWillExitFullscreenAppearance(_ session: AVCaptureSession) {
        // Called when the controls will exit a fullscreen appearance.
    }
    
    func sessionControlsDidBecomeInactive(_ session: AVCaptureSession) {
        // Called when the controls become inactive.
    }
}
