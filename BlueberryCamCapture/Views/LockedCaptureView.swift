import LockedCameraCapture
import SwiftUI

extension LockedCaptureView {
    private var errorString: String { "Error" }
    private var okButtonString: String { "OK" }
    
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

struct LockedCaptureView: View {
    let lockedSession: LockedCameraCaptureSession
    
    @State private var cameraModel = LockedCameraModel()
    @State private var selectedControl: ManualControl?
    
    // Transitions
    @State private var visualZoomScale: CGFloat = 1.0
    @State private var visualOpacity: CGFloat = 1.0
    
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
                .scaleEffect(visualZoomScale)
                .opacity(visualOpacity)
                .ignoresSafeArea()
                .contentShape(.rect.path(in: previewRect))
                
                // MARK: - UI Overlays
                VStack(spacing: 0) {
                    LockedTopBarView(cameraModel: cameraModel, selectedControl: $selectedControl)
                        .offset(y:-2)
                    
                    Spacer()
                    
                    if let selectedControl {
                        LockedManualControlsView(cameraModel: cameraModel, control: selectedControl)
                            .padding(.bottom, 8)
                    }
                    
                    ZStack {
                        LockedLensSelectorView(cameraModel: cameraModel)
                            .padding(.bottom, 30)
                    }
                    .animation(.bouncy, value: cameraModel.activeLens)
                    
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
        .onChange(of: cameraModel.activeLens) { oldLens, newLens in
            // Handle visual "zoom" bump to mask lens hardware switch
            if oldLens.isFront == newLens.isFront {
                // Handle visual "zoom" bump and opacity dip to mask lens hardware switch
                let oldVal = Double(oldLens.label) ?? 1.0
                let newVal = Double(newLens.label) ?? 1.0
                let isZoomIn = newVal > oldVal
                let targetScale: CGFloat = isZoomIn ? 1.05 : 0.95
                
                withAnimation(.easeIn(duration: 0.1)) {
                    visualZoomScale = targetScale
                    visualOpacity = 0.5
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    withAnimation(.easeOut(duration: 0.25)) {
                        visualZoomScale = 1.0
                        visualOpacity = 1.0
                    }
                }
            }
        }
        .alert(errorString, isPresented: $cameraModel.showError) {
            Button(okButtonString, role: .cancel) {}
        } message: {
            Text(cameraModel.errorMessage)
        }
    }
}
