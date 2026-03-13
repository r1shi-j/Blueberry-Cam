import SwiftUI

struct ContentView: View {
    @State private var cameraModel = CameraModel()
    @State private var levelModel  = LevelMotionModel()
    @AppStorage("shutterCount") private var shutterCount = 0
    @State private var count = 0
    
    var body: some View {
        GeometryReader { geo in
            let previewRect = makePreviewRect(in: geo.size)
            
            ZStack {
                Color.black.ignoresSafeArea()
                
                // MARK: - Viewfinder (resizeAspect — matches exact capture FOV)
                CameraPreviewView(session: cameraModel.session) {
                    cameraModel.capturePhoto()
                }
                .onTapGesture(count: 2) {
                    withAnimation(.bouncy) {
                        let target: Lens = cameraModel.activeLens.isFront ? .wide : .front
                        cameraModel.switchLens(to: target)
                    }
                    count += 1
                }
                .sensoryFeedback(.selection, trigger: count)
                .ignoresSafeArea()
                
                if !cameraModel.isCleanUI {
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
                }
                
                // MARK: - Crop frame overlay
                if !cameraModel.isCleanUI {
                    CropOverlayView(aspectRatio: cameraModel.captureAspectRatio)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                }
                
                // MARK: - Level / Horizon overlay
                if !cameraModel.isCleanUI {
                    LevelOverlayView(model: levelModel)
                        .ignoresSafeArea()
                }
                
                // MARK: - UI Overlays
                VStack(spacing: 0) {
                    if !cameraModel.isCleanUI {
                        TopBarView(cameraModel: cameraModel)
                    }
                    Spacer()
                    
                    if !cameraModel.isCleanUI {
                        if cameraModel.showHistogram && cameraModel.histogramSize == .large {
                            HistogramView(
                                mode: cameraModel.histogramMode,
                                size: cameraModel.histogramSize,
                                lumaData: cameraModel.histogramData,
                                redData: cameraModel.redHistogram,
                                greenData: cameraModel.greenHistogram,
                                blueData: cameraModel.blueHistogram,
                                waveformData: cameraModel.waveformData
                            )
                            .frame(height: 60)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 32)
                            .onTapGesture {
                                cameraModel.cycleHistogramMode()
                            }
                        }
                    }
                    
                    if !cameraModel.isCleanUI {
                        if cameraModel.showManualControls {
                            ManualControlsView(cameraModel: cameraModel)
                                .padding(.bottom, 8)
                        }
                    }
                    
                    if !cameraModel.isCleanUI {
                        LensSelectorView(cameraModel: cameraModel)
                            .padding(.bottom, 30)
                    }
                    
                    BottomBarView(cameraModel: cameraModel, shutterCount: $shutterCount)
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
        .safeAreaInset(edge: .top) {
            if !cameraModel.isCleanUI {
                StatusBarAreaView(cameraModel: cameraModel)
                    .padding()
                    .ignoresSafeArea()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: .zero)
            }
        }
        .statusBarHidden()
        .onAppear {
            cameraModel.configure()
            levelModel.startUpdates()
        }
        .onDisappear {
            levelModel.stopUpdates()
        }
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
