internal import AVFoundation
internal import CoreLocation
import Foundation

extension CameraModel {
    var showSimpleView: Bool {
        appView == .clean || appView == .settings || isBurstCapturing || (isTimerCountingDown && shouldHideUIWhileCountingDown)
    }
    
    func hideSettings() {
        appView = .standard
    }
    
    func toggleSelfie() {
        guard canToggleSelfie else { return }
        let target: Lens = activeLens.isFront ? .wide : (captureMode == .raw ? .frontUltraWide : .front)
        switchLens(to: target)
    }
    
    func toggleClipping() { showClipping.toggle() }
    
    func toggleZebraStripes() { showZebraStripes.toggle() }
    
    func cycleHistogramMode(mode: inout HistogramMode, size: HistogramSize? = nil) {
        switch mode {
            case .luminance:
                mode = .color
            case .color:
                mode = .waveform
            case .waveform:
                mode = .parade
            case .parade:
                mode = .luminance
            case .none:
                if size == .small {
                    mode = defaultHistogramSmall == .none ? .waveform : defaultHistogramSmall
                } else if size == .large {
                    mode = defaultHistogramLarge == .none ? .luminance : defaultHistogramLarge
                } else {
                    mode = .luminance
                }
        }
    }
    
    func hideHistogram(for mode: HistogramSize) {
        mode == .small ? (histogramModeSmall = .none) : (histogramModeLarge = .none)
    }
    
    func resetControl(for control: ManualControl) {
        switch control {
            case .ev:
                if isAutoExposure {
                    resetEV()
                    applyExposureBias()
                }
            case .iso:
                isAutoExposure = true
                setAutoExposure()
            case .ss:
                isAutoExposure = true
                setAutoExposure()
            case .f:
                isAutoFocus = true
                setAutoFocus()
            case .wb:
                isAutoWhiteBalance = true
        }
    }
    
    func selectResolution(_ opt: ResolutionOption) {
        guard isResolutionEnabled(opt) else { return }
        if isHighResolutionOption(opt), !activeLens.preservesHighResolutionCapture {
            switchLens(to: activeLens.highResolutionFallbackLens)
        }
        
        selectedResolution = opt
    }
    
    func changeCaptureFormat(to mode: CaptureMode) {
        guard isFormatEnabled(mode) else { return }
        if mode == .raw {
            switchToRawCaptureMode()
            return
        }
        
        captureMode = mode
    }
    
    func cycleFlashMode() {
        guard supportsFlash, isAutoExposure else {
            flashMode = .off
            return
        }
        
        let supported = photoOutput.supportedFlashModes
        let order: [AVCaptureDevice.FlashMode] = [.off, .auto, .on]
        let currentIndex = order.firstIndex(of: flashMode) ?? 0
        
        for offset in 1...order.count {
            let candidate = order[(currentIndex + offset) % order.count]
            if supported.contains(candidate) {
                flashMode = candidate
                return
            }
        }
        
        flashMode = .off
    }
    
    func toggleMacroMode() {
        guard supportsMacro, isAutoExposure else { return }
        
        if !isMacroEnabled {
            // Enabling macro: switch to Ultra Wide first
            if activeLens != .ultraWide {
                switchLens(to: .ultraWide)
            }
            isMacroEnabled = true
        } else {
            // Disabling macro
            isMacroEnabled = false
        }
    }
    
    func cycleTimerMode() {
        if isBurstModeEnabled {
            isBurstModeEnabled = false
        }
        
        switch timerMode {
            case .off:
                timerMode = .threeSeconds
            case .threeSeconds:
                timerMode = .fiveSeconds
            case .fiveSeconds:
                timerMode = .tenSeconds
            case .tenSeconds:
                timerMode = .off
        }
    }
    
    func cycleFocusAssistMode() {
        if showFocusPeaking {
            showFocusPeaking = false
            showFocusLoupe = true
        } else if showFocusLoupe {
            showFocusLoupe = false
            showFocusPeaking = false
        } else {
            showFocusPeaking = true
            showFocusLoupe = false
        }
    }
    
    func changePhotoFilter(to filter: PhotoFilter) {
        selectedPhotoFilter = filter
    }
    
    var isLiveFilterPreviewActive: Bool {
        selectedPhotoFilter != .off && captureMode != .raw
    }
    
    var isFilterRestrictingCaptureOptions: Bool {
        selectedPhotoFilter != .off
    }
    
    func enforcePhotoFilterConstraints() {
        guard selectedPhotoFilter != .off else { return }
        
        if !isAutoExposure {
            isAutoExposure = true
            setAutoExposure()
        }
        
        if captureMode == .raw {
            captureMode = preferredFilteredCaptureMode
        }
    }
    
    func updateLiveFilterPreviewReferenceSize() {
        if let selectedResolution {
            liveFilterPreviewReferenceSize = CGSize(
                width: CGFloat(selectedResolution.width),
                height: CGFloat(selectedResolution.height)
            )
            return
        }
        
        let maxPhotoDimensions = photoOutput.maxPhotoDimensions
        liveFilterPreviewReferenceSize = CGSize(
            width: CGFloat(maxPhotoDimensions.width),
            height: CGFloat(maxPhotoDimensions.height)
        )
    }
    
    func syncAutoRulerValues(
        iso liveISO: Float,
        exposureDuration: CMTime,
        whiteBalanceTemperature: Float,
        lensPosition liveLensPosition: Float
    ) {
        if isAutoExposure {
            let nextISO = nearestISOStop(to: liveISO)
            if abs(iso - nextISO) > 0.1 {
                iso = nextISO
            }
            
            if let nextShutterIndex = nearestShutterIndex(to: exposureDuration),
               shutterIndex != nextShutterIndex {
                shutterIndex = nextShutterIndex
            }
        }
        
        if isAutoWhiteBalance {
            let nextWhiteBalance = snappedWhiteBalanceKelvin(whiteBalanceTemperature)
            if abs(whiteBalanceTargetKelvin - nextWhiteBalance) >= 50 {
                whiteBalanceTargetKelvin = nextWhiteBalance
            }
        }
        
        if isAutoFocus {
            let nextLensPosition = snappedFocusPosition(liveLensPosition)
            if abs(lensPosition - nextLensPosition) >= 0.005 {
                lensPosition = nextLensPosition
            }
        }
    }
}
