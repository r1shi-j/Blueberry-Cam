import SwiftUI

extension CameraModel {
    fileprivate var shutterLabel: String {
        let denom = manualShutterDenominator
        if denom <= 0 {
            guard shutterSpeeds.indices.contains(shutterIndex) else { return "--" }
            return CameraModel.formatShutter(shutterSpeeds[shutterIndex])
        }
        return "1/\(denom)"
    }
}

extension ManualControlsView {
    private var exposureString: String { "Exposure" }
    private var evString: String { "EV" }
    private var isoString: String { "ISO" }
    private var ssString: String { "Shutter" }
    private var focusString: String { "Focus" }
    private var focusPeakingString: String { "Focus Peaking" }
    private var focusLoupeString: String { "Focus Loupe" }
    private var wbString: String { "White Balance" }
    
    private var customEVValue: String { cameraModel.exposureBias.signedSingleDecimalString }
    private var customISOValue: String { "\(Int(cameraModel.iso))" }
    private var customSSValue: String { cameraModel.shutterLabel }
    private var customFocusValue: String { Double(cameraModel.lensPosition).formatted(.number.precision(.fractionLength(2))) }
    private var customWBValue: String { "\(Int(cameraModel.whiteBalanceTargetKelvin))K" }
    
    private func conditionalTextColor(for bool: Bool) -> Color {
        bool ? .yellow : .white
    }
    
    private func conditionalTextLabel(for bool: Bool) -> String {
        bool ? "AUTO" : "MANUAL"
    }
}

struct ManualControlsView: View {
    @Bindable var cameraModel: CameraModel
    let control: ManualControl
    
