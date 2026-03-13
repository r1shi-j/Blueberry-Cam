import SwiftUI
import AVFoundation

struct TopBarView: View {
    @Bindable var cameraModel: CameraModel
    @Binding var selectedControl: ManualControl?
    
    private let readoutColor: (ManualControl) -> Color = { control in
        switch control {
            case .ev: .orange
            case .iso: .yellow
            case .ss: .white.opacity(0.8)
            case .f: .green
            case .wb: .cyan
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
    
    var body: some View {
        VStack(spacing: 20) {
            HStack(alignment: .center, spacing: 30) {
                // Live EXIF
                // long press or double tap resets and enables auto
                // one tap opens slider
                ForEach(ManualControl.allCases, id: \.self) { control in
                    Text(readoutTitle(for: control))
                        .underline(selectedControl == control)
                        .foregroundColor(readoutColor(control))
                        .onTapGesture(count: 2) {
                            withAnimation(.spring(duration: 0.5)) {
                                cameraModel.resetControl(for: control)
                            }
                        }
                        .onLongPressGesture {
                            withAnimation(.spring(duration: 0.5)) {
                                cameraModel.resetControl(for: control)
                            }
                        }
                        .disabled(control == ManualControl.ev && !cameraModel.isAutoExposure)
                        .disabled(control == ManualControl.iso && cameraModel.isAutoExposure)
                        .disabled(control == ManualControl.ss && cameraModel.isAutoExposure)
                        .disabled(control == ManualControl.f && cameraModel.isAutoFocus)
                        .disabled(control == ManualControl.wb && cameraModel.isAutoWhiteBalance)
                        .onTapGesture {
                            withAnimation(.spring(duration: 0.5)) {
                                selectedControl = selectedControl == control ? nil : control
                            }
                        }
                }
            }
            .font(.system(size: 12, weight: .medium, design: .monospaced))
            .padding(.horizontal, 12)
            
            HStack(alignment: .center, spacing: 10) {
                // Location geotag toggle
                Button {
                    cameraModel.toggleLocationGeotag()
                } label: {
                    Image(systemName: "location")
                        .symbolVariant(cameraModel.shouldEmbedLocationData ? .fill : .slash.fill)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(
                            cameraModel.shouldEmbedLocationData ? .black : .white.opacity(0.7)
                        )
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(
                            cameraModel.shouldEmbedLocationData ? Color.yellow : Color.white.opacity(0.15)
                        )
                        .clipShape(.capsule)
                }
                
                // Flash toggle
                Button {
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
                    .foregroundColor(
                        cameraModel.flashMode == .off || !cameraModel.supportsFlash
                        ? .white.opacity(0.7)
                        : .black
                    )
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        cameraModel.flashMode == .off || !cameraModel.supportsFlash
                        ? Color.white.opacity(0.15)
                        : Color.yellow
                    )
                    .clipShape(.capsule)
                }
                .opacity(cameraModel.isFlashControlEnabled ? 1.0 : 0.45)
                .disabled(!cameraModel.isFlashControlEnabled)
                
                // Resolution picker
                HStack(spacing: 0) {
                    ForEach(cameraModel.availableResolutions) { opt in
                        let isSelected = cameraModel.selectedResolution?.id == opt.id
                        Button {
                            withAnimation(.spring(.bouncy)) {
                                cameraModel.selectResolution(opt)
                            }
                        } label: {
                            Text(opt.label)
                                .font(.system(size: 11, weight: .medium))
                                .fontWidth(.expanded)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(isSelected ? Color.yellow : Color.white.opacity(0.15))
                                .foregroundColor(isSelected ? .black : .white)
                        }
                    }
                }
                .clipShape(.rect(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.2), lineWidth: 1))
                
                // Format picker
                HStack(spacing: 0) {
                    ForEach(cameraModel.availableFormats) { mode in
                        Button {
                            withAnimation(.spring(.bouncy)) {
                                cameraModel.captureMode = mode
                            }
                        } label: {
                            Text(mode.rawValue)
                                .font(.system(size: 11, weight: .medium))
                                .fontWidth(.expanded)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(
                                    cameraModel.captureMode == mode
                                    ? Color.yellow
                                    : Color.white.opacity(0.15)
                                )
                                .foregroundColor(
                                    cameraModel.captureMode == mode ? .black : .white
                                )
                        }
                    }
                }
                .opacity(cameraModel.isFormatPickerEnabled ? 1.0 : 0.45)
                .disabled(!cameraModel.isFormatPickerEnabled)
                .clipShape(.rect(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.2), lineWidth: 1))
            }
            .padding(.horizontal, 8)
        }
    }
}
