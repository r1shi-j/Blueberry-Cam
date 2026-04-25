internal import AVFoundation
import Foundation

extension CameraModel {
    private var tapFocusHideDelay: Duration { .seconds(2) }
    private var tapFocusAdjustmentIgnoreDuration: TimeInterval { 1.0 }
    private var tapFocusLensPositionChangeThreshold: Float { 0.05 }
    
    var canHandleTapPointInteraction: Bool {
        isAutoFocus || isAutoExposure
    }
    
    var canAdjustTapPointExposureBias: Bool {
        isAutoFocus && isAutoExposure
    }
    
    var canLockTapPoint: Bool {
        isAutoFocus
    }
    
    func configureSubjectAreaMonitoring(for device: AVCaptureDevice) {
        try? device.lockForConfiguration()
        device.isSubjectAreaChangeMonitoringEnabled = true
        device.unlockForConfiguration()
        
        if let subjectAreaChangeObserver {
            NotificationCenter.default.removeObserver(subjectAreaChangeObserver)
        }
        subjectAreaChangeObserver = NotificationCenter.default.addObserver(
            forName: AVCaptureDevice.subjectAreaDidChangeNotification,
            object: device,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleSubjectAreaDidChange()
            }
        }
        
        focusAdjustmentObservation?.invalidate()
        focusAdjustmentObservation = device.observe(\.isAdjustingFocus, options: [.old, .new]) { [weak self] _, change in
            let wasAdjusting = change.oldValue ?? false
            let isAdjusting = change.newValue ?? false
            guard !wasAdjusting, isAdjusting else { return }
            Task { @MainActor [weak self] in
                self?.handleAutoFocusRetake()
            }
        }
        
