import LockedCameraCapture
import SwiftUI

// MARK: - LockedCaptureView
struct LockedCaptureView: View {
    let lockedSession: LockedCameraCaptureSession
    
    @State private var cameraModel = LockedCameraModel()
    @State private var selectedControl: ManualControl?
    
    var body: some View {
        GeometryReader { geo in
            let previewRect = makePreviewRect(in: geo)
            
            ZStack {
                Color.black.ignoresSafeArea()
                
                // MARK: - Viewfinder
                CameraPreviewView(session: cameraModel.session) {
                    cameraModel.capturePhoto {
                        withAnimation { cameraModel.changeCapturingState(to: true) }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            withAnimation { cameraModel.changeCapturingState(to: false) }
                        }
                    }
                }
                .ignoresSafeArea()
                .contentShape(.rect.path(in: previewRect))
                
                // MARK: - UI Overlays
                VStack(spacing: 0) {
                    LockedTopBarView(cameraModel: cameraModel, selectedControl: $selectedControl)
                    
                    Spacer()
                    
                    if let selectedControl {
                        LockedManualControlsView(cameraModel: cameraModel, control: selectedControl)
                            .padding(.bottom, 8)
                    }
                    
                    LockedLensSelectorView(cameraModel: cameraModel)
                        .padding(.bottom, 30)
                    
                    LockedBottomBarView(cameraModel: cameraModel, lockedSession: lockedSession)
                        .padding(.bottom, 30)
                }
                
                // MARK: - Capture flash
                if cameraModel.isCapturing {
                    Color.white.opacity(0.3)
                        .frame(width: previewRect.width, height: previewRect.height)
                        .position(x: previewRect.midX, y: previewRect.midY)
                        .animation(.easeOut(duration: 0.15), value: cameraModel.isCapturing)
                }
            }
        }
        .environment(\.scenePhase, .active)
        .onAppear {
            cameraModel.configure(with: lockedSession)
        }
        .alert("Error", isPresented: $cameraModel.showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(cameraModel.errorMessage)
        }
    }
    
    private func makePreviewRect(in geo: GeometryProxy) -> CGRect {
        let size = geo.size
        let topInset = geo.safeAreaInsets.top
        let botInset = geo.safeAreaInsets.bottom
        let xHeight = (topInset - botInset) / 2
        let aspect = cameraModel.captureAspectRatio
        let previewW: CGFloat = aspect < size.width / size.height ? size.height * aspect : size.width
        let previewH: CGFloat = aspect < size.width / size.height ? size.height : size.width / aspect
        let previewX = (size.width - previewW) / 2
        let previewY = (size.height - previewH) / 2
        return CGRect(x: previewX, y: previewY - xHeight, width: previewW, height: previewH)
    }
}
