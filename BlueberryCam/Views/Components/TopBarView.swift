internal import AVFoundation
import SwiftUI

extension TopBarView {
    // MARK: - Constants
    private enum Style {
        static let disabledOpacity = 0.3
        static let selectedForeground: Color = .black
        static let buttonHeight: CGFloat = 18
        static let horizontalButtonPadding: CGFloat = 8
        static let verticalButtonPadding: CGFloat = 5
        static let horizontalPickerPadding: CGFloat = 8
        static let pickerCornerRadius: CGFloat = 6
        static let verticalPadding: CGFloat = 0
        static let expandedVerticalPadding: CGFloat = 10
        static let rowSpacing: CGFloat = 14
        static let expandedRowSpacing: CGFloat = 24
        static let row1Spacing: CGFloat = 12
        static let row2Spacing: CGFloat = 16
        static let row3Spacing: CGFloat = 16
        static let row1HPadding: CGFloat = 4
        static let row2HPadding: CGFloat = 8
        static let row3HPadding: CGFloat = 8
        static let readoutRowTransitionOffset: CGFloat = -10
    }
    
    private enum Fonts {
        static let picker: Font = .system(size: 12, weight: .medium)
        static let pickerIcon: Font = .system(size: 13, weight: .medium)
        static let readoutSize: CGFloat = 14
        static let button: Font = .system(size: 12, weight: .bold)
        static let buttonInfo: Font = .system(size: 12, weight: .medium, design: .monospaced)
    }
    
    // MARK: Properties
    // MARK: - Capture Aspect Ratio properties
    private var captureAspectRatioButtonRotation: Angle {
        cameraModel.selectedCaptureAspectRatio == .landscape4x3 ? .degrees(90) : .zero
    }
    
