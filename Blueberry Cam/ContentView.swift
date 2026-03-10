import SwiftUI

struct ContentView: View {
    @State private var cameraModel = CameraModel()
    
    var body: some View {
        GeometryReader { geo in
            let previewRect = makePreviewRect(in: geo.size)
            
            ZStack {
                Color.black.ignoresSafeArea()
                
                // MARK: - Viewfinder (resizeAspect — matches exact capture FOV)
                CameraPreviewView(session: cameraModel.session)
                    .ignoresSafeArea()
                
                if cameraModel.showZebraStripes {
                    AnalysisOverlayView(
                        mask: cameraModel.zebraMask,
                        gridSize: cameraModel.analysisGridSize,
                        style: .zebra
                    )
                    .frame(width: previewRect.width, height: previewRect.height)
                    .position(x: previewRect.midX, y: previewRect.midY)
                }
                
                if cameraModel.shouldShowFocusPeakingOverlay {
                    AnalysisOverlayView(
                        mask: cameraModel.focusPeakingMask,
                        gridSize: cameraModel.analysisGridSize,
                        style: .focusPeaking
                    )
                    .frame(width: previewRect.width, height: previewRect.height)
                    .position(x: previewRect.midX, y: previewRect.midY)
                }
                
                if cameraModel.showClipping {
                    AnalysisOverlayView(
                        mask: cameraModel.clippingMask,
                        gridSize: cameraModel.analysisGridSize,
                        style: .clipping
                    )
                    .frame(width: previewRect.width, height: previewRect.height)
                    .position(x: previewRect.midX, y: previewRect.midY)
                }
                
                // MARK: - Crop frame overlay
                CropOverlayView(aspectRatio: cameraModel.captureAspectRatio)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                
                // MARK: - UI Overlays
                VStack(spacing: 0) {
                    TopBarView(cameraModel: cameraModel)
                    Spacer()
                    
                    if cameraModel.showHistogram {
                        HistogramView(
                            mode: cameraModel.histogramMode,
                            lumaData: cameraModel.histogramData,
                            redData: cameraModel.redHistogram,
                            greenData: cameraModel.greenHistogram,
                            blueData: cameraModel.blueHistogram,
                            waveformData: cameraModel.waveformData,
                            waveformCols: cameraModel.waveformCols,
                            waveformRows: cameraModel.waveformRows
                        )
                        .frame(height: 60)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 8)
                        .onTapGesture {
                            cameraModel.cycleHistogramMode()
                        }
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
        }
        .onAppear { cameraModel.configure() }
//        .alert("Saved", isPresented: $cameraModel.showSaveAlert) {
//            Button("OK", role: .cancel) {}
//        } message: {
//            Text(cameraModel.saveMessage)
//        }
        .alert("Error", isPresented: $cameraModel.showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(cameraModel.errorMessage)
        }
    }
    
    private func makePreviewRect(in size: CGSize) -> CGRect {
        let screenW = size.width
        let screenH = size.height
        let screenAspect = screenW / screenH
        let aspect = cameraModel.captureAspectRatio
        let previewW: CGFloat = aspect < screenAspect ? screenH * aspect : screenW
        let previewH: CGFloat = aspect < screenAspect ? screenH : screenW / aspect
        let previewX = (screenW - previewW) / 2
        let previewY = (screenH - previewH) / 2
        return CGRect(x: previewX, y: previewY, width: previewW, height: previewH)
    }
}
