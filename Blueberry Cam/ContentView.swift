import SwiftUI

struct ContentView: View {
    @StateObject private var cameraModel = CameraModel()
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            // MARK: - Viewfinder (resizeAspect — matches exact capture FOV)
            CameraPreviewView(session: cameraModel.session)
                .ignoresSafeArea()
            
            // MARK: - Crop frame overlay
            CropOverlayView(aspectRatio: cameraModel.captureAspectRatio)
                .ignoresSafeArea()
                .allowsHitTesting(false)
            
            // MARK: - UI Overlays
            VStack(spacing: 0) {
                TopBarView(cameraModel: cameraModel)
                Spacer()
                
                if cameraModel.showHistogram {
                    HistogramView(data: cameraModel.histogramData)
                        .frame(height: 60)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 8)
                }
                
                if cameraModel.showManualControls {
                    ManualControlsView(cameraModel: cameraModel)
                        .padding(.bottom, 8)
                }
                
                LensSelectorView(cameraModel: cameraModel)
                    .padding(.bottom, 8)
                
                BottomBarView(cameraModel: cameraModel)
                    .padding(.bottom, 30)
            }
            
            // Capture flash
            if cameraModel.isCapturing {
                Color.white
                    .ignoresSafeArea()
                    .opacity(0.3)
                    .animation(.easeOut(duration: 0.15), value: cameraModel.isCapturing)
            }
        }
        .onAppear { cameraModel.configure() }
        .alert("Saved", isPresented: $cameraModel.showSaveAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(cameraModel.saveMessage)
        }
        .alert("Error", isPresented: $cameraModel.showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(cameraModel.errorMessage)
        }
    }
}
