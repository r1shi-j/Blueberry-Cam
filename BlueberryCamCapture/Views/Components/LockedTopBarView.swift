internal import AVFoundation
import SwiftUI

extension LockedCameraModel {
    // MARK: Flash properties
    fileprivate var flashButtonForeground: Color {
        flashMode == .off || !supportsFlash ? Colors.buttonText : .black
    }
    
    fileprivate var flashButtonBackground: Color {
        flashMode == .off || !supportsFlash ? Colors.buttonBackground : .yellow
    }
    
    fileprivate var flashButtonOpacity: Double {
        (supportsFlash && isAutoExposure) ? 1.0 : 0.3
    }
    
    fileprivate var isFlashButtonDisabled: Bool {
        !(supportsFlash && isAutoExposure)
    }
    
    // MARK: Macro properties
    fileprivate var macroButtonSymbol: String {
        isMacroEnabled ? "camera.macro" : "camera.macro.slash"
    }
    
    fileprivate var macroButtonForeground: Color {
        isMacroEnabled ? .black : Colors.buttonText
    }
    
    fileprivate var macroButtonBackground: Color {
        isMacroEnabled ? .yellow : Colors.buttonBackground
    }
    
    // MARK: Dual Camera properties
    fileprivate var dualcamButtonSymbol: String {
        isMacroEnabled ? "camera.macro" : "camera.macro.slash"
        // "inset.filled.rectangle.and.person.filled.slash") // no .slash if enabled
    }
    
    fileprivate var dualcamButtonForeground: Color {
        isMacroEnabled ? .black : Colors.buttonText
    }
    
    fileprivate var dualcamButtonBackground: Color {
        isMacroEnabled ? .yellow : Colors.buttonBackground
    }
    
    fileprivate var dualcamButtonOpacity: Double {
        (supportsMacro && isAutoExposure) ? 1.0 : 0.3
    }
    
    fileprivate var isDualcamButtonDisabled: Bool {
        !(supportsMacro && isAutoExposure)
    }
    
    // MARK: Burst properties
    fileprivate var burstButtonSymbol: String {
        isMacroEnabled ? "camera.macro" : "camera.macro.slash"
        //        "square.stack.3d.down.right") // .fill if enabled
    }
    
    fileprivate var burstButtonForeground: Color {
        isMacroEnabled ? .black : Colors.buttonText
    }
    
    fileprivate var burstButtonBackground: Color {
        isMacroEnabled ? .yellow : Colors.buttonBackground
    }
    
    fileprivate var burstButtonOpacity: Double {
        (supportsMacro && isAutoExposure) ? 1.0 : 0.3
    }
    
    fileprivate var isBurstButtonDisabled: Bool {
        !(supportsMacro && isAutoExposure)
    }
    
    // MARK: Timer properties
    fileprivate var timerButtonSymbol: String {
        isMacroEnabled ? "camera.macro" : "camera.macro.slash"
        // "timer" but would need a string label for 3 or 10 seconds, could create custom one
    }
    
    fileprivate var timerButtonForeground: Color {
        isMacroEnabled ? .black : Colors.buttonText
    }
    
    fileprivate var timerButtonBackground: Color {
        isMacroEnabled ? .yellow : Colors.buttonBackground
    }
    
    fileprivate var timerButtonOpacity: Double {
        (supportsMacro && isAutoExposure) ? 1.0 : 0.3
    }
    
    fileprivate var isTimerButtonDisabled: Bool {
        !(supportsMacro && isAutoExposure)
    }
    
    // MARK: Format/resolution properties
    fileprivate func resolutionForeground(for isSelected: Bool, isEnabled: Bool) -> Color {
        guard isEnabled else { return Colors.buttonText.opacity(0.3) }
        return isSelected ? .black : .white
    }
    
    fileprivate func resolutionBackground(for isSelected: Bool, isEnabled: Bool) -> Color {
        guard isEnabled else { return Colors.buttonBackground.opacity(0.3) }
        return isSelected ? .yellow : Colors.buttonBackground
    }
    
