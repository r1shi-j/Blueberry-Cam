import SwiftUI
import AVFoundation

struct TopBarView: View {
    @Bindable var cameraModel: CameraModel
    
    var body: some View {
        VStack(spacing: 20) {
            HStack(alignment: .center, spacing: 30) {
                // Live EXIF
                // long press or double tap resets and enables auto
                // one tap opens slider and disables auto
                Text(String(format: "EV %+.1f", cameraModel.exposureBias))
                    .foregroundColor(.yellow.opacity(0.8))
                Text("ISO \(Int(cameraModel.liveISO))")
                    .foregroundColor(.yellow)
                Text(cameraModel.liveShutter)
                    .foregroundColor(.white.opacity(0.8))
                Text(cameraModel.liveFocus)
                    .foregroundColor(.green.opacity(0.8))
                Text(cameraModel.liveWB)
                    .foregroundColor(.cyan)
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
