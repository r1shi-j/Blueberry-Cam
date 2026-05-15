internal import AVFoundation
import SwiftUI

extension LockedTopBarView {
    // MARK: - Constants
    private enum Style {
        static let disabledOpacity = 0.3
        static let selectedForeground: Color = .black
        static let buttonHeight: CGFloat = 18
        static let horizontalButtonPadding: CGFloat = 8
        static let verticalButtonPadding: CGFloat = 5
        static let horizontalPickerPadding: CGFloat = 8
        static let pickerCornerRadius: CGFloat = 6
        static let rowSpacing: CGFloat = 14
        static let row1Spacing: CGFloat = 12
        static let row2Spacing: CGFloat = 16
        static let row3Spacing: CGFloat = 16
        static let row1HPadding: CGFloat = 4
        static let row2HPadding: CGFloat = 8
        static let row3HPadding: CGFloat = 8
    }
    
    private enum Fonts {
        static let picker: Font = .system(size: 12, weight: .medium)
        static let readoutSize: CGFloat = 14
        static let button: Font = .system(size: 12, weight: .bold)
        static let buttonInfo: Font = .system(size: 12, weight: .medium, design: .monospaced)
    }
    
    // MARK: Properties
    // MARK: - Format/resolution properties
    private func resolutionForeground(for isSelected: Bool, isEnabled: Bool) -> Color {
        guard isEnabled else { return Colors.buttonText.opacity(Style.disabledOpacity) }
        return isSelected ? Style.selectedForeground : .white
    }
    
    private func resolutionBackground(for isSelected: Bool, isEnabled: Bool) -> Color {
        guard isEnabled else { return Colors.buttonBackground.opacity(Style.disabledOpacity) }
        return isSelected ? theme.accent : Colors.buttonBackground
    }
    
    private func formatForeground(for mode: CaptureMode, isEnabled: Bool) -> Color {
        guard isEnabled else { return Colors.buttonText.opacity(Style.disabledOpacity) }
        return cameraModel.captureMode == mode ? Style.selectedForeground : .white
    }
    
    private func formatBackground(for mode: CaptureMode, isEnabled: Bool) -> Color {
        guard isEnabled else { return Colors.buttonBackground.opacity(Style.disabledOpacity) }
        return cameraModel.captureMode == mode ? theme.accent : Colors.buttonBackground
    }
    
    // MARK: - Flash properties
    private var flashButtonSymbol: String {
        switch cameraModel.flashMode {
            case .off, .on: "bolt.fill"
            case .auto: "bolt.badge.automatic.fill"
            @unknown default: "bolt.badge.xmark.fill"
        }
    }
    
    private var flashButtonForeground: Color {
        cameraModel.flashMode == .off || !cameraModel.supportsFlash ? Colors.buttonText : Style.selectedForeground
    }
    
    private var flashButtonBackground: Color {
        cameraModel.flashMode == .off || !cameraModel.supportsFlash ? Colors.buttonBackground : theme.accent
    }
    
    private var flashButtonOpacity: Double {
        (cameraModel.supportsFlash && cameraModel.isAutoExposure) ? 1.0 : Style.disabledOpacity
    }
    
    private var isFlashButtonDisabled: Bool {
        !(cameraModel.supportsFlash && cameraModel.isAutoExposure)
    }
    
    // MARK: - Macro properties
    private var macroButtonSymbol: String {
        "camera.macro"
    }
    
    private var macroButtonForeground: Color {
        cameraModel.isMacroEnabled ? Style.selectedForeground : Colors.buttonText
    }
    
    private var macroButtonBackground: Color {
        cameraModel.isMacroEnabled ? theme.accent : Colors.buttonBackground
    }
    
    // MARK: - Timer properties
    private var timerButtonSymbol: String {
        "timer"
    }
    
    private var timerButtonForeground: Color {
        cameraModel.timerMode == .off ? Colors.buttonText : Style.selectedForeground
    }
    
    private var timerButtonBackground: Color {
        cameraModel.timerMode == .off ? Colors.buttonBackground : theme.accent
    }
    
