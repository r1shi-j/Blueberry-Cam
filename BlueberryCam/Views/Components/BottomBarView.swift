import SwiftUI
import UIKit

extension CameraModel {
    fileprivate var shutterTint: Color {
        captureMode == .raw ? Color.blue.opacity(0.4) : Color.white.opacity(0.2)
    }
}

extension BottomBarView {
    private func openPhotosApp() {
        guard let url = URL(string: "photos-redirect://") else { return }
        UIApplication.shared.open(url)
    }
}

struct BottomBarView: View {
    @ObservedObject var cameraModel: CameraModel
    @Binding var shutterCount: Int
    
    var body: some View {
        VStack {
            HStack(alignment: .center, spacing: 0) {
                // MARK: - Photos app shortcut
                if !cameraModel.showSimpleView {
                    Button(action: openPhotosApp) {
                        Image(systemName: "photo.fill")
                            .font(.system(size: 18))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundColor(.white)
                            .padding()
                            .background(Color.white.opacity(0.15))
                            .clipShape(Circle())
                    }
                    .frame(height: 65)
                    .frame(maxWidth: .infinity)
                }
                
                // MARK: - Shutter button
                ZStack {
                    Circle()
                        .fill(cameraModel.shutterTint)
                        .frame(width: 65, height: 65)
                    Circle()
                        .stroke(Color.white.opacity(0.25), lineWidth: 2)
                        .frame(width: 65, height: 65)
                    Button {
                        cameraModel.capturePhoto {
                            withAnimation { cameraModel.changeCapturingState(to: true) }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                withAnimation { cameraModel.changeCapturingState(to: false) }
                            }
                        }
                        shutterCount += 1
                    } label: {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 55, height: 55)
                    }
                }
                .frame(maxWidth: .infinity)
                
                // MARK: - Placeholder
                if !cameraModel.showSimpleView {
                    Text(String(shutterCount))
                        .font(.caption)
                        .foregroundColor(Color.white.opacity(0.6))
                        .frame(height: 65)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }
}
