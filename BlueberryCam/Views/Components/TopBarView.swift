import AVFoundation
import SwiftUI

// MARK: - Shared icon constants (single source of truth)
private enum IconStyle {
    /// Diameter of every circle icon
    static let size: CGFloat = 26
    /// SF Symbol font — sized so symbols fill the circle similarly to a bold letter
    static let symbolFont = Font.system(size: 13, weight: .semibold)
    /// Monospaced font for text icons (Z, P)
    static let textFont = Font.system(size: 11, weight: .bold, design: .monospaced)
    /// Padding for pill-shaped labels (format, readout)
    static let pillH: CGFloat = 9
    static let pillV: CGFloat = 5
}

extension TopBarView {
    
    // MARK: - Readout buttons (EV / ISO / SS / F / WB)
    private func readoutColor(for control: ManualControl) -> Color {
        switch control {
            case .ev: return .orange
            case .iso: return .yellow
            case .ss: return Color.white.opacity(0.8)
            case .f:  return .green
            case .wb: return .cyan
        }
    }
    
    private func readoutTitle(for control: ManualControl) -> String {
        switch control {
            case .ev:  return String(format: "EV %+.1f", cameraModel.exposureBias)
            case .iso: return "ISO \(Int(cameraModel.liveISO))"
            case .ss:  return cameraModel.liveShutter
            case .f:   return cameraModel.liveFocus
            case .wb:  return cameraModel.liveWB
        }
    }
    
    private func isReadoutUnderlined(for control: ManualControl) -> Bool {
        (control == ManualControl.ev && cameraModel.exposureBias != 0.0) ||
        (control == ManualControl.iso && !cameraModel.isAutoExposure) ||
        (control == ManualControl.ss && !cameraModel.isAutoExposure) ||
        (control == ManualControl.f && !cameraModel.isAutoFocus) ||
        (control == ManualControl.wb && !cameraModel.isAutoWhiteBalance)
    }
    
    private func readoutText(for control: ManualControl) -> Text {
        var str = AttributedString(readoutTitle(for: control))
        if isReadoutUnderlined(for: control) {
            str.underlineStyle = .single
            str.underlineColor = .yellow
        }
        return Text(str)
    }
    
    private func isReadoutDisabled(for control: ManualControl) -> Bool {
        (control == ManualControl.ev && !cameraModel.isAutoExposure) ||
        (control == ManualControl.iso && cameraModel.isAutoExposure) ||
        (control == ManualControl.ss && cameraModel.isAutoExposure) ||
        (control == ManualControl.f && cameraModel.isAutoFocus) ||
        (control == ManualControl.wb && cameraModel.isAutoWhiteBalance)
    }
    
    // MARK: - Unified icon button (circle, SF Symbol)
    /// All top-bar icon buttons funnel through here for consistent sizing.
    private func iconButton(
        symbol: String,
        fg: Color = Colors.buttonText,
        bg: Color = Colors.buttonBackground,
        opacity: Double = 1.0,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            hapticLight.impactOccurred()
            action()
        } label: {
            Image(systemName: symbol)
                .font(IconStyle.symbolFont)
                .foregroundColor(fg)
                .frame(width: IconStyle.size, height: IconStyle.size)
                .background(bg)
                .clipShape(Circle())
                .opacity(opacity)
        }
    }
    
    // MARK: - Circle text button (for Z, P — same 32×32 as iconButton but with a text label)
    private func circleTextButton(
        label: String,
        fg: Color,
        bg: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            hapticLight.impactOccurred()
            action()
        } label: {
            Text(label)
                .font(IconStyle.textFont)
                .foregroundColor(fg)
                .frame(width: IconStyle.size - 2, height: IconStyle.size - 2)
                .background(bg)
                .clipShape(Circle())
        }
    }
    
    // MARK: - Pill button (for format/resolution labels)
    private func pillButton(
        label: String,
        fg: Color,
        bg: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            hapticLight.impactOccurred()
            action()
        } label: {
            Text(label)
                .font(IconStyle.textFont)
                .foregroundColor(fg)
                .padding(.horizontal, IconStyle.pillH)
                .padding(.vertical, IconStyle.pillV)
                .background(bg)
                .clipShape(Capsule())
        }
    }
    
    // MARK: - Histogram pill
    private var chartSymbol: String { "chart.bar.fill" }
    
    private func histogramButton() -> some View {
        ZStack {
            if cameraModel.histogramModeSmall == .none && cameraModel.histogramModeLarge == .none {
                Button {
                    hapticLight.impactOccurred()
                    withAnimation(.spring()) {
                        cameraModel.cycleHistogramMode(mode: &cameraModel.histogramModeSmall, size: .small)
                        cameraModel.cycleHistogramMode(mode: &cameraModel.histogramModeLarge, size: .large)
                    }
                } label: {
                    Image(systemName: chartSymbol)
                        .font(IconStyle.symbolFont)
                        .foregroundColor(Colors.buttonText)
                        .padding(.horizontal, IconStyle.pillH)
                        .padding(.vertical, IconStyle.pillV)
                        .background(Colors.buttonBackground)
                        .clipShape(Capsule())
                }
            } else {
                Button {
                    hapticLight.impactOccurred()
                    withAnimation(.spring()) {
                        cameraModel.hideHistogram(for: .small)
                        cameraModel.hideHistogram(for: .large)
                    }
                } label: {
                    Image(systemName: chartSymbol)
                        .font(IconStyle.symbolFont)
                        .foregroundColor(.black)
                        .padding(.horizontal, IconStyle.pillH)
                        .padding(.vertical, IconStyle.pillV)
                        .background(Color.yellow)
                        .clipShape(Capsule())
                }
            }
        }
        .animation(.spring(), value: cameraModel.histogramModeSmall)
        .animation(.spring(), value: cameraModel.histogramModeLarge)
    }
    
    // MARK: - Flash button
    private func flashButton() -> some View {
        let (symbol, isActive) = cameraModel.flashLabel
        let supported = cameraModel.supportsFlash && cameraModel.isAutoExposure
        return iconButton(
            symbol: symbol,
            fg: isActive ? .black : Colors.buttonText,
            bg: isActive ? .yellow : Colors.buttonBackground,
            opacity: supported ? 1.0 : 0.3
        ) {
            cameraModel.cycleFlashMode()
        }
        .disabled(!supported)
    }
    
    // MARK: - Clean UI button
    private func cleanUIButton() -> some View {
        let isClean = cameraModel.appView == .clean
        return iconButton(
            symbol: isClean ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
            fg: isClean ? .black : Colors.buttonText,
            bg: isClean ? .yellow : Colors.buttonBackground
        ) {
            withAnimation(.spring()) {
                cameraModel.appView = isClean ? .standard : .clean
            }
        }
    }
}