    // MARK: - General Readout properties
    private func readoutColor(for control: ManualControl) -> Color {
        guard !isReadoutDisabled(for: control) else {
            return Colors.buttonText.opacity(Style.disabledOpacity)
        }
        
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
            case .iso: "ISO \(cameraModel.isAutoExposure && cameraModel.liveISO > 0 ? LockedCameraModel.formatISO(cameraModel.liveISO) : cameraModel.formattedISO)"
            case .ss: cameraModel.isAutoExposure && !cameraModel.liveShutter.isEmpty ? cameraModel.liveShutter : cameraModel.formattedShutterSpeed
            case .f: cameraModel.isAutoFocus && !cameraModel.liveFocus.isEmpty ? cameraModel.liveFocus : cameraModel.formattedFocus
            case .wb: cameraModel.isAutoWhiteBalance && !cameraModel.liveWB.isEmpty ? cameraModel.liveWB : cameraModel.formattedWhiteBalance
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
        (control == ManualControl.f && !cameraModel.supportsManualFocus)
    }
    
    private func isExposurePairControl(_ control: ManualControl?) -> Bool {
        control == .iso || control == .ss
    }
    
    private func isReadoutSelected(_ control: ManualControl) -> Bool {
        if isExposurePairControl(control), isExposurePairControl(selectedControl) {
            return true
        }
        
        return selectedControl == control
    }
    
    private func resetReadout(_ control: ManualControl) {
        guard !isReadoutDisabled(for: control) else { return }
        
        hapticTriggerR += 1
        withAnimation(Animations.readoutShown) {
            cameraModel.resetControl(for: control)
            selectedControl = nil
        }
    }
    
    private func toggleReadout(_ control: ManualControl) {
        guard !isReadoutDisabled(for: control) else { return }
        
        hapticTrigger += 1
        withAnimation(Animations.readoutShown) {
            if isExposurePairControl(control), isExposurePairControl(selectedControl) {
                selectedControl = nil
            } else {
                selectedControl = selectedControl == control ? nil : control
            }
        }
    }
    
    // MARK: - Subviews
    // MARK: - Readouts
    private func readouts() -> some View {
        ForEach(ManualControl.allCases, id: \.self) { control in
            Text(readoutTitle(for: control))
                .padding(.horizontal, 4)
                .font(.system(size: Fonts.readoutSize, weight: isReadoutSelected(control) && !isReadoutDisabled(for: control) ? .black : .regular, design: .monospaced))
                .underline(isReadoutUnderlined(for: control))
                .foregroundStyle(readoutColor(for: control))
                .animation(Animations.readoutShown, value: isReadoutDisabled(for: control))
                .onTapGesture {
                    toggleReadout(control)
                }
                .onTapGesture(count: 2) {
                    resetReadout(control)
                }
                .onLongPressGesture {
                    resetReadout(control)
                }
                .disabled(isReadoutDisabled(for: control))
        }
    }
    
    // MARK: - Resolution picker
    @ViewBuilder
    private func resolutionPicker() -> some View {
        if !cameraModel.activeLens.isFront {
            HStack(spacing: 0) {
                ForEach(cameraModel.availableResolutions) { opt in
                    let isSelected = cameraModel.selectedResolution?.id == opt.id
                    let isEnabled = cameraModel.isResolutionEnabled(opt)
                    Button {
                        hapticTrigger += 1
                        withAnimation(Animations.bouncy) {
                            cameraModel.selectResolution(opt)
                        }
                    } label: {
                        Text(opt.label)
                            .font(Fonts.picker)
                            .fontWidth(.expanded)
                            .padding(.horizontal, Style.horizontalPickerPadding)
                            .padding(.vertical, Style.verticalButtonPadding)
                            .background(resolutionBackground(for: isSelected, isEnabled: isEnabled))
                            .foregroundStyle(resolutionForeground(for: isSelected, isEnabled: isEnabled))
                    }
                    .disabled(!isEnabled)
                }
            }
            .clipShape(.rect(cornerRadius: Style.pickerCornerRadius))
            .overlay(RoundedRectangle(cornerRadius: Style.pickerCornerRadius).stroke(.white.opacity(0.2), lineWidth: 1))
            .animation(Animations.bouncy, value: cameraModel.availableResolutions)
            .transition(.opacity.combined(with: .scale(scale: 0.5)))
        }
    }
    
    // MARK: - Format picker
    private func formatPicker() -> some View {
        HStack(spacing: 0) {
            ForEach(cameraModel.availableFormats) { mode in
                let isEnabled = cameraModel.isFormatEnabled(mode)
                Button {
                    hapticTrigger += 1
                    withAnimation(Animations.bouncy) {
                        cameraModel.changeCaptureFormat(to: mode)
                    }
                } label: {
                    Text(mode.rawValue)
                        .font(Fonts.picker)
                        .fontWidth(.expanded)
                        .padding(.horizontal, Style.horizontalPickerPadding)
                        .padding(.vertical, Style.verticalButtonPadding)
                        .background(formatBackground(for: mode, isEnabled: isEnabled))
                        .foregroundStyle(formatForeground(for: mode, isEnabled: isEnabled))
                }
                .disabled(!isEnabled)
            }
        }
        .clipShape(.rect(cornerRadius: Style.pickerCornerRadius))
        .overlay(RoundedRectangle(cornerRadius: Style.pickerCornerRadius).stroke(.white.opacity(0.2), lineWidth: 1))
        .animation(Animations.bouncy, value: cameraModel.enabledFormats)
        .animation(Animations.bouncy, value: cameraModel.captureMode)
        
    }
    
