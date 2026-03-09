import SwiftUI
import UIKit

struct BottomBarView: View {
    @Bindable var cameraModel: CameraModel
    
    var body: some View {
        VStack(spacing: 0) {
            // Divider
            Rectangle()
                .fill(Color.white.opacity(0.1))
                .frame(height: 1)
                .padding(.bottom, 24)
            
            HStack(alignment: .center, spacing: 0) {
                
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
                
                // Shutter button
                Button {
                    cameraModel.capturePhoto()
                } label: {
                    ZStack {
                        Circle()
                            .stroke(Color.white, lineWidth: 3)
                            .frame(width: 76, height: 76)
                        Circle()
                            .fill(Color.white)
                            .frame(width: 62, height: 62)
                        
                        // RAW indicator ring
                        if cameraModel.captureMode != .jpeg {
                            Circle()
                                .stroke(Color.yellow, lineWidth: 2)
                                .frame(width: 70, height: 70)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                
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