        lensPositionObservation?.invalidate()
        lensPositionObservation = device.observe(\.lensPosition, options: [.new]) { [weak self] _, change in
            guard let lensPosition = change.newValue else { return }
            Task { @MainActor [weak self] in
                self?.handleLensPositionChange(lensPosition)
            }
        }
    }
    
    func handleSubjectAreaDidChange() {
        guard tapFocusIndicatorPoint != nil,
              tapFocusLockLabel == nil,
              isAutoFocus,
              !isTapFocusInteractionActive else { return }
        clearTapPointInteraction(resetDeviceState: false)
        if isAutoExposure {
            applyExposureBias()
        }
    }
    
    func handleAutoFocusRetake() {
        guard isAutoFocus,
              tapFocusIndicatorPoint != nil,
              tapFocusLockLabel == nil,
              !isTapFocusInteractionActive else { return }
        if ignoredTapFocusAdjustmentEvents > 0 {
            if let deadline = ignoredTapFocusAdjustmentDeadline, Date() <= deadline {
                ignoredTapFocusAdjustmentEvents -= 1
                ignoredTapFocusAdjustmentDeadline = nil
                return
            }
            ignoredTapFocusAdjustmentEvents = 0
            ignoredTapFocusAdjustmentDeadline = nil
        }
        clearTapPointInteraction(resetDeviceState: false)
        if isAutoExposure {
            applyExposureBias()
        }
    }
    
    func handleLensPositionChange(_ lensPosition: Float) {
        guard isAutoFocus,
              tapFocusIndicatorPoint != nil,
              tapFocusLockLabel == nil,
              !isTapFocusInteractionActive,
              ignoredTapFocusAdjustmentEvents == 0,
              ignoredTapFocusAdjustmentDeadline == nil,
              let baseline = tapFocusLensPositionBaseline else { return }
        guard abs(lensPosition - baseline) >= tapFocusLensPositionChangeThreshold else { return }
        clearTapPointInteraction(resetDeviceState: false)
        if isAutoExposure {
            applyExposureBias()
        }
    }
    
    func applyManualFocus() {
        guard let d = device else { return }
        clearTapPointInteraction(resetDeviceState: false)
        beginManualFocusAdjustment()
        guard d.isLockingFocusWithCustomLensPositionSupported else {
            try? d.lockForConfiguration()
            d.focusMode = .continuousAutoFocus
            d.unlockForConfiguration()
            isAutoFocus = true
            return
        }
        try? d.lockForConfiguration()
        d.setFocusModeLocked(lensPosition: lensPosition) { _ in }
        d.unlockForConfiguration()
    }
    
    func setAutoFocus() {
        guard let d = device else { return }
        clearTapPointInteraction(resetDeviceState: false)
        endManualFocusAdjustment()
        try? d.lockForConfiguration()
        d.focusMode = .continuousAutoFocus
        d.unlockForConfiguration()
    }
    
    func showTapFocusIndicator(at previewPoint: CGPoint, lockLabel: String? = nil, persist: Bool = false) {
        tapFocusHideTask?.cancel()
        tapFocusIndicatorPoint = previewPoint
        tapFocusLockLabel = lockLabel
        isTapFocusIndicatorDimmed = false
        if canAdjustTapPointExposureBias {
            updateTapFocusIndicatorOffset(forExposureBias: tapExposureBias)
        } else {
            tapFocusIndicatorOffset = 0
        }
        isTapFocusIndicatorVisible = true
        if !persist {
            scheduleTapFocusIndicatorHide()
        }
    }
    
    func scheduleTapFocusIndicatorHide() {
        tapFocusHideTask?.cancel()
        tapFocusHideTask = Task { @MainActor in
            try? await Task.sleep(for: tapFocusHideDelay)
            guard !Task.isCancelled, !self.isTapFocusInteractionActive else { return }
            self.isTapFocusIndicatorDimmed = self.tapFocusLockLabel == nil
        }
    }
    
    func suspendTapFocusIndicatorHide() {
        tapFocusHideTask?.cancel()
        if tapFocusIndicatorPoint != nil {
            isTapFocusIndicatorVisible = true
            isTapFocusIndicatorDimmed = false
        }
    }
    
    func keepTapFocusIndicatorAlive(at previewPoint: CGPoint) {
        if tapFocusIndicatorPoint == nil {
            tapFocusIndicatorPoint = previewPoint
        }
        isTapFocusIndicatorVisible = true
        isTapFocusIndicatorDimmed = false
    }
    
    func updateTapFocusIndicatorOffset(_ offset: CGFloat) {
        tapFocusIndicatorOffset = offset
    }
    
    func clearTapPointInteraction(resetDeviceState: Bool = true) {
        tapFocusHideTask?.cancel()
        tapFocusLockTask?.cancel()
        tapFocusLensPositionMonitorTask?.cancel()
        isTapFocusIndicatorVisible = false
        isTapFocusIndicatorDimmed = false
        isTapFocusInteractionActive = false
        tapFocusIndicatorPoint = nil
        tapFocusLockLabel = nil
        tapFocusIndicatorOffset = 0
        tapExposureBias = 0
        ignoredTapFocusAdjustmentEvents = 0
        ignoredTapFocusAdjustmentDeadline = nil
        tapFocusLensPositionBaseline = nil
        
        guard resetDeviceState, let d = device else { return }
        try? d.lockForConfiguration()
        if isAutoFocus, d.isFocusModeSupported(.continuousAutoFocus) {
            d.focusMode = .continuousAutoFocus
        }
        if isAutoExposure, d.isExposureModeSupported(.continuousAutoExposure) {
            d.exposureMode = .continuousAutoExposure
        }
        d.unlockForConfiguration()
        if isAutoExposure {
            applyExposureBias()
        }
    }
    
    func handleTapPointAction(devicePoint: CGPoint, previewPoint: CGPoint) {
        guard canHandleTapPointInteraction else { return }
        clearTapPointInteraction()
        tapExposureBias = 0
        updateTapFocusIndicatorOffset(forExposureBias: 0)
        ignoredTapFocusAdjustmentEvents = isAutoFocus ? 1 : 0
        ignoredTapFocusAdjustmentDeadline = isAutoFocus ? Date().addingTimeInterval(tapFocusAdjustmentIgnoreDuration) : nil
        switch (isAutoFocus, isAutoExposure) {
            case (true, true):
                applyAutoFocusAndMeter(at: devicePoint)
                showTapFocusIndicator(at: previewPoint)
                scheduleTapFocusLensPositionMonitoring()
            case (true, false):
                applyAutoFocusOnly(at: devicePoint)
                showTapFocusIndicator(at: previewPoint)
                scheduleTapFocusLensPositionMonitoring()
            case (false, true):
                applyAutoExposureMetering(at: devicePoint)
                showTapFocusIndicator(at: previewPoint)
            case (false, false):
                break
        }
    }
    
    func handleTapPointHold(devicePoint: CGPoint, previewPoint: CGPoint) {
        guard canLockTapPoint else { return }
        clearTapPointInteraction()
        tapExposureBias = 0
        updateTapFocusIndicatorOffset(forExposureBias: 0)
        ignoredTapFocusAdjustmentEvents = isAutoFocus ? 1 : 0
        ignoredTapFocusAdjustmentDeadline = isAutoFocus ? Date().addingTimeInterval(tapFocusAdjustmentIgnoreDuration) : nil
        if isAutoExposure {
            applyAutoFocusAndMeter(at: devicePoint)
            scheduleTapPointLock(focus: true, exposure: true)
            showTapFocusIndicator(at: previewPoint, lockLabel: "AE/AF LOCK", persist: true)
        } else {
            applyAutoFocusOnly(at: devicePoint)
            scheduleTapPointLock(focus: true, exposure: false)
            showTapFocusIndicator(at: previewPoint, lockLabel: "AF LOCK", persist: true)
        }
        tap​Focus​Lock​Haptic​Trigger += 1
    }
    
    private func scheduleTapFocusLensPositionMonitoring() {
        tapFocusLensPositionMonitorTask?.cancel()
        tapFocusLensPositionBaseline = nil
        tapFocusLensPositionMonitorTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(tapFocusAdjustmentIgnoreDuration))
            guard !Task.isCancelled,
                  ignoredTapFocusAdjustmentEvents == 0 || ignoredTapFocusAdjustmentDeadline == nil,
                  tapFocusIndicatorPoint != nil,
                  tapFocusLockLabel == nil,
                  !isTapFocusInteractionActive,
                  let d = self.device else { return }
            self.ignoredTapFocusAdjustmentEvents = 0
            self.ignoredTapFocusAdjustmentDeadline = nil
            self.tapFocusLensPositionBaseline = d.lensPosition
        }
    }
    
    private func applyAutoFocusAndMeter(at devicePoint: CGPoint) {
        guard let d = device else { return }
        try? d.lockForConfiguration()
        if d.isFocusPointOfInterestSupported {
            d.focusPointOfInterest = devicePoint
        }
        if d.isFocusModeSupported(.continuousAutoFocus) {
            d.focusMode = .continuousAutoFocus
        } else if d.isFocusModeSupported(.autoFocus) {
            d.focusMode = .autoFocus
        }
        if d.isExposurePointOfInterestSupported {
            d.exposurePointOfInterest = devicePoint
        }
        if d.isExposureModeSupported(.continuousAutoExposure) {
            d.exposureMode = .continuousAutoExposure
        }
        d.unlockForConfiguration()
        applyExposureBias()
    }
    
    private func applyAutoFocusOnly(at devicePoint: CGPoint) {
        guard let d = device else { return }
        try? d.lockForConfiguration()
        if d.isFocusPointOfInterestSupported {
            d.focusPointOfInterest = devicePoint
        }
        if d.isFocusModeSupported(.continuousAutoFocus) {
            d.focusMode = .continuousAutoFocus
        } else if d.isFocusModeSupported(.autoFocus) {
            d.focusMode = .autoFocus
        }
        d.unlockForConfiguration()
    }
    
    private func scheduleTapPointLock(focus: Bool, exposure: Bool) {
        tapFocusLockTask?.cancel()
        tapFocusLockTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled, let d = self.device else { return }
            try? d.lockForConfiguration()
            if focus {
                if d.isLockingFocusWithCustomLensPositionSupported {
                    d.setFocusModeLocked(lensPosition: d.lensPosition) { _ in }
                } else if d.isFocusModeSupported(.locked) {
                    d.focusMode = .locked
                }
            }
            if exposure, d.isExposureModeSupported(.locked) {
                d.exposureMode = .locked
            }
            d.unlockForConfiguration()
        }
    }
    
    func beginManualFocusAdjustment() {
        guard !isAutoFocus else { return }
        focusPeakingHoldTask?.cancel()
        isAdjustingManualFocus = true
    }
    
    func endManualFocusAdjustment() {
        focusPeakingHoldTask?.cancel()
        focusPeakingHoldTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            self.isAdjustingManualFocus = false
        }
    }
}
