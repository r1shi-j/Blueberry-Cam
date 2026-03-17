internal import AVFoundation
import SwiftUI

extension LockedCameraModel {
    fileprivate var macroButtonSymbol: String {
        isMacroEnabled ? "camera.macro" : "camera.macro.slash"
    }
    
    fileprivate var macroButtonForeground: Color {
        isMacroEnabled ? .black : Colors.buttonText
    }
    
    fileprivate var macroButtonBackground: Color {
        isMacroEnabled ? .yellow : Colors.buttonBackground
    }
    
    fileprivate var macroButtonOpacity: Double {
        supportsMacro ? 1.0 : 0.45
    }
    
    fileprivate var flashButtonForeground: Color {
        flashMode == .off || !supportsFlash ? Colors.buttonText : .black
    }
    
    fileprivate var flashButtonBackground: Color {
        flashMode == .off || !supportsFlash ? Colors.buttonBackground : .yellow
    }
    
    fileprivate var flashButtonOpacity: Double {
        (supportsFlash && isAutoExposure) ? 1.0 : 0.45
    }
    
    fileprivate var isFlashButtonDisabled: Bool {
        !(supportsFlash && isAutoExposure)
    }
    
    fileprivate func resolutionForeground(for isSelected: Bool) -> Color {
        isSelected ? .black : .white
    }
    
    fileprivate func resolutionBackground(for isSelected: Bool) -> Color {
        isSelected ? .yellow : Colors.buttonBackground
    }
    
    fileprivate func formatForeground(for mode: CaptureMode) -> Color {
        captureMode == mode ? .black : .white
    }
    
    fileprivate func formatBackground(for mode: CaptureMode) -> Color {
        captureMode == mode ? .yellow : Colors.buttonBackground
    }
    
    fileprivate var formatOpacity: Double {
        isAutoExposure ? 1.0 : 0.45
    }
    
    fileprivate var isFormatDisabled: Bool {
        !isAutoExposure
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
        VStack(spacing: 20) {
            HStack(alignment: .center, spacing: 22) {
                // MARK: - Readout values
                ForEach(ManualControl.allCases, id: \.self) { control in
                    Text(readoutTitle(for: control))
                        .padding(4)
                        .font(.system(size: 12, weight: selectedControl == control ? .black : .regular, design: .monospaced))
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
            .padding(.horizontal, 12)
            
            HStack(alignment: .center, spacing: cameraModel.supportsMacro ? 10 : 16) {
                // MARK: - Macro
                if cameraModel.supportsMacro {
                    Button {
                        hapticTrigger += 1
                        withAnimation(.bouncy) {
                            cameraModel.toggleMacroMode()
                        }
                    } label: {
                        Image(systemName: cameraModel.macroButtonSymbol)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(cameraModel.macroButtonForeground)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(cameraModel.macroButtonBackground)
                            .clipShape(.capsule)
                    }
                    .opacity(cameraModel.macroButtonOpacity)
                }

                // MARK: - Flash
                Button {
                    hapticTrigger += 1
                    withAnimation(.bouncy) {
                        cameraModel.cycleFlashMode()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: cameraModel.flashLabel.systemImage)
                            .font(.system(size: 11, weight: .bold))
                        if !cameraModel.flashLabel.label.isEmpty {
                            Text(cameraModel.flashLabel.label)
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                        }
                    }
                    .foregroundColor(cameraModel.flashButtonForeground)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(cameraModel.flashButtonBackground)
                    .clipShape(.capsule)
                }
                .opacity(cameraModel.flashButtonOpacity)
                .disabled(cameraModel.isFlashButtonDisabled)
                
                // MARK: - Resolution picker
                HStack(spacing: 0) {
                    ForEach(cameraModel.availableResolutions) { opt in
                        let isSelected = cameraModel.selectedResolution?.id == opt.id
                        Button {
                            hapticTrigger += 1
                            withAnimation(.bouncy) {
                                cameraModel.selectResolution(opt)
                            }
                        } label: {
                            Text(opt.label)
                                .font(.system(size: 11, weight: .medium))
                                .fontWidth(.expanded)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(cameraModel.resolutionBackground(for: isSelected))
                                .foregroundColor(cameraModel.resolutionForeground(for: isSelected))
                        }
                    }
                }
                .clipShape(.rect(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.white.opacity(0.2), lineWidth: 1))
                
                // MARK: - Format picker
                HStack(spacing: 0) {
                    ForEach(cameraModel.availableFormats) { mode in
                        Button {
                            hapticTrigger += 1
                            withAnimation(.bouncy) {
                                cameraModel.changeCaptureFormat(to: mode)
                            }
                        } label: {
                            Text(mode.rawValue)
                                .font(.system(size: 11, weight: .medium))
                                .fontWidth(.expanded)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(cameraModel.formatBackground(for: mode))
                                .foregroundColor(cameraModel.formatForeground(for: mode))
                        }
                    }
                }
                .opacity(cameraModel.formatOpacity)
                .disabled(cameraModel.isFormatDisabled)
                .clipShape(.rect(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.white.opacity(0.2), lineWidth: 1))
            }
            .padding(.horizontal, 8)
        }
        .sensoryFeedback(.impact, trigger: hapticTrigger)
        .sensoryFeedback(.impact(flexibility: .soft), trigger: hapticTriggerR)
    }
}
