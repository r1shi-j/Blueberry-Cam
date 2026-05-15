internal import AVFoundation
internal import CoreLocation
import Foundation

extension LockedCameraModel {
    var showSimpleView: Bool {
        isTimerCountingDown && shouldHideUIWhileCountingDown
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
        selectedResolution = opt
    }
    
    func changeCaptureFormat(to mode: CaptureMode) {
        guard isFormatEnabled(mode) else { return }
        if mode.isRawLike {
            switchToRawCaptureMode(mode)
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
