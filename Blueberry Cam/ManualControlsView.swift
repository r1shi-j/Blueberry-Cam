import SwiftUI
import CoreMedia

struct ManualControlsView: View {
    @ObservedObject var cameraModel: CameraModel
    
    var body: some View {
        VStack(spacing: 12) {
            // Auto / Manual toggle
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
                        else { cameraModel.applyManualExposure() }
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
                        ) { editing in
                            if !editing { cameraModel.applyManualExposure() }
                        }
                        .tint(.yellow)
                        Text("\(Int(cameraModel.iso))")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundColor(.yellow)
                            .frame(width: 50, alignment: .trailing)
                    }
                }
                .padding(.horizontal, 20)
                
                // Shutter Speed
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
                                set: { cameraModel.shutterIndex = Int($0) }
                            ),
                            in: 0...Double(cameraModel.shutterSpeeds.count - 1),
                            step: 1
                        ) { editing in
                            if !editing { cameraModel.applyManualExposure() }
                        }
                        .tint(.yellow)
                        Text(shutterLabel)
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundColor(.yellow)
                            .frame(width: 50, alignment: .trailing)
                    }
                }
                .padding(.horizontal, 20)
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
        guard !cameraModel.shutterSpeeds.isEmpty else { return "--" }
        let t = cameraModel.shutterSpeeds[cameraModel.shutterIndex]
        return cameraModel.formatShutter(t)
    }
}