struct TopBarView: View {
    @ObservedObject var cameraModel: CameraModel
    @Binding var selectedControl: ManualControl?
    private let hapticLight = UIImpactFeedbackGenerator(style: .light)
    private let hapticSoft = UIImpactFeedbackGenerator(style: .soft)
    
    var body: some View {
        VStack(spacing: 0) {
            // MARK: Row 1
            HStack(alignment: .center, spacing: 8) {
                histogramButton()
                
                // Zebra
                circleTextButton(
                    label: "Z",
                    fg: cameraModel.showZebraStripes ? .black : Colors.buttonText,
                    bg: cameraModel.showZebraStripes ? .yellow : Colors.buttonBackground
                ) { cameraModel.toggleZebraStripes() }
                
                // Highlight clipping
                circleTextButton(
                    label: "P",
                    fg: cameraModel.showClipping ? .black : Colors.buttonText,
                    bg: cameraModel.showClipping ? .yellow : Colors.buttonBackground
                ) { cameraModel.toggleClipping() }
                
                // Only show format/resolution row when there's something to pick
                if !cameraModel.activeLens.isFront && cameraModel.availableFormats.count > 1 {
                    HStack {
                        ForEach(cameraModel.availableFormats) { mode in
                            let isEnabled = cameraModel.isFormatEnabled(mode)
                            let isSelected = cameraModel.captureMode == mode
                            Button {
                                hapticLight.impactOccurred()
                                cameraModel.changeCaptureFormat(to: mode)
                            } label: {
                                Text(mode.rawValue)
                                    .font(IconStyle.textFont)
                                    .foregroundColor(isSelected ? .black : (isEnabled ? Colors.buttonText : Colors.buttonText.opacity(0.3)))
                                    .padding(.horizontal, IconStyle.pillH)
                                    .padding(.vertical, IconStyle.pillV)
                                    .background(isSelected ? Color.yellow : (isEnabled ? Colors.buttonBackground : Colors.buttonBackground.opacity(0.3)))
                                    .clipShape(Capsule())
                            }
                            .disabled(!isEnabled)
                        }
                    }
                }
                
                flashButton()
                
                // Settings gear
                iconButton(symbol: "gear") {
                    withAnimation(.spring()) { cameraModel.appView = .settings }
                }
                
                cleanUIButton()
            }
            .padding(.horizontal, 6)
            .padding(.top, 8)
            .padding(.bottom, 6)
            
            // MARK: Row 2
            HStack(alignment: .center, spacing: 10) {
                // MARK: - Readout values
                ForEach(ManualControl.allCases, id: \.self) { control in
                    readoutText(for: control)
                        .padding(.horizontal, 4)
                        .font(.system(size: 12, weight: selectedControl == control ? .black : .regular, design: .monospaced))
                        .foregroundColor(readoutColor(for: control))
                        .onTapGesture(count: 2) {
                            hapticSoft.impactOccurred()
                            withAnimation(.bouncy) {
                                cameraModel.resetControl(for: control)
                            }
                        }
                        .onLongPressGesture {
                            hapticSoft.impactOccurred()
                            withAnimation(.bouncy) {
                                cameraModel.resetControl(for: control)
                            }
                        }
                        .disabled(isReadoutDisabled(for: control))
                        .onTapGesture {
                            hapticLight.impactOccurred()
                            withAnimation(.bouncy) {
                                selectedControl = selectedControl == control ? nil : control
                            }
                        }
                }
            }
            .padding(.top, 3)
            .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity)
    }
}
