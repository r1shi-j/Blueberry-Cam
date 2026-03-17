import LockedCameraCapture
import SwiftUI

extension LockedCameraModel {
    fileprivate var shutterTint: Color {
        captureMode == .raw ? .blue.mix(with: .mint, by: 0.5).opacity(0.4) : .white.opacity(0.2)
    }
}

extension LockedBottomBarView {
    private var mainAppLinkSymbolName: String {
        "camera.blueberry"
    }
    
    private var openString: String {
        "Open"
    }
    
    private func openMainApp() {
        Task {
            let activity = NSUserActivity(activityType: "com.jansari.rishi.Blueberry-Cam.opencamera")
            try? await lockedSession.openApplication(for: activity)
        }
    }
}

struct LockedBottomBarView: View {
    @Bindable var cameraModel: LockedCameraModel
    let lockedSession: LockedCameraCaptureSession
    @State private var hapticTrigger = 0
    
    var body: some View {
        VStack() {
            HStack(alignment: .center, spacing: 0) {
                // MARK: - Main app shortcut
                Button(action: openMainApp) {
                    Image(systemName: mainAppLinkSymbolName)
                        .font(.system(size: 20))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.black, .blue, .green)
                        .padding()
                        .clipShape(.circle)
                        .glassEffect(.regular.interactive().tint(.white.mix(with: .teal, by: 0.4)), in: .circle)
                }
                .frame(height: 82)
                .frame(maxWidth: .infinity)
                .overlay {
                    Text(openString.uppercased())
                        .font(.caption)
                        .fontWidth(.expanded)
                        .foregroundColor(.white.opacity(0.6))
                        .offset(y: 41)
                }
                
                // MARK: - Shutter button
                ZStack {
                    Circle()
                        .frame(width: 82, height: 82)
                        .glassEffect(.regular.tint(cameraModel.shutterTint).interactive())
                    Button {
                        cameraModel.capturePhoto()
                        hapticTrigger += 1
                    } label: {
                        Circle()
                            .fill(.white)
                            .frame(width: 69, height: 69)
                    }
                    .glassEffect(.regular.interactive())
                    .sensoryFeedback(.selection, trigger: hapticTrigger)
                }
                .frame(maxWidth: .infinity)
                
                // MARK: - Placeholder
                Button {
                    
                } label: {
                    Image(systemName: "applelogo")
                        .font(.system(size: 20))
                        .foregroundColor(.white.opacity(0.8))
                }
                .frame(height: 82)
                .frame(maxWidth: .infinity)
                .disabled(true)
            }
        }
    }
}