    private var row2AccessoryTransition: AnyTransition {
        .opacity.combined(with: .scale(scale: 0.94, anchor: .leading))
    }
    
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
        return isFormatSelected(mode) ? Style.selectedForeground : .white
    }
    
    private func formatBackground(for mode: CaptureMode, isEnabled: Bool) -> Color {
        guard isEnabled else { return Colors.buttonBackground.opacity(Style.disabledOpacity) }
        return isFormatSelected(mode) ? theme.accent : Colors.buttonBackground
    }
    
    private var displayedFormats: [CaptureMode] {
        cameraModel.shownAvailableFormats(includeRaw: !cameraModel.shouldUseDualCameraFormatSet)
    }
    
    private var displayedCaptureMode: CaptureMode {
        guard cameraModel.shouldUseDualCameraFormatSet,
              cameraModel.captureMode.isRawLike else {
            return cameraModel.captureMode
        }
        
        return cameraModel.preferredProcessedCaptureMode(in: displayedFormats) ?? displayedFormats.first ?? cameraModel.captureMode
    }
    
    private func isFormatSelected(_ mode: CaptureMode) -> Bool {
        displayedCaptureMode == mode
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
        (cameraModel.supportsFlash && cameraModel.isAutoExposure && !cameraModel.isBurstModeEnabled) ? 1.0 : Style.disabledOpacity
    }
    
    private var isFlashButtonDisabled: Bool {
        !(cameraModel.supportsFlash && cameraModel.isAutoExposure && !cameraModel.isBurstModeEnabled)
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
    
    // MARK: - Dual Camera properties
    private var dualcamButtonSymbol: String {
        "inset.filled.rectangle.and.person.filled"
    }
    
    private var dualcamButtonForeground: Color {
        cameraModel.isDualCameraEnabled ? Style.selectedForeground : Colors.buttonText
    }
    
    private var dualcamButtonBackground: Color {
        cameraModel.isDualCameraEnabled ? theme.accent : Colors.buttonBackground
    }
    
    private var dualcamButtonOpacity: Double {
        guard cameraModel.supportsDualCamera else { return Style.disabledOpacity }
        return cameraModel.isDualCameraEnabled || !cameraModel.isSwitchingLens ? 1.0 : Style.disabledOpacity
    }
    
    private var isDualcamButtonDisabled: Bool {
        !cameraModel.supportsDualCamera || cameraModel.isSwitchingLens
    }
    
    // MARK: - Burst properties
    private var burstButtonSymbol: String {
        "square.stack.3d.down.right"
    }
    
    private var burstButtonForeground: Color {
        cameraModel.isBurstModeEnabled ? Style.selectedForeground : Colors.buttonText
    }
    
    private var burstButtonBackground: Color {
        cameraModel.isBurstModeEnabled ? theme.accent : Colors.buttonBackground
    }
    
    private var burstButtonOpacity: Double {
        cameraModel.canUseBurstButton ? 1.0 : Style.disabledOpacity
    }
    
    private var isBurstButtonDisabled: Bool {
        !cameraModel.canUseBurstButton
    }
    
    private var parsedBurstInterval: Double? {
        Double(burstIntervalInput)
    }
    
    private var parsedBurstFrameLimit: Int? {
        Int(burstFrameLimitInput)
    }
    
    private var isBurstIntervalInputValid: Bool {
        guard let parsedBurstInterval else { return false }
        return parsedBurstInterval >= CameraModel.burstIntervalMin && parsedBurstInterval <= CameraModel.burstIntervalMax
    }
    
    private var isBurstFrameLimitInputValid: Bool {
        guard let parsedBurstFrameLimit else { return false }
        return parsedBurstFrameLimit >= CameraModel.burstFrameLimitMin && parsedBurstFrameLimit <= CameraModel.burstFrameLimitMax
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
    
    private var timerButtonOpacity: Double {
        cameraModel.isBurstModeEnabled ? Style.disabledOpacity : 1.0
    }
    
    private var isTimerButtonDisabled: Bool {
        cameraModel.isBurstModeEnabled
    }
    
    // MARK: - Selfie Switch properties
    private var selfieButtonSymbol: String {
        "arrow.trianglehead.2.clockwise.rotate.90.camera.fill"
    }
    
    private var selfieButtonForeground: Color {
        Colors.buttonText
    }
    
    private var selfieButtonBackground: Color {
        Colors.buttonBackground
    }
    
    private var isSelfieButtonDisabled: Bool {
        cameraModel.isSwitchingLens || !cameraModel.canToggleSelfie
    }
    
    private var shouldShowSelfieButton: Bool {
        if cameraModel.isDualCameraEnabled || cameraModel.isDualCameraTransitionCoverVisible || cameraModel.secondaryLens != nil {
            return true
        }
        
        return cameraModel.supportsSelfieToggle
    }
    
    private var selfieButtonOpacity: Double {
        isSelfieButtonDisabled ? Style.disabledOpacity : 1.0
    }
    
    // MARK: - Focus Assist properties
    private var focusAssistButtonSymbol: String {
        if cameraModel.showFocusLoupe {
            return "plus.magnifyingglass"
        }
        
        if cameraModel.showFocusPeaking {
            return "person.and.background.dotted"
        }
        
        return "camera.viewfinder"
    }
    
    private var focusAssistButtonForeground: Color {
        cameraModel.showFocusLoupe || cameraModel.showFocusPeaking ? Style.selectedForeground : .green
    }
    
    private var focusAssistButtonBackground: Color {
        cameraModel.showFocusLoupe || cameraModel.showFocusPeaking ? .green : Colors.buttonBackground
    }
    
    // MARK: - General Readout properties
    private func readoutColor(for control: ManualControl) -> Color {
        guard !isReadoutDisabled(for: control) else {
            return usesAppThemeReadouts ? theme.readoutColor.opacity(Style.disabledOpacity) : Colors.buttonText.opacity(Style.disabledOpacity)
        }
        
        if usesAppThemeReadouts {
            return theme.readoutColor
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
            case .iso: "ISO \(cameraModel.isAutoExposure && cameraModel.liveISO > 0 ? CameraModel.formatISO(cameraModel.liveISO) : cameraModel.formattedISO)"
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
        if cameraModel.isDualCameraEnabled && control != .ev {
            return true
        }
        
        if cameraModel.isFilterRestrictingCaptureOptions && isExposurePairControl(control) {
            return true
        }
        
        return (control == ManualControl.ev && !cameraModel.isAutoExposure) ||
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
    
    // MARK: - Capture Aspect Ratio
    private func captureAspectRatioButton() -> some View {
        Button {
            hapticTriggerR += 1
            withAnimation(Animations.bouncy) {
                cameraModel.cycleCaptureAspectRatio()
            }
        } label: {
            Label("Switch aspect ratio", systemImage: "aspectratio")
                .labelStyle(.iconOnly)
                .rotationEffect(captureAspectRatioButtonRotation)
        }
        .font(Fonts.pickerIcon)
        .fontWidth(.expanded)
        .padding(.horizontal, Style.horizontalPickerPadding)
        .padding(.vertical, Style.verticalButtonPadding)
        .background(theme.accent)
        .foregroundStyle(Style.selectedForeground)
        .clipShape(.rect(cornerRadius: Style.pickerCornerRadius))
        .overlay(RoundedRectangle(cornerRadius: Style.pickerCornerRadius).stroke(.white.opacity(0.2), lineWidth: 1))
        .allowsHitTesting(cameraModel.canCycleCaptureAspectRatio)
        .animation(.smooth(duration: 0.22), value: cameraModel.selectedCaptureAspectRatio)
        .animation(Animations.bouncy, value: cameraModel.selectedCaptureAspectRatio)
        .animation(Animations.bouncy, value: cameraModel.availableCaptureAspectRatios)
        .accessibilityValue(cameraModel.selectedCaptureAspectRatio.label)
    }
    
    // MARK: - Resolution picker
    private func resolutionPicker() -> some View {
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
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
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
        .allowsHitTesting(!cameraModel.isSwitchingLens)
        .fixedSize(horizontal: true, vertical: false)
    }
    
    // MARK: - Row 2 accessory
    @ViewBuilder
    private func row2LeadingAccessory() -> some View {
        if cameraModel.shouldShowCaptureAspectRatioButton {
            captureAspectRatioButton()
                .fixedSize(horizontal: true, vertical: false)
                .transition(row2AccessoryTransition)
        } else if cameraModel.shouldShowResolutionPicker {
            resolutionPicker()
                .transition(row2AccessoryTransition)
        }
    }
    
    // MARK: - Format picker
    private func formatPicker() -> some View {
        HStack(spacing: 0) {
            ForEach(displayedFormats) { mode in
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
                .transition(.opacity.combined(with: .scale(scale: 0.86)))
            }
        }
        .clipShape(.rect(cornerRadius: Style.pickerCornerRadius))
        .overlay(RoundedRectangle(cornerRadius: Style.pickerCornerRadius).stroke(.white.opacity(0.2), lineWidth: 1))
        .animation(Animations.bouncy, value: cameraModel.enabledFormats)
        .animation(Animations.bouncy, value: cameraModel.availableFormats)
        .animation(Animations.bouncy, value: cameraModel.shownCaptureFormats)
        .animation(Animations.bouncy, value: cameraModel.shouldUseDualCameraFormatSet)
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
    
    // MARK: - Dual Camera
    private func dualcamButton() -> some View {
        Button {
            hapticTrigger += 1
            withAnimation(Animations.bouncy) {
                cameraModel.toggleDualCameraMode()
            }
        } label: {
            imageIcon(systemName: dualcamButtonSymbol, foregroundStyle: dualcamButtonForeground, background: dualcamButtonBackground)
        }
        .disabled(!cameraModel.supportsDualCamera)
        .allowsHitTesting(!isDualcamButtonDisabled)
        .opacity(dualcamButtonOpacity)
        .animation(Animations.bouncy, value: cameraModel.isSwitchingLens)
    }
    
    // MARK: - Burst
    private func burstButton() -> some View {
        imageIcon(foregroundStyle: burstButtonForeground, background: burstButtonBackground) {
            HStack(spacing: 10) {
                Button {
                    hapticTrigger += 1
                    withAnimation(Animations.bouncy) {
                        cameraModel.toggleBurstMode()
                    }
                } label: {
                    Image(systemName: burstButtonSymbol)
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
                        withAnimation(Animations.bouncy) {
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
                        withAnimation(Animations.bouncy) {
                            cameraModel.setBurstFrameLimit(nil)
                        }
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.7)))
                }
            }
        }
        .font(Fonts.button)
        .disabled(isBurstButtonDisabled)
        .opacity(burstButtonOpacity)
        .animation(Animations.bouncy, value: cameraModel.isBurstModeEnabled)
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
        .disabled(isTimerButtonDisabled)
        .opacity(timerButtonOpacity)
    }
    
    // MARK: - Selfie switch
    @ViewBuilder
    private func selfieButton() -> some View {
        if shouldShowSelfieButton {
            Button {
                hapticTrigger += 1
                guard !isSelfieButtonDisabled else { return }
                withAnimation(Animations.selfieToggled) {
                    cameraModel.toggleSelfie()
                }
            } label: {
                imageIcon(systemName: selfieButtonSymbol, foregroundStyle: selfieButtonForeground, background: selfieButtonBackground)
                    .rotation3DEffect(
                        .degrees(cameraModel.activeLens.isFront ? 180 : 0),
                        axis: (x: 0, y: 1, z: 0),
                        perspective: 0.1
                    )
                    .animation(Animations.selfieToggled, value: cameraModel.activeLens.isFront)
            }
            .opacity(selfieButtonOpacity)
            .allowsHitTesting(!isSelfieButtonDisabled)
            .transition(.opacity.combined(with: .scale(scale: 0.72)))
            .animation(Animations.bouncy, value: isSelfieButtonDisabled)
        }
    }
    
    // MARK: - Focus helper
    @ViewBuilder
    private func focusHelperButton() -> some View {
        if !cameraModel.isDualCameraEnabled, !cameraModel.isLiveFilterPreviewActive, !cameraModel.isAutoFocus {
            Button {
                hapticTrigger += 1
                withAnimation(Animations.bouncy) {
                    cameraModel.cycleFocusAssistMode()
                }
            } label: {
                imageIcon(systemName: focusAssistButtonSymbol, foregroundStyle: focusAssistButtonForeground, background: focusAssistButtonBackground)
            }
            .transition(.opacity.combined(with: .scale))
            .animation(Animations.bouncy, value: cameraModel.isAutoFocus)
        }
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
struct TopBarView: View {
    @Bindable var cameraModel: CameraModel
    @Binding var selectedControl: ManualControl?
    let theme: AppTheme
    let usesAppThemeReadouts: Bool
    @State private var hapticTrigger = 0
    @State private var hapticTriggerR = 0
    @State private var isShowingBurstIntervalAlert = false
    @State private var isShowingBurstFrameLimitAlert = false
    @State private var burstIntervalInput = ""
    @State private var burstFrameLimitInput = ""
    
    var body: some View {
        VStack(spacing: cameraModel.isDualCameraEnabled ? Style.expandedRowSpacing : Style.rowSpacing) {
            // MARK: Row 1
            if !cameraModel.isDualCameraEnabled {
                HStack(alignment: .center, spacing: Style.row1Spacing) {
                    readouts()
                }
                .padding(.horizontal, Style.row1HPadding)
                .transition(
                    .asymmetric(
                        insertion: .opacity
                            .combined(with: .move(edge: .top))
                            .combined(with: .scale(scale: 0.96, anchor: .top)),
                        removal: .opacity
                            .combined(with: .offset(y: Style.readoutRowTransitionOffset))
                            .combined(with: .scale(scale: 0.96, anchor: .top))
                    )
                )
            }
            
            // MARK: Row 2
            HStack(alignment: .center, spacing: Style.row2Spacing) {
                row2LeadingAccessory()
                formatPicker()
            }
            .padding(.horizontal, Style.row2HPadding)
            .animation(.smooth(duration: 0.24), value: cameraModel.activeLens.isFront)
            .animation(.smooth(duration: 0.24), value: cameraModel.shouldShowCaptureAspectRatioButton)
            .animation(.smooth(duration: 0.24), value: cameraModel.shouldShowResolutionPicker)
            .animation(.smooth(duration: 0.24), value: cameraModel.availableResolutions)
            .animation(Animations.bouncy, value: cameraModel.isDualCameraEnabled)
            
            // MARK: Row 3
            HStack(alignment: .center, spacing: Style.row3Spacing) {
                flashButton()
                macroButton()
                dualcamButton()
                burstButton()
                timerButton()
                selfieButton()
                focusHelperButton()
            }
            .padding(.horizontal, Style.row3HPadding)
            .animation(Animations.bouncy, value: cameraModel.isAutoFocus)
            .animation(Animations.bouncy, value: cameraModel.isDualCameraEnabled)
            .animation(Animations.bouncy, value: cameraModel.isSwitchingLens)
            .animation(Animations.bouncy, value: cameraModel.canToggleSelfie)
        }
        .padding(.vertical, cameraModel.isDualCameraEnabled ? Style.expandedVerticalPadding : Style.verticalPadding)
        .animation(Animations.bouncy, value: cameraModel.isDualCameraEnabled)
        .sensoryFeedback(.impact, trigger: hapticTrigger)
        .sensoryFeedback(.impact(flexibility: .soft), trigger: hapticTriggerR)
        .alert(Alerts.burstIntervalTitle, isPresented: $isShowingBurstIntervalAlert) {
            TextField(Alerts.auto, text: $burstIntervalInput)
                .keyboardType(.decimalPad)
            Button(Alerts.ok) {
                if let parsedBurstInterval {
                    cameraModel.setBurstInterval(seconds: parsedBurstInterval)
                }
            }
            .disabled(!isBurstIntervalInputValid)
            Button(Alerts.auto) {
                cameraModel.setBurstInterval(seconds: nil)
            }
            Button(Alerts.cancel, role: .cancel) {}
        } message: {
            Text(Alerts.burstIntervalMessage)
        }
        .alert(Alerts.burstFramesTitle, isPresented: $isShowingBurstFrameLimitAlert) {
            TextField(Alerts.infinityString, text: $burstFrameLimitInput)
                .keyboardType(.numberPad)
            Button(Alerts.ok) {
                if let parsedBurstFrameLimit {
                    cameraModel.setBurstFrameLimit(parsedBurstFrameLimit)
                }
            }
            .disabled(!isBurstFrameLimitInputValid)
            Button(Alerts.auto) {
                cameraModel.setBurstFrameLimit(nil)
            }
            Button(Alerts.cancel, role: .cancel) {}
        } message: {
            Text(Alerts.burstFramesMessage)
        }
        .onChange(of: cameraModel.isAutoExposure) { _, isAutoExposure in
            guard !isAutoExposure, selectedControl == .ev else { return }
            
            withAnimation(Animations.bouncy) {
                selectedControl = nil
            }
        }
        .onChange(of: cameraModel.isFilterRestrictingCaptureOptions) { _, isRestricting in
            guard isRestricting, isExposurePairControl(selectedControl) else { return }
            
            withAnimation(Animations.bouncy) {
                selectedControl = nil
            }
        }
        .onChange(of: cameraModel.isDualCameraEnabled) { _, isEnabled in
            guard isEnabled, selectedControl != .ev else { return }
            
            withAnimation(Animations.bouncy) {
                selectedControl = nil
            }
        }
    }
}