    fileprivate func formatForeground(for mode: CaptureMode, isEnabled: Bool) -> Color {
        guard isEnabled else { return Colors.buttonText.opacity(0.3) }
        return captureMode == mode ? .black : .white
    }
    
    fileprivate func formatBackground(for mode: CaptureMode, isEnabled: Bool) -> Color {
        guard isEnabled else { return Colors.buttonBackground.opacity(0.3) }
        return captureMode == mode ? .yellow : Colors.buttonBackground
    }
}

extension LockedTopBarView {
    private func readoutColor(for control: ManualControl) -> Color {
        switch control {
            case .ev: return .orange
            case .iso: return .yellow
            case .ss: return .white.opacity(0.8)
            case .f: return .green
            case .wb: return .cyan
        }
    }
    
    private func readoutTitle(for control: ManualControl) -> String {
        switch control {
            case .ev: String(format: "EV %+.1f", cameraModel.exposureBias)
            case .iso: "ISO \(Int(cameraModel.liveISO))"
            case .ss: cameraModel.liveShutter
            case .f: cameraModel.liveFocus
            case .wb: cameraModel.liveWB
        }
    }
    
    private func isReadoutUnderlined(for control: ManualControl) -> Bool {
        (control == ManualControl.ev && cameraModel.exposureBias != 0.0) ||
        (control == ManualControl.iso && !cameraModel.isAutoExposure) ||
        (control == ManualControl.ss && !cameraModel.isAutoExposure) ||
        (control == ManualControl.f && !cameraModel.isAutoFocus) ||
        (control == ManualControl.wb && !cameraModel.isAutoWhiteBalance)
    }
    
    private func isReadoutDisabled(for control: ManualControl) -> Bool {
        (control == ManualControl.ev && !cameraModel.isAutoExposure) ||
        (control == ManualControl.iso && cameraModel.isAutoExposure) ||
        (control == ManualControl.ss && cameraModel.isAutoExposure) ||
        (control == ManualControl.f && cameraModel.isAutoFocus) ||
        (control == ManualControl.wb && cameraModel.isAutoWhiteBalance)
    }
}

struct LockedTopBarView: View {
    @Bindable var cameraModel: LockedCameraModel
    @Binding var selectedControl: ManualControl?
    @State private var hapticTrigger = 0
    @State private var hapticTriggerR = 0
    
