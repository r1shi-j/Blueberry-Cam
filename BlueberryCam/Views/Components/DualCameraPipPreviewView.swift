import SwiftUI

struct DualCameraPipPreviewView: View {
    @Bindable var cameraModel: CameraModel
    @State private var dragTranslation: CGSize = .zero
    
    private var cornerRadius: CGFloat { 28 }
    private var rimWidth: CGFloat { 0.8 }
    private var innerCornerRadius: CGFloat { cornerRadius - rimWidth }
    
    var body: some View {
        if !cameraModel.isDetachingPreviewForReconfiguration,
           let pipDeviceUniqueID = cameraModel.pipPreviewDeviceUniqueID {
            pipPreview(pipDeviceUniqueID)
                .transition(.scale(scale: 0.85).combined(with: .opacity))
        }
    }
    
    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 16)
            .onChanged { value in
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    dragTranslation = value.translation
                }
            }
            .onEnded { value in
                withAnimation(Animations.pipSnap) {
                    cameraModel.moveDualCameraPip(
                        by: value.translation,
                        predictedTranslation: value.predictedEndTranslation
                    )
                    dragTranslation = .zero
                }
            }
    }
    
    @ViewBuilder
    private func pipPreview(_ pipDeviceUniqueID: String) -> some View {
        CameraPreviewView(
            session: cameraModel.previewSession,
            onCapture: {},
            proxy: PreviewViewProxy(),
            deviceUniqueID: pipDeviceUniqueID,
            rotationAngle: cameraModel.pipPreviewRotationAngle,
            isMirrored: cameraModel.isPipPreviewMirrored,
            handlesCaptureEvents: false
        )
        .clipShape(.rect(cornerRadius: innerCornerRadius))
        .padding(rimWidth)
        .background {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Color(red: 0.30, green: 0.28, blue: 0.24).opacity(0.16))
                .glassEffect(
                    .regular.tint(Color(red: 0.36, green: 0.34, blue: 0.30).opacity(0.24)),
                    in: .rect(cornerRadius: cornerRadius)
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            .white.opacity(0.22),
                            Color(red: 0.48, green: 0.45, blue: 0.39).opacity(0.46),
                            Color(red: 0.10, green: 0.09, blue: 0.08).opacity(0.28)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.4
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(Color(red: 0.08, green: 0.07, blue: 0.06).opacity(0.16), lineWidth: 0.25)
                .blendMode(.multiply)
        }
        .aspectRatio(cameraModel.dualCameraPipAspectRatio, contentMode: .fit)
        .offset(dragTranslation)
        .scaleEffect(dragTranslation == .zero ? 1 : 1.025)
        .shadow(color: .black.opacity(0.30), radius: 12, x: 0, y: 4)
        .contentShape(.rect(cornerRadius: cornerRadius))
        .accessibilityHidden(true)
        .gesture(moveGesture)
    }
}
