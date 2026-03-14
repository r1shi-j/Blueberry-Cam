import SwiftUI

struct ContentView: View {
    @Binding var shutterCount: Int
    @State private var cameraModel = CameraModel()
    @State private var levelModel  = LevelMotionModel()
    @State private var count = 0
    @State private var selectedControl: ManualControl?
    
    var body: some View {
        GeometryReader { geo in
            let previewRect = makePreviewRect(in: geo)
            
            ZStack {
                Color.black.ignoresSafeArea()
                
                // MARK: - Viewfinder (resizeAspect — matches exact capture FOV)
                CameraPreviewView(session: cameraModel.session) {
                    cameraModel.capturePhoto()
                }
                .ignoresSafeArea()
                .contentShape(.rect.path(in: previewRect))
                .onTapGesture(count: 2) {
                    withAnimation(.bouncy) {
                        let target: Lens = cameraModel.activeLens.isFront ? .wide : .front
                        cameraModel.switchLens(to: target)
                    }
                    count += 1
                }
                .sensoryFeedback(.selection, trigger: count)
                
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
                        TopBarView(cameraModel: cameraModel, selectedControl: $selectedControl)
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
                        if let selectedControl {
                            ManualControlsView(cameraModel: cameraModel, control: selectedControl)
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
                    Color.white.opacity(0.3)
                        .frame(width: previewRect.width, height: previewRect.height)
                        .position(x: previewRect.midX, y: previewRect.midY)
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
