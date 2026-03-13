import SwiftUI
import CoreMedia

enum ManualControl: CaseIterable {
    case ev, iso, ss, f, wb
}

struct ManualControlsView: View {
    @Bindable var cameraModel: CameraModel
    let control: ManualControl
    
    var body: some View {
        VStack {
            switch control {
                case .ev:
                    HStack {
                        Text("EXPOSURE")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.5))
                            .tracking(2)
                        Spacer()
                        Toggle("Auto", isOn: $cameraModel.isAutoExposure)
                            .labelsHidden()
                            .tint(.yellow)
                            .onChange(of: cameraModel.isAutoExposure) { _, auto in
                                if auto { cameraModel.setAutoExposure() }
                                else {
                                    cameraModel.exposureBias = 0.0
                                    cameraModel.applyManualExposure()
                                }
                            }
                        Text(cameraModel.isAutoExposure ? "AUTO" : "MANUAL")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(cameraModel.isAutoExposure ? .yellow : .white)
                    }
                    .padding(.horizontal, 20)
                    
                    if cameraModel.isAutoExposure {
                        // EV Compensation (auto exposure only)
                        HStack {
                            Text("EV")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(.white.opacity(0.5))
                                .tracking(2)
                                .frame(width: 60, alignment: .leading)
                            Slider(
                                value: $cameraModel.exposureBias,
                                in: -4.0...4.0,
                                step: 0.1
                            ).onChange(of: cameraModel.exposureBias) { _, _ in
                                cameraModel.applyExposureBias()
                            }
                            .tint(.yellow)
                            Text(String(format: "%+.1f", cameraModel.exposureBias))
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .foregroundColor(.yellow)
                                .frame(width: 50, alignment: .trailing)
                        }
                        .padding(.horizontal, 20)
                    }
                case .iso:
                    HStack {
                        Text("EXPOSURE")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.5))
                            .tracking(2)
                        Spacer()
                        Toggle("Auto", isOn: $cameraModel.isAutoExposure)
                            .labelsHidden()
                            .tint(.yellow)
                            .onChange(of: cameraModel.isAutoExposure) { _, auto in
                                if auto { cameraModel.setAutoExposure() }
                                else {
                                    cameraModel.exposureBias = 0.0
                                    cameraModel.applyManualExposure()
                                }
                            }
                        Text(cameraModel.isAutoExposure ? "AUTO" : "MANUAL")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(cameraModel.isAutoExposure ? .yellow : .white)
                    }
                    .padding(.horizontal, 20)
                    
                    if !cameraModel.isAutoExposure {
                        // ISO
                        VStack(spacing: 4) {
                            HStack {
                                Text("ISO")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.5))
                                    .tracking(2)
                                    .frame(width: 60, alignment: .leading)
                                Slider(
                                    value: $cameraModel.iso,
                                    in: cameraModel.minISO...cameraModel.maxISO,
                                    step: 1
                                ).onChange(of: cameraModel.iso) { _, _ in
                                    cameraModel.applyManualExposure()
                                }
                                .tint(.yellow)
                                Text("\(Int(cameraModel.iso))")
                                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                                    .foregroundColor(.yellow)
                                    .frame(width: 50, alignment: .trailing)
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                case .ss:
                    HStack {
                        Text("EXPOSURE")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.5))
                            .tracking(2)
                        Spacer()
                        Toggle("Auto", isOn: $cameraModel.isAutoExposure)
                            .labelsHidden()
                            .tint(.yellow)
                            .onChange(of: cameraModel.isAutoExposure) { _, auto in
                                if auto { cameraModel.setAutoExposure() }
                                else {
                                    cameraModel.exposureBias = 0.0
                                    cameraModel.applyManualExposure()
                                }
                            }
                        Text(cameraModel.isAutoExposure ? "AUTO" : "MANUAL")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(cameraModel.isAutoExposure ? .yellow : .white)
                    }
                    .padding(.horizontal, 20)
                    
                    if !cameraModel.isAutoExposure {
                        // Shutter Speed — stop-based (fastest on left, slowest on right)
                        // shutterSpeeds[0] = fastest, [count-1] = slowest → equal spacing per photographic stop
                        VStack(spacing: 4) {
                            HStack {
                                Text("SHUTTER")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundColor(.white.opacity(0.5))
                                    .tracking(2)
                                    .frame(width: 60, alignment: .leading)
                                Slider(
                                    value: Binding(
                                        get: { Double(cameraModel.shutterIndex) },
                                        set: {
                                            cameraModel.manualShutterDenominator = 0   // use stop-based path
                                            cameraModel.shutterIndex = Int($0)
                                            cameraModel.applyManualExposure()
                                        }
                                    ),
                                    in: 0...Double(max(0, cameraModel.shutterSpeeds.count - 1)),
                                    step: 1
                                )
                                .tint(.yellow)
                                Text(shutterLabel)
                                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                                    .foregroundColor(.yellow)
                                    .frame(width: 65, alignment: .trailing)
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                case .f:
                    HStack {
                        Text("FOCUS")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.5))
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
                        Text(cameraModel.isAutoFocus ? "AUTO" : "MANUAL")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(cameraModel.isAutoFocus ? .yellow : .white)
                    }
                    .padding(.horizontal, 20)
                    
                    if !cameraModel.isAutoFocus {
                        HStack {
                            Text("")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(.white.opacity(0.5))
                                .tracking(2)
                                .frame(width: 60, alignment: .leading)
                            Slider(value: $cameraModel.lensPosition, in: 0...1, onEditingChanged: { editing in
                                if editing {
                                    cameraModel.beginManualFocusAdjustment()
                                } else {
                                    cameraModel.endManualFocusAdjustment()
                                }
                            }).onChange(of: cameraModel.lensPosition) { _, _ in
                                cameraModel.applyManualFocus()
                            }
                            .tint(.yellow)
                            Text(String(format: "%.2f", cameraModel.lensPosition))
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .foregroundColor(.yellow)
                                .frame(width: 50, alignment: .trailing)
                        }
                        .padding(.horizontal, 20)
                    }
                case .wb:
                    HStack {
                        Text("WHITE BALANCE")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(.white.opacity(0.5))
                            .tracking(2)
                        Spacer()
                        Toggle("", isOn: $cameraModel.isAutoWhiteBalance)
                            .labelsHidden()
                            .tint(.yellow)
                        Text(cameraModel.isAutoWhiteBalance ? "AUTO" : "MANUAL")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(cameraModel.isAutoWhiteBalance ? .yellow : .white)
                    }
                    .padding(.horizontal, 20)
                    
                    if !cameraModel.isAutoWhiteBalance {
                        HStack {
                            Text("")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(.white.opacity(0.5))
                                .tracking(2)
                                .frame(width: 60, alignment: .leading)
                            Slider(
                                value: $cameraModel.whiteBalanceTargetKelvin,
                                in: 2000...10000,
                                step: 100
                            )
                            .tint(.yellow)
                            Text("\(Int(cameraModel.whiteBalanceTargetKelvin))K")
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .foregroundColor(.yellow)
                                .frame(width: 65, alignment: .trailing)
                        }
                        .padding(.horizontal, 20)
                    }
            }
        }
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.65))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
        .padding(.horizontal, 12)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
    
    private var shutterLabel: String {
        let denom = cameraModel.manualShutterDenominator
        if denom <= 0 {
            guard cameraModel.shutterSpeeds.indices.contains(cameraModel.shutterIndex) else { return "--" }
            return CameraModel.formatShutter(cameraModel.shutterSpeeds[cameraModel.shutterIndex])
        }
        return "1/\(denom)"
    }
}
