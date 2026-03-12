import SwiftUI
import UIKit

struct BottomBarView: View {
    @Bindable var cameraModel: CameraModel
    @State private var count = 0
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 0) {
                if !cameraModel.isCleanUI {
                    // Manual controls toggle
                    Button {
                        withAnimation(.spring(response: 0.3)) {
                            cameraModel.toggleManualControls()
                        }
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: "slider.horizontal.3")
                                .font(.system(size: 20))
                                .foregroundColor(cameraModel.showManualControls ? .yellow : .white)
                            Text("MANUAL")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(cameraModel.showManualControls ? .yellow : .white.opacity(0.6))
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                // Shutter button
                ZStack {
                    Circle()
                        .frame(width: 82, height: 82)
                        .glassEffect(.regular.tint(cameraModel.captureMode == .raw ? .blue.mix(with: .mint, by: 0.5).opacity(0.4) : .white.opacity(0.2)).interactive())
                    Button {
                        cameraModel.capturePhoto()
                        count += 1
                    } label: {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 69, height: 69)
                    }
                    .glassEffect(.regular.interactive())
                    .sensoryFeedback(.selection, trigger: count)
                }
                .frame(maxWidth: .infinity)
                
                if !cameraModel.isCleanUI {
                    // Placeholder right side
                    Button {
                        openPhotosApp()
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: "photo.on.rectangle")
                                .font(.system(size: 20))
                                .foregroundColor(.white.opacity(0.8))
                            Text("GALLERY")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .background(
            LinearGradient(
                colors: [.clear, .black.opacity(0.75)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
    
    private func openPhotosApp() {
        guard let url = URL(string: "photos-redirect://") else { return }
        UIApplication.shared.open(url)
    }
}
