internal import AVFoundation
import SwiftUI

extension CameraModel {
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
    
    // MARK: Flash properties
    fileprivate var flashButtonForeground: Color {
        flashMode == .off || !supportsFlash ? Colors.buttonText : .black
    }
    
    fileprivate var flashButtonBackground: Color {
        flashMode == .off || !supportsFlash ? Colors.buttonBackground : .yellow
    }
    
    fileprivate var flashButtonOpacity: Double {
        (supportsFlash && isAutoExposure && !isBurstModeEnabled) ? 1.0 : 0.3
    }
    
    fileprivate var isFlashButtonDisabled: Bool {
        !(supportsFlash && isAutoExposure && !isBurstModeEnabled)
    }
    
    // MARK: Macro properties
    fileprivate var macroButtonSymbol: String {
        "camera.macro"
    }
    
    fileprivate var macroButtonForeground: Color {
        isMacroEnabled ? .black : Colors.buttonText
    }
    
    fileprivate var macroButtonBackground: Color {
        isMacroEnabled ? .yellow : Colors.buttonBackground
    }
    
    // MARK: Dual Camera properties
    fileprivate var dualcamButtonSymbol: String {
        "inset.filled.rectangle.and.person.filled"
    }
    
    fileprivate var dualcamButtonForeground: Color {
        Colors.buttonText
    }
    
    fileprivate var dualcamButtonBackground: Color {
        Colors.buttonBackground
    }
    
    fileprivate var dualcamButtonOpacity: Double {
        0.3
    }
    
    fileprivate var isDualcamButtonDisabled: Bool {
        true
    }
    
    // MARK: Burst properties
    fileprivate var burstButtonSymbol: String {
        "square.stack.3d.down.right"
    }
    
    fileprivate var burstButtonForeground: Color {
        isBurstModeEnabled ? .black : Colors.buttonText
    }
    
    fileprivate var burstButtonBackground: Color {
        isBurstModeEnabled ? .yellow : Colors.buttonBackground
    }
    
    fileprivate var burstButtonOpacity: Double {
        timerMode == .off && !isTimerCountingDown ? 1.0 : 0.3
    }
    
    fileprivate var isBurstButtonDisabled: Bool {
        timerMode != .off || isTimerCountingDown
    }
    
    // MARK: Timer properties
    fileprivate var timerButtonSymbol: String {
        "timer"
    }
    
    fileprivate var timerButtonForeground: Color {
        timerMode == .off ? Colors.buttonText : .black
    }
    
    fileprivate var timerButtonBackground: Color {
        timerMode == .off ? Colors.buttonBackground : .yellow
    }
    
    fileprivate var timerButtonOpacity: Double {
        isBurstModeEnabled ? 0.3 : 1.0
    }
    
    fileprivate var isTimerButtonDisabled: Bool {
        isBurstModeEnabled
    }
    
    // MARK: Selfie Switch properties
    fileprivate var selfieButtonSymbol: String {
        "arrow.trianglehead.2.clockwise.rotate.90.camera.fill"
    }
    
    fileprivate var selfieButtonForeground: Color {
        Colors.buttonText
    }
    
    fileprivate var selfieButtonBackground: Color {
        Colors.buttonBackground
    }
}

extension TopBarView {
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
            case .ev: "EV \(cameraModel.exposureBias.signedSingleDecimalString)"
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

struct TopBarView: View {
    @Bindable var cameraModel: CameraModel
    @Binding var selectedControl: ManualControl?
    @State private var hapticTrigger = 0
    @State private var hapticTriggerR = 0
    @State private var isShowingBurstIntervalAlert = false
    @State private var isShowingBurstFrameLimitAlert = false
    @State private var burstIntervalInput = ""
    @State private var burstFrameLimitInput = ""
    
    private var parsedBurstInterval: Double? {
        Double(burstIntervalInput)
    }
    
    private var parsedBurstFrameLimit: Int? {
        Int(burstFrameLimitInput)
    }
    
    private var isBurstIntervalInputValid: Bool {
        guard let parsedBurstInterval else { return false }
        return parsedBurstInterval >= 0.2 && parsedBurstInterval <= 5.0
    }
    
    private var isBurstFrameLimitInputValid: Bool {
        guard let parsedBurstFrameLimit else { return false }
        return parsedBurstFrameLimit >= 1 && parsedBurstFrameLimit <= 100
    }
    
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
                        .foregroundStyle(readoutColor(for: control))
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
                if !cameraModel.activeLens.isFront {
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
                    .transition(.opacity.combined(with: .scale(scale: 0.5)))
                }
                
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
                        .frame(height: 18)
                        .foregroundStyle(cameraModel.flashButtonForeground)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(cameraModel.flashButtonBackground)
                        .clipShape(.capsule)
                }
                .opacity(cameraModel.flashButtonOpacity)
                .disabled(cameraModel.isFlashButtonDisabled)
                