    var body: some View {
        VStack(spacing: 14) {
            // MARK: Row 1
            HStack(alignment: .center, spacing: 16) {
                // MARK: - Readout values
                ForEach(ManualControl.allCases, id: \.self) { control in
                    Text(readoutTitle(for: control))
                        .padding(.horizontal, 4)
                        .font(.system(size: 14, weight: selectedControl == control ? .black : .regular, design: .monospaced))
                        .underline(isReadoutUnderlined(for: control))
                        .foregroundColor(readoutColor(for: control))
                        .onTapGesture(count: 2) {
                            hapticTriggerR += 1
                            withAnimation(.bouncy) {
                                cameraModel.resetControl(for: control)
                            }
                        }
                        .onLongPressGesture {
                            hapticTriggerR += 1
                            withAnimation(.bouncy) {
                                cameraModel.resetControl(for: control)
                            }
                        }
                        .disabled(isReadoutDisabled(for: control))
                        .onTapGesture {
                            hapticTrigger += 1
                            withAnimation(.bouncy) {
                                selectedControl = selectedControl == control ? nil : control
                            }
                        }
                }
            }
            .padding(.horizontal, 4)
            
            // MARK: Row 2
            HStack(alignment: .center, spacing: 16) {
                // MARK: - Resolution picker
                HStack(spacing: 0) {
                    ForEach(cameraModel.availableResolutions) { opt in
                        let isSelected = cameraModel.selectedResolution?.id == opt.id
                        let isEnabled = cameraModel.isResolutionEnabled(opt)
                        Button {
                            hapticTrigger += 1
                            withAnimation(.bouncy) {
                                cameraModel.selectResolution(opt)
                            }
                        } label: {
                            Text(opt.label)
                                .font(.system(size: 12, weight: .medium))
                                .fontWidth(.expanded)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(cameraModel.resolutionBackground(for: isSelected, isEnabled: isEnabled))
                                .foregroundStyle(cameraModel.resolutionForeground(for: isSelected, isEnabled: isEnabled))
                        }
                        .disabled(!isEnabled)
                    }
                }
                .clipShape(.rect(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.white.opacity(0.2), lineWidth: 1))
                .animation(.bouncy, value: cameraModel.availableResolutions)
                
                // MARK: - Format picker
                HStack(spacing: 0) {
                    ForEach(cameraModel.availableFormats) { mode in
                        let isEnabled = cameraModel.isFormatEnabled(mode)
                        Button {
                            hapticTrigger += 1
                            withAnimation(.bouncy) {
                                cameraModel.changeCaptureFormat(to: mode)
                            }
                        } label: {
                            Text(mode.rawValue)
                                .font(.system(size: 12, weight: .medium))
                                .fontWidth(.expanded)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(cameraModel.formatBackground(for: mode, isEnabled: isEnabled))
                                .foregroundStyle(cameraModel.formatForeground(for: mode, isEnabled: isEnabled))
                        }
                        .disabled(!isEnabled)
                    }
                }
                .clipShape(.rect(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.white.opacity(0.2), lineWidth: 1))
                .animation(.bouncy, value: cameraModel.availableResolutions)
            }
            .padding(.horizontal, 8)
            
            // MARK: Row 3
            HStack(alignment: .center, spacing: 16) {
                // MARK: - Flash
                Button {
                    hapticTrigger += 1
                    withAnimation(.bouncy) {
                        cameraModel.cycleFlashMode()
                    }
                } label: {
                    Image(systemName: cameraModel.flashLabel)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(cameraModel.flashButtonForeground)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(cameraModel.flashButtonBackground)
                        .clipShape(.capsule)
                }
                .opacity(cameraModel.flashButtonOpacity)
                .disabled(cameraModel.isFlashButtonDisabled)
                
                // MARK: - Macro
                if cameraModel.supportsMacro {
                    Button {
                        hapticTrigger += 1
                        withAnimation(.bouncy) {
                            cameraModel.toggleMacroMode()
                        }
                    } label: {
                        Image(systemName: cameraModel.macroButtonSymbol)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(cameraModel.macroButtonForeground)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(cameraModel.macroButtonBackground)
                            .clipShape(.capsule)
                    }
                    .animation(.bouncy, value: cameraModel.activeLens)
                    .transition(.opacity.combined(with: .scale))
                }
                
                // MARK: - Dual Camera
                Button {
                    hapticTrigger += 1
                } label: {
                    Image(systemName: cameraModel.dualcamButtonSymbol)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(cameraModel.dualcamButtonForeground)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(cameraModel.dualcamButtonBackground)
                        .clipShape(.capsule)
                }
                .disabled(cameraModel.isDualcamButtonDisabled)
                .opacity(cameraModel.dualcamButtonOpacity)
                
                // MARK: - Burst
                Button {
                    hapticTrigger += 1
                } label: {
                    Image(systemName: cameraModel.burstButtonSymbol)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(cameraModel.burstButtonForeground)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(cameraModel.burstButtonBackground)
                        .clipShape(.capsule)
                }
                .disabled(cameraModel.isBurstButtonDisabled)
                .opacity(cameraModel.burstButtonOpacity)
                
                // MARK: - Timer
                Button {
                    hapticTrigger += 1
                } label: {
                    Image(systemName: cameraModel.timerButtonSymbol)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(cameraModel.timerButtonForeground)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(cameraModel.timerButtonBackground)
                        .clipShape(.capsule)
                }
                .disabled(cameraModel.isTimerButtonDisabled)
                .opacity(cameraModel.timerButtonOpacity)
            }
            .padding(.horizontal, 8)
        }
        .sensoryFeedback(.impact, trigger: hapticTrigger)
        .sensoryFeedback(.impact(flexibility: .soft), trigger: hapticTriggerR)
    }
}
