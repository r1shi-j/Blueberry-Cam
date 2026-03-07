import SwiftUI

struct ContentView: View {
    @StateObject private var cameraModel = CameraModel()
    @State private var showSettings = false
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            // MARK: - Viewfinder
            CameraPreviewView(session: cameraModel.session)
                .ignoresSafeArea()
            
            // MARK: - Overlays
            VStack(spacing: 0) {
                
                // Top bar
                TopBarView(cameraModel: cameraModel)
                
                Spacer()
                
                // Histogram
                if cameraModel.showHistogram {
                    HistogramView(data: cameraModel.histogramData)
                        .frame(height: 60)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 8)
                }
                
                // Manual controls
                if cameraModel.showManualControls {
                    ManualControlsView(cameraModel: cameraModel)
                        .padding(.bottom, 8)
                }
                
                // Bottom controls
                BottomBarView(cameraModel: cameraModel)
                    .padding(.bottom, 30)
            }
            
            // Capture flash overlay
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
