import SwiftUI
import CoreMedia

struct TopBarView: View {
    @Bindable var cameraModel: CameraModel
    
    var body: some View {
        VStack {
            HStack(alignment: .center) {
                // Live EXIF
                VStack(alignment: .leading, spacing: 2) {
                    Text("ISO \(Int(cameraModel.liveISO))")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(.yellow)
                    Text(cameraModel.liveShutter)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(.white.opacity(0.8))
                }
                .padding(.leading, 16)
                
                Spacer()
                
                HStack(spacing: 8) {
                    // Resolution picker — only shown when 2+ options
                    HStack(spacing: 0) {
                        ForEach(cameraModel.availableResolutions) { opt in
                            let isSelected = cameraModel.selectedResolution?.id == opt.id
                            Button {
                                cameraModel.selectResolution(opt)
                            } label: {
                                Text(opt.label)
                                    .font(.system(size: 11, weight: .bold))
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(isSelected ? Color.yellow : Color.white.opacity(0.15))
                                    .foregroundColor(isSelected ? .black : .white)
                            }
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.2), lineWidth: 1))
                    
                    // Format picker
                    HStack(spacing: 0) {
                        ForEach(cameraModel.availableFormats) { mode in
                            Button {
                                cameraModel.captureMode = mode
                            } label: {
                                Text(mode.rawValue)
                                    .font(.system(size: 11, weight: .bold))
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
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.white.opacity(0.2), lineWidth: 1))
                }
                
                Spacer()
                
                VStack {
                    // Histogram toggle
                    Button {
                        cameraModel.toggleHistogram()
                    } label: {
                        Image(systemName: "chart.bar.fill")
                            .font(.system(size: 16))
                            .foregroundColor(cameraModel.showHistogram ? .yellow : .white.opacity(0.5))
                    }
                }
                .padding(.trailing, 16)
            }
            HStack(alignment: .center, spacing: 12) {
                // Zebra toggle
                Button {
                    cameraModel.toggleZebraStripes()
                } label: {
                    Text("Z")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(cameraModel.showZebraStripes ? .black : .white.opacity(0.7))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(cameraModel.showZebraStripes ? Color.yellow : Color.white.opacity(0.15))
                        .clipShape(Capsule())
                }
                
                // Focus peaking toggle
                Button {
                    cameraModel.toggleFocusPeaking()
                } label: {
                    Text("P")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(cameraModel.showFocusPeaking ? .black : .white.opacity(0.7))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(cameraModel.showFocusPeaking ? Color.yellow : Color.white.opacity(0.15))
                        .clipShape(Capsule())
                }
            }
        }
        .padding(.top, 56)
        .padding(.bottom, 12)
        .background(
            LinearGradient(
                colors: [.black.opacity(0.7), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
}