    var body: some View {
        VStack {
            switch control {
                case .ev:
                    // MARK: EV
                    HStack {
                        Text(exposureString.uppercased())
                            .font(Fonts.manualLabel)
                            .foregroundStyle(Colors.manualLabel)
                            .tracking(2)
                        Spacer()
                        Toggle("", isOn: $cameraModel.isAutoExposure)
                            .labelsHidden()
                            .tint(.yellow)
                            .onChange(of: cameraModel.isAutoExposure) { _, auto in
                                if auto {
                                    cameraModel.setAutoExposure()
                                } else {
                                    cameraModel.resetEV()
                                    cameraModel.applyManualExposure()
                                }
                            }
                        Text(conditionalTextLabel(for: cameraModel.isAutoExposure))
                            .font(Fonts.manualLabel)
                            .foregroundStyle(conditionalTextColor(for: cameraModel.isAutoExposure))
                    }
                    .padding(.horizontal, 20)
                    
                    if cameraModel.isAutoExposure {
                        HStack {
                            Text(evString.uppercased())
                                .font(Fonts.manualLabel)
                                .foregroundStyle(Colors.manualLabel)
                                .tracking(2)
                                .frame(width: 60, alignment: .leading)
                            Slider(value: $cameraModel.exposureBias, in: -4.0...4.0, step: 0.1)
                                .onChange(of: cameraModel.exposureBias) {
                                    cameraModel.applyExposureBias()
                                }
                                .tint(.yellow)
                            Text(customEVValue)
                                .font(Fonts.manualValue)
                                .foregroundStyle(.yellow)
                                .frame(width: 50, alignment: .trailing)
                        }
                        .padding(.horizontal, 20)
                    }
                case .iso:
                    // MARK: ISO
                    HStack {
                        Text(exposureString.uppercased())
                            .font(Fonts.manualLabel)
                            .foregroundStyle(Colors.manualLabel)
                            .tracking(2)
                        Spacer()
                        Toggle("", isOn: $cameraModel.isAutoExposure)
                            .labelsHidden()
                            .tint(.yellow)
                            .onChange(of: cameraModel.isAutoExposure) { _, auto in
                                if auto {
                                    cameraModel.setAutoExposure()
                                } else {
                                    cameraModel.resetEV()
                                    cameraModel.applyManualExposure()
                                }
                            }
                        Text(conditionalTextLabel(for: cameraModel.isAutoExposure))
                            .font(Fonts.manualLabel)
                            .foregroundStyle(conditionalTextColor(for: cameraModel.isAutoExposure))
                    }
                    .padding(.horizontal, 20)
                    
                    if !cameraModel.isAutoExposure {
                        VStack(spacing: 4) {
                            HStack {
                                Text(isoString.uppercased())
                                    .font(Fonts.manualLabel)
                                    .foregroundStyle(Colors.manualLabel)
                                    .tracking(2)
                                    .frame(width: 60, alignment: .leading)
                                Slider(value: $cameraModel.iso, in: cameraModel.minISO...cameraModel.maxISO, step: 1)
                                    .onChange(of: cameraModel.iso) {
                                        cameraModel.applyManualExposure()
                                    }
                                    .tint(.yellow)
                                Text(customISOValue)
                                    .font(Fonts.manualValue)
                                    .foregroundStyle(.yellow)
                                    .frame(width: 50, alignment: .trailing)
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                case .ss:
                    // MARK: SS
                    HStack {
                        Text(exposureString.uppercased())
                            .font(Fonts.manualLabel)
                            .foregroundStyle(Colors.manualLabel)
                            .tracking(2)
                        Spacer()
                        Toggle("", isOn: $cameraModel.isAutoExposure)
                            .labelsHidden()
                            .tint(.yellow)
                            .onChange(of: cameraModel.isAutoExposure) { _, auto in
                                if auto {
                                    cameraModel.setAutoExposure()
                                } else {
                                    cameraModel.resetEV()
                                    cameraModel.applyManualExposure()
                                }
                            }
                        Text(conditionalTextLabel(for: cameraModel.isAutoExposure))
                            .font(Fonts.manualLabel)
                            .foregroundStyle(conditionalTextColor(for: cameraModel.isAutoExposure))
                    }
                    .padding(.horizontal, 20)
                    
                    if !cameraModel.isAutoExposure {
                        VStack(spacing: 4) {
                            HStack {
                                Text(ssString.uppercased())
                                    .font(Fonts.manualLabel)
                                    .foregroundStyle(Colors.manualLabel)
                                    .tracking(2)
                                    .frame(width: 60, alignment: .leading)
                                Slider(
                                    value: Binding(get: {
                                        Double(cameraModel.shutterIndex)
                                    }, set: {
                                        cameraModel.setCustomShutter(to: Int($0))
                                        cameraModel.applyManualExposure()
                                    }),
                                    in: 0...Double(max(0, cameraModel.shutterSpeeds.count - 1)),
                                    step: 1
                                )
                                .tint(.yellow)
                                Text(customSSValue)
                                    .font(Fonts.manualValue)
                                    .foregroundStyle(.yellow)
                                    .frame(width: 65, alignment: .trailing)
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                case .f:
                    // MARK: Focus
                    HStack {
                        Text(focusString.uppercased())
                            .font(Fonts.manualLabel)
                            .foregroundStyle(Colors.manualLabel)
                            .tracking(2)
                        Spacer()
                        Toggle("", isOn: $cameraModel.isAutoFocus)
                            .labelsHidden()
                            .tint(.yellow)
                            .disabled(!cameraModel.supportsManualFocus)
                            .onChange(of: cameraModel.isAutoFocus) { _, auto in
                                if auto { cameraModel.setAutoFocus() }
                                else { cameraModel.applyManualFocus() }
                            }
                        Text(conditionalTextLabel(for: cameraModel.isAutoFocus))
                            .font(Fonts.manualLabel)
                            .foregroundStyle(conditionalTextColor(for: cameraModel.isAutoFocus))
                    }
                    .padding(.horizontal, 20)
                    
                    if !cameraModel.isAutoFocus {
                        HStack {
                            Text(focusPeakingString.uppercased())
                                .font(Fonts.manualLabel)
                                .foregroundStyle(Colors.manualLabel)
                                .tracking(2)
                            Spacer()
                            Toggle("", isOn: $cameraModel.showFocusPeaking)
                                .labelsHidden()
                                .tint(.green)
                        }
                        .padding(.horizontal, 20)
                        HStack {
                            Text(focusLoupeString.uppercased())
                                .font(Fonts.manualLabel)
                                .foregroundStyle(Colors.manualLabel)
                                .tracking(2)
                            Spacer()
                            Toggle("", isOn: $cameraModel.showFocusLoupe)
                                .labelsHidden()
                                .tint(.green)
                        }
                        .padding(.horizontal, 20)
                        HStack {
                            Text("")
                                .font(Fonts.manualLabel)
                                .tracking(2)
                                .frame(width: 60, alignment: .leading)
                            Slider(value: $cameraModel.lensPosition, in: 0...1, onEditingChanged: { editing in
                                if editing {
                                    cameraModel.beginManualFocusAdjustment()
                                } else {
                                    cameraModel.endManualFocusAdjustment()
                                }
                            })
                            .onChange(of: cameraModel.lensPosition) {
                                cameraModel.applyManualFocus()
                            }
                            .tint(.yellow)
                            Text(customFocusValue)
                                .font(Fonts.manualValue)
                                .foregroundStyle(.yellow)
                                .frame(width: 50, alignment: .trailing)
                        }
                        .padding(.horizontal, 20)
                    }
                case .wb:
                    // MARK: WB
                    HStack {
                        Text(wbString.uppercased())
                            .font(Fonts.manualLabel)
                            .foregroundStyle(Colors.manualLabel)
                            .tracking(2)
                        Spacer()
                        Toggle("", isOn: $cameraModel.isAutoWhiteBalance)
                            .labelsHidden()
                            .tint(.yellow)
                        Text(conditionalTextLabel(for: cameraModel.isAutoWhiteBalance))
                            .font(Fonts.manualLabel)
                            .foregroundStyle(conditionalTextColor(for: cameraModel.isAutoWhiteBalance))
                    }
                    .padding(.horizontal, 20)
                    
                    if !cameraModel.isAutoWhiteBalance {
                        HStack {
                            Text("")
                                .font(Fonts.manualLabel)
                                .tracking(2)
                                .frame(width: 60, alignment: .leading)
                            Slider(value: $cameraModel.whiteBalanceTargetKelvin, in: 2000...10000, step: 100)
                                .tint(.yellow)
                            Text(customWBValue)
                                .font(Fonts.manualValue)
                                .foregroundStyle(.yellow)
                                .frame(width: 65, alignment: .trailing)
                        }
                        .padding(.horizontal, 20)
                    }
            }
        }
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.black.opacity(0.65))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(.white.opacity(0.1), lineWidth: 1)
                )
        )
        .padding(.horizontal, 12)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}
