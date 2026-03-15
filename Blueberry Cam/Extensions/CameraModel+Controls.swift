internal import AVFoundation
import Foundation

extension CameraModel {
    func setupCameraControls() {
        // Surgical removal to prevent duplicates
        if let c = cleanUIControl { session.removeControl(c); cleanUIControl = nil }
        if let l = lensControl { session.removeControl(l); lensControl = nil }
        if let e = evControl { session.removeControl(e); evControl = nil }
        if let i = isoControl { session.removeControl(i); isoControl = nil }
        if let s = ssControl { session.removeControl(s); ssControl = nil }
        if let f = focusControl { session.removeControl(f); focusControl = nil }
        if let wb = wbControl { session.removeControl(wb); wbControl = nil }
        
        // Final wipe of any orphans just in case
        session.controls.forEach { session.removeControl($0) }
        
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
        self.cleanUIControl = picker
        session.addControl(picker)
        
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
            self.lensControl = picker
            session.addControl(picker)
        }
        
        // EV Slider
        let ev = AVCaptureSlider("Exposure", symbolName: "plusminus", in: -4.0...4.0, step: 0.1)
        ev.prominentValues = [-4.0, -3.5, -3.0, -2.5, -2.0, -1.5, -1.0, -0.5, 0.0, 0.5, 1.0, 1.5, 2.0, 2.5, 3.0, 3.5, 4.0]
        ev.localizedValueFormat = "%@ EV"
        // Seed to current EV value
        let clampedEV = max(-4.0, min(4.0, exposureBias))
        ev.value = round(clampedEV * 10) / 10.0
        ev.setActionQueue(.main) { [weak self] value in
            guard let self, !self.isUpdatingHardwareControl else { return }
            if abs(self.exposureBias - value) > 0.01 {
                self.exposureBias = value
                self.applyExposureBias()
            }
        }
        self.evControl = ev
        session.addControl(ev)
        
        // ISO Slider — use step-safe bounds (ceil min to next 50, floor max to prev 50)
        // This ensures min/max are exact multiples of the step so AVCaptureSlider never throws
        let isoSliderMin = ceil(minISO / 50.0) * 50.0
        let isoSliderMax = floor(maxISO / 50.0) * 50.0
        guard isoSliderMin <= isoSliderMax else { return }
        let isoSlider = AVCaptureSlider("ISO", symbolName: "film", in: isoSliderMin...isoSliderMax, step: 50.0)
        isoSlider.prominentValues = [100, 200, 400, 800, 1600, 3200, 6400]
        // Seed the slider to the current iso (clamped & snapped)
        let seedISO = max(isoSliderMin, min(isoSliderMax, round(iso / 50.0) * 50.0))
        isoSlider.value = seedISO
        isoSlider.setActionQueue(.main) { [weak self] value in
            guard let self, !self.isUpdatingHardwareControl else { return }
            if abs(self.iso - value) > 1.0 {
                self.iso = value
                self.applyManualExposure()
            }
        }
        self.isoControl = isoSlider
        session.addControl(isoSlider)
        
        // Shutter Speed Index Picker — index 0 is fastest (left), max index is slowest (right)
        // This solves both the negative sign formatting limitations of AVCaptureSlider
        // and ensures we only select valid stops for the current camera.
        if shutterSpeeds.count > 0 {
            let ssPicker = AVCaptureIndexPicker("Shutter Speed", symbolName: "lightspectrum.horizontal", numberOfIndexes: shutterSpeeds.count) { [weak self] index in
                guard let self else { return "" }
                guard index >= 0 && index < self.shutterSpeeds.count else { return "" }
                return Self.formatShutter(self.shutterSpeeds[index])
            }
            // Seed to current shutterIndex
            let clampedIdx = max(0, min(shutterSpeeds.count - 1, shutterIndex))
            ssPicker.selectedIndex = clampedIdx
            ssPicker.setActionQueue(.main) { [weak self] index in
                guard let self, !self.isUpdatingHardwareControl else { return }
                if self.shutterIndex != index {
                    self.shutterIndex = index
                    self.manualShutterDenominator = 0 // clear manual denominator
                    self.applyManualExposure()
                }
            }
            self.ssControl = ssPicker
            session.addControl(ssPicker)
        }
        
        // Focus Slider
        // Trick: slider runs 0...100 so iOS formats it as whole numbers, and we prefix with "0."
        let focus = AVCaptureSlider("Focus", symbolName: "scope", in: 0...100, step: 1)
        focus.localizedValueFormat = "0.%@"
        focus.value = Float(lensPosition * 100.0)
        focus.setActionQueue(.main) { [weak self] value in
            guard let self, !self.isUpdatingHardwareControl else { return }
            let normalized = value / 100.0
            if abs(self.lensPosition - normalized) > 0.01 {
                self.lensPosition = normalized
                self.applyManualFocus()
            }
        }
        self.focusControl = focus
        session.addControl(focus)
        
        // White Balance Slider
        let wb = AVCaptureSlider("White Balance", symbolName: "thermometer.sun.fill", in: 2000...10000, step: 100)
        wb.localizedValueFormat = "%@K"
        wb.value = max(2000, min(10000, whiteBalanceTargetKelvin))
        wb.setActionQueue(.main) { [weak self] value in
            guard let self, !self.isUpdatingHardwareControl else { return }
            if abs(self.whiteBalanceTargetKelvin - value) > 10 {
                self.whiteBalanceTargetKelvin = value
                // Setting whiteBalanceTargetKelvin triggers applyManualWhiteBalance() via didSet if manual WB
            }
        }
        self.wbControl = wb
        session.addControl(wb)
        
        updateCameraControlsMode()
    }
    
    func updateCameraControlsMode() {
        evControl?.isEnabled = isAutoExposure
        isoControl?.isEnabled = !isAutoExposure
        ssControl?.isEnabled = !isAutoExposure
        focusControl?.isEnabled = !isAutoFocus
        wbControl?.isEnabled = !isAutoWhiteBalance
    }
    
    // MARK: - Bidirectional Sync Helpers
    func syncEVToHardware() {
        guard let ctrl = evControl else { return }
        let clamped = max(-4.0, min(4.0, exposureBias))
        let snapped = round(clamped * 10.0) / 10.0
        if abs(ctrl.value - snapped) > 0.01 {
            isUpdatingHardwareControl = true
            ctrl.value = snapped
            isUpdatingHardwareControl = false
        }
    }
    
    func syncISOToHardware() {
        guard let ctrl = isoControl else { return }
        let raw = max(minISO, min(maxISO, iso))
        let snapped = round(raw / 50.0) * 50.0
        let safeMin = ceil(minISO / 50.0) * 50.0
        let safeMax = floor(maxISO / 50.0) * 50.0
        let final = max(safeMin, min(safeMax, snapped))
        if abs(ctrl.value - final) > 0.1 {
            isUpdatingHardwareControl = true
            ctrl.value = final
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
        let sliderValue = Float(clamped * 100.0)
        if abs(ctrl.value - sliderValue) > 1.0 {
            isUpdatingHardwareControl = true
            ctrl.value = sliderValue
            isUpdatingHardwareControl = false
        }
    }
    
    func syncWBToHardware() {
        guard let ctrl = wbControl else { return }
        let clamped = max(2000, min(10000, whiteBalanceTargetKelvin))
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
