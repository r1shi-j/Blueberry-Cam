import SwiftUI

extension CameraModel {
    fileprivate var shutterTint: Color {
        captureMode == .raw ? .blue.mix(with: .mint, by: 0.5).opacity(0.4) : .white.opacity(0.2)
    }
}

extension BottomBarView {
    private var photosLinkSymbolName: String {
        "photo.on.rectangle.angled.fill"
    }
    
    private func openPhotosApp() {
        guard let url = URL(string: "photos-redirect://") else { return }
        UIApplication.shared.open(url)
    }
}

struct BottomBarView: View {
    @Bindable var cameraModel: CameraModel
    @Binding var shutterCount: Int
    
    var body: some View {
        VStack() {
            HStack(alignment: .center, spacing: 0) {
                // MARK: - Photos app shortcut
                if !cameraModel.showSimpleView {
                    Button(action: openPhotosApp) {
                        Image(systemName: photosLinkSymbolName)
                            .font(.system(size: 20))
                            .symbolRenderingMode(.hierarchical)
                            .tint(.primary)
                            .padding()
                            .clipShape(.circle)
                            .glassEffect(.regular.interactive().tint(.black.mix(with: .white, by: 0.2)), in: .circle)
                    }
                    .frame(height: 82)
                    .frame(maxWidth: .infinity)
                    .overlay {
                        Text(String(shutterCount))
                            .font(.caption)
                            .fontWidth(.expanded)
                            .foregroundColor(.white.opacity(0.6))
                            .offset(y: 41)
                    }
                }
                
                // MARK: - Shutter button
                ZStack {
                    Circle()
                        .frame(width: 82, height: 82)
                        .glassEffect(.regular.tint(cameraModel.shutterTint).interactive())
                    Button {
                        cameraModel.capturePhoto()
                        shutterCount += 1
                    } label: {
                        Circle()
                            .fill(.white)
                            .frame(width: 69, height: 69)
                    }
                    .glassEffect(.regular.interactive())
                    .sensoryFeedback(.selection, trigger: shutterCount)
                }
                .frame(maxWidth: .infinity)
                
                // MARK: - Manual controls toggle
                if !cameraModel.showSimpleView {
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
}
