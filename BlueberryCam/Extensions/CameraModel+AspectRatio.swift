internal import AVFoundation
import CoreGraphics
import Foundation

extension CameraModel {
    var shouldShowCaptureAspectRatioButton: Bool {
        guard !isDualCameraEnabled,
              !isConfiguringDualCamera,
              !isDetachingPreviewForReconfiguration,
              activeLens.isFront else { return false }
        return isSwitchingLens || availableCaptureAspectRatios.count > 1
    }
    
    var canCycleCaptureAspectRatio: Bool {
        shouldShowCaptureAspectRatioButton &&
        availableCaptureAspectRatios.count > 1 &&
        !isSwitchingLens &&
        !isCaptureAspectRatioTransitioning
    }
    
    func cycleCaptureAspectRatio() {
        guard canCycleCaptureAspectRatio,
              let currentIndex = availableCaptureAspectRatios.firstIndex(of: selectedCaptureAspectRatio) else { return }
        
        let nextIndex = availableCaptureAspectRatios.index(after: currentIndex)
        let nextRatio = nextIndex == availableCaptureAspectRatios.endIndex
        ? availableCaptureAspectRatios[availableCaptureAspectRatios.startIndex]
        : availableCaptureAspectRatios[nextIndex]
        
        selectCaptureAspectRatio(nextRatio)
    }
    
    func refreshCaptureAspectRatioOptions(for camera: AVCaptureDevice) {
        guard !isDualCameraEnabled, activeLens.isFront else {
            if availableCaptureAspectRatios != [.portrait4x3] {
                availableCaptureAspectRatios = [.portrait4x3]
            }
            return
        }
        
        let supportedRatios = camera.activeFormat.supportedDynamicAspectRatios
        let options = CaptureAspectRatioOption.allCases.filter {
            supportedRatios.contains($0.dynamicAspectRatio)
        }
        
        guard !options.isEmpty else {
            setCaptureAspectRatioOptions([.defaultSelection], selectedRatio: .defaultSelection)
            return
        }
        
        let activeRatio = camera.dynamicAspectRatio.flatMap(CaptureAspectRatioOption.init(dynamicAspectRatio:))
        let selectedRatio: CaptureAspectRatioOption
        if options.contains(selectedCaptureAspectRatio) {
            selectedRatio = selectedCaptureAspectRatio
        } else if let activeRatio, options.contains(activeRatio) {
            selectedRatio = activeRatio
        } else if options.contains(.defaultSelection) {
            selectedRatio = .defaultSelection
        } else {
            selectedRatio = options[options.startIndex]
        }
        
        setCaptureAspectRatioOptions(options, selectedRatio: selectedRatio)
        applyCaptureAspectRatio(selectedRatio,
                                toDeviceWithUniqueID: camera.uniqueID,
                                zoomFactor: activeLens.zoomFactor,
                                endsTransition: false)
    }
    
    func selectCaptureAspectRatio(_ ratio: CaptureAspectRatioOption, zoomFactor: CGFloat? = nil) {
        guard availableCaptureAspectRatios.contains(ratio),
              let device else { return }
        
        selectedCaptureAspectRatio = ratio
        isCaptureAspectRatioTransitioning = true
        updateCaptureOrientation()
        applyCaptureAspectRatio(ratio,
                                toDeviceWithUniqueID: device.uniqueID,
                                zoomFactor: zoomFactor ?? activeLens.zoomFactor,
                                endsTransition: true)
    }
    
    private func setCaptureAspectRatioOptions(_ options: [CaptureAspectRatioOption],
                                              selectedRatio: CaptureAspectRatioOption) {
        if availableCaptureAspectRatios != options {
            availableCaptureAspectRatios = options
        }
        
        if selectedCaptureAspectRatio != selectedRatio {
            selectedCaptureAspectRatio = selectedRatio
        }
    }
    
    private func applyCaptureAspectRatio(_ ratio: CaptureAspectRatioOption,
                                         toDeviceWithUniqueID deviceUniqueID: String,
                                         zoomFactor: CGFloat,
                                         endsTransition: Bool) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard let camera = Lens.captureDevice(uniqueID: deviceUniqueID),
                  camera.activeFormat.supportedDynamicAspectRatios.contains(ratio.dynamicAspectRatio) else {
                if endsTransition {
                    self.finishCaptureAspectRatioTransition()
                }
                return
            }
            
            guard camera.dynamicAspectRatio != ratio.dynamicAspectRatio else {
                if endsTransition {
                    self.finishCaptureAspectRatioTransition()
                }
                return
            }
            let zoomRefresh = zoomRefreshValues(for: camera, zoomFactor: zoomFactor)
            
            do {
                try camera.lockForConfiguration()
                if let zoomRefresh {
                    camera.videoZoomFactor = zoomRefresh.reset
                }
                camera.setDynamicAspectRatio(ratio.dynamicAspectRatio) { _, error in
                    Task { @MainActor in
                        guard let error else {
                            self.restoreZoomAfterCaptureAspectRatioChange(deviceUniqueID: deviceUniqueID,
                                                                          targetZoom: zoomRefresh?.target,
                                                                          endsTransition: endsTransition)
                            return
                        }
                        if endsTransition {
                            self.isCaptureAspectRatioTransitioning = false
                        }
                        self.errorMessage = "Could not change camera aspect ratio: \(error.localizedDescription)"
                        self.showError = true
                    }
                }
                camera.unlockForConfiguration()
            } catch {
                Task { @MainActor in
                    if endsTransition {
                        self.isCaptureAspectRatioTransitioning = false
                    }
                    self.errorMessage = "Could not lock the camera to change aspect ratio."
                    self.showError = true
                }
            }
        }
    }
    
    private nonisolated func zoomRefreshValues(for camera: AVCaptureDevice,
                                               zoomFactor: CGFloat) -> (reset: CGFloat, target: CGFloat)? {
        guard zoomFactor > 1 else { return nil }
        
        let minimumZoom = max(camera.minAvailableVideoZoomFactor, 1)
        let targetZoom = min(camera.activeFormat.videoMaxZoomFactor, max(minimumZoom, zoomFactor))
        guard minimumZoom < targetZoom else { return nil }
        
        return (reset: minimumZoom, target: targetZoom)
    }
    
    private nonisolated func restoreZoomAfterCaptureAspectRatioChange(deviceUniqueID: String,
                                                                      targetZoom: CGFloat?,
                                                                      endsTransition: Bool) {
        sessionQueue.async {
            if let targetZoom,
               let camera = Lens.captureDevice(uniqueID: deviceUniqueID),
               (try? camera.lockForConfiguration()) != nil {
                camera.videoZoomFactor = targetZoom
                camera.unlockForConfiguration()
            }
            
            Task { @MainActor in
                self.updateCaptureOrientation()
                if endsTransition {
                    try? await Task.sleep(for: .milliseconds(targetZoom == nil ? 40 : 110))
                    self.isCaptureAspectRatioTransitioning = false
                }
            }
        }
    }
    
    private nonisolated func finishCaptureAspectRatioTransition() {
        Task { @MainActor [weak self] in
            self?.isCaptureAspectRatioTransitioning = false
        }
    }
}