                // MARK: - Macro
                if cameraModel.supportsMacro && !cameraModel.activeLens.isFront {
                    Button {
                        hapticTrigger += 1
                        withAnimation(.bouncy) {
                            cameraModel.toggleMacroMode()
                        }
                    } label: {
                        Image(systemName: cameraModel.macroButtonSymbol)
                            .font(.system(size: 12, weight: .bold))
                            .frame(height: 18)
                            .foregroundStyle(cameraModel.macroButtonForeground)
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
                        .frame(height: 18)
                        .foregroundStyle(cameraModel.dualcamButtonForeground)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(cameraModel.dualcamButtonBackground)
                        .clipShape(.capsule)
                }
                .disabled(cameraModel.isDualcamButtonDisabled)
                .opacity(cameraModel.dualcamButtonOpacity)
                
                // MARK: - Burst
                HStack(spacing: 10) {
                    Button {
                        hapticTrigger += 1
                        withAnimation(.bouncy) {
                            cameraModel.toggleBurstMode()
                        }
                    } label: {
                        Image(systemName: cameraModel.burstButtonSymbol)
                    }
                    
                    if cameraModel.isBurstModeEnabled {
                        Button {
                            hapticTrigger += 1
                            burstIntervalInput = cameraModel.burstIntervalSeconds.map {
                                $0.formatted(.number.precision(.fractionLength(1)))
                            } ?? ""
                            isShowingBurstIntervalAlert = true
                        } label: {
                            Text(cameraModel.burstIntervalLabel)
                        }
                        .onTapGesture(count: 2) {
                            hapticTriggerR += 1
                            withAnimation(.bouncy) {
                                cameraModel.setBurstInterval(seconds: nil)
                            }
                        }
                        .transition(.opacity.combined(with: .scale(scale: 0.7)))
                        
                        Button {
                            hapticTrigger += 1
                            burstFrameLimitInput = cameraModel.burstFrameLimit.map(String.init) ?? ""
                            isShowingBurstFrameLimitAlert = true
                        } label: {
                            Text(cameraModel.burstFrameLimitLabel)
                        }
                        .onTapGesture(count: 2) {
                            hapticTriggerR += 1
                            withAnimation(.bouncy) {
                                cameraModel.setBurstFrameLimit(nil)
                            }
                        }
                        .transition(.opacity.combined(with: .scale(scale: 0.7)))
                    }
                }
                .font(.system(size: 12, weight: .bold))
                .frame(height: 18)
                .foregroundStyle(cameraModel.burstButtonForeground)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(cameraModel.burstButtonBackground)
                .clipShape(.capsule)
                .disabled(cameraModel.isBurstButtonDisabled)
                .opacity(cameraModel.burstButtonOpacity)
                
                // MARK: - Timer
                Button {
                    hapticTrigger += 1
                    withAnimation(.bouncy) {
                        cameraModel.cycleTimerMode()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: cameraModel.timerButtonSymbol)
                            .font(.system(size: 12, weight: .bold))
                        
                        if cameraModel.timerMode != .off {
                            Text(cameraModel.timerMode.label)
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                        }
                    }
                    .frame(height: 18)
                    .foregroundStyle(cameraModel.timerButtonForeground)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(cameraModel.timerButtonBackground)
                    .clipShape(.capsule)
                }
                .animation(.bouncy, value: cameraModel.timerMode)
                .disabled(cameraModel.isTimerButtonDisabled)
                .opacity(cameraModel.timerButtonOpacity)
                
                // MARK: - Selfie switch
                Button {
                    hapticTrigger += 1
                    withAnimation(.bouncy) {
                        cameraModel.toggleSelfie()
                    }
                } label: {
                    Image(systemName: cameraModel.selfieButtonSymbol)
                        .font(.system(size: 12, weight: .bold))
                        .frame(height: 18)
                        .foregroundStyle(cameraModel.selfieButtonForeground)
                        .rotation3DEffect(
                            .degrees(cameraModel.activeLens.isFront ? 180 : 0),
                            axis: (x: 0, y: 1, z: 0)
                        )
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(cameraModel.selfieButtonBackground)
                        .clipShape(.capsule)
                }
            }
            .padding(.horizontal, 8)
        }
        .sensoryFeedback(.impact, trigger: hapticTrigger)
        .sensoryFeedback(.impact(flexibility: .soft), trigger: hapticTriggerR)
        .alert("Burst Interval", isPresented: $isShowingBurstIntervalAlert) {
            TextField("Auto", text: $burstIntervalInput)
                .keyboardType(.decimalPad)
            Button("OK") {
                if let parsedBurstInterval {
                    cameraModel.setBurstInterval(seconds: parsedBurstInterval)
                }
            }
            .disabled(!isBurstIntervalInputValid)
            Button("Auto") {
                cameraModel.setBurstInterval(seconds: nil)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Time (seconds) between frames.\nRange: 0.2 to 5.0.\nMay not be guaranteed for smaller intervals. Auto shoots as fast as safely possible.")
        }
        .alert("Burst Frames", isPresented: $isShowingBurstFrameLimitAlert) {
            TextField("Infinity", text: $burstFrameLimitInput)
                .keyboardType(.numberPad)
            Button("OK") {
                if let parsedBurstFrameLimit {
                    cameraModel.setBurstFrameLimit(parsedBurstFrameLimit)
                }
            }
            .disabled(!isBurstFrameLimitInputValid)
            Button("Auto") {
                cameraModel.setBurstFrameLimit(nil)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Number of frames to capture.\nRange: 1 to 100.\nAuto keeps shooting until you tap the shutter button again.")
        }
    }
}