    // MARK: - Flash
    private func flashButton() -> some View {
        Button {
            hapticTrigger += 1
            withAnimation(Animations.bouncy) {
                cameraModel.cycleFlashMode()
            }
        } label: {
            imageIcon(systemName: flashButtonSymbol, foregroundStyle: flashButtonForeground, background: flashButtonBackground)
        }
        .opacity(flashButtonOpacity)
        .disabled(isFlashButtonDisabled)
    }
    
    // MARK: - Macro
    @ViewBuilder
    private func macroButton() -> some View {
        if cameraModel.supportsMacro && !cameraModel.activeLens.isFront {
            Button {
                hapticTrigger += 1
                withAnimation(Animations.bouncy) {
                    cameraModel.toggleMacroMode()
                }
            } label: {
                imageIcon(systemName: macroButtonSymbol, foregroundStyle: macroButtonForeground, background: macroButtonBackground)
            }
            .animation(Animations.bouncy, value: cameraModel.activeLens)
            .transition(.opacity.combined(with: .scale))
        }
    }
    
    // MARK: - Timer
    private func timerButton() -> some View {
        Button {
            hapticTrigger += 1
            withAnimation(Animations.bouncy) {
                cameraModel.cycleTimerMode()
            }
        } label: {
            imageIcon(foregroundStyle: timerButtonForeground, background: timerButtonBackground) {
                HStack(spacing: 4) {
                    Image(systemName: timerButtonSymbol)
                        .font(Fonts.button)
                    
                    if cameraModel.timerMode != .off {
                        Text(cameraModel.timerMode.label)
                            .font(Fonts.buttonInfo)
                    }
                }
            }
        }
        .animation(Animations.bouncy, value: cameraModel.timerMode)
    }
    
    private func imageIcon(systemName: String, foregroundStyle: Color, background: Color) -> some View {
        Image(systemName: systemName)
            .font(Fonts.button)
            .frame(height: Style.buttonHeight)
            .foregroundStyle(foregroundStyle)
            .padding(.horizontal, Style.horizontalButtonPadding)
            .padding(.vertical, Style.verticalButtonPadding)
            .background(background)
            .clipShape(.capsule)
    }
    
    private func imageIcon<Content: View>(foregroundStyle: Color, background: Color, @ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(height: Style.buttonHeight)
            .foregroundStyle(foregroundStyle)
            .padding(.horizontal, Style.horizontalButtonPadding)
            .padding(.vertical, Style.verticalButtonPadding)
            .background(background)
            .clipShape(.capsule)
    }
}

// MARK: - View
struct LockedTopBarView: View {
    @Bindable var cameraModel: LockedCameraModel
    @Binding var selectedControl: ManualControl?
    let theme: AppTheme
    @State private var hapticTrigger = 0
    @State private var hapticTriggerR = 0
    
    var body: some View {
        VStack(spacing: Style.rowSpacing) {
            // MARK: Row 1
            HStack(alignment: .center, spacing: Style.row1Spacing) {
                readouts()
            }
            .padding(.horizontal, Style.row1HPadding)
            
            // MARK: Row 2
            HStack(alignment: .center, spacing: Style.row2Spacing) {
                resolutionPicker()
                formatPicker()
            }
            .padding(.horizontal, Style.row2HPadding)
            
            // MARK: Row 3
            HStack(alignment: .center, spacing: Style.row3Spacing) {
                flashButton()
                macroButton()
                timerButton()
            }
            .padding(.horizontal, Style.row3HPadding)
            .animation(Animations.bouncy, value: cameraModel.isAutoFocus)
        }
        .sensoryFeedback(.impact, trigger: hapticTrigger)
        .sensoryFeedback(.impact(flexibility: .soft), trigger: hapticTriggerR)
        .onChange(of: cameraModel.isAutoExposure) { _, isAutoExposure in
            guard !isAutoExposure, selectedControl == .ev else { return }
            
            withAnimation(Animations.bouncy) {
                selectedControl = nil
            }
        }
    }
}
