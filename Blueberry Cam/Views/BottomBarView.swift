import SwiftUI

struct BottomBarView: View {
    @Bindable var cameraModel: CameraModel
    @Binding var shutterCount: Int
    
    var body: some View {
        VStack() {
            HStack(alignment: .center, spacing: 0) {
                // Photos app link
                if !cameraModel.isCleanUI {
                    Button {
                        openPhotosApp()
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: "photo.on.rectangle.angled.fill")
                                .font(.system(size: 20))
                                .symbolRenderingMode(.hierarchical)
                                .tint(.primary)
                                .padding()
                                .clipShape(.circle)
                                .glassEffect(.regular.interactive().tint(.black.mix(with: .white, by: 0.2)), in: .circle)
                            Text(String(shutterCount))
                                .font(.caption)
                                .fontWidth(.expanded)
                                .foregroundColor(.white.opacity(0.6))
                        }
                        .padding(.top)
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
                        shutterCount += 1
                    } label: {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 69, height: 69)
                    }
                    .glassEffect(.regular.interactive())
                    .sensoryFeedback(.selection, trigger: shutterCount)
                }
                .frame(maxWidth: .infinity)
                
                // Manual controls toggle
                if !cameraModel.isCleanUI {
                    Button {
                        
                    } label: {
                        Image(systemName: "applelogo")
                            .font(.system(size: 20))
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .frame(maxWidth: .infinity)
                    .disabled(true)
                }
            }
        }
    }
    
    private func openPhotosApp() {
        guard let url = URL(string: "photos-redirect://") else { return }
        UIApplication.shared.open(url)
    }
}
