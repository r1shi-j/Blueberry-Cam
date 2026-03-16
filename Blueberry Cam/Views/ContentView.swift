import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Binding var shutterCount: Int
    @State private var cameraModel = CameraModel()
    @State private var levelModel  = LevelMotionModel()
    @State private var selectedControl: ManualControl?
    @State private var hapticTrigger = 0
    @State private var hapticTriggerR = 0
    
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
                    hapticTrigger += 1
                    withAnimation(.bouncy) {
                        cameraModel.toggleSelfie()
                    }
                }
                
                // MARK: - Peaking/Clipping overlays
                if !cameraModel.showSimpleView {
                    if cameraModel.showZebraStripes {
                        AnalysisOverlayView(
                            mask: cameraModel.zebraMask,
                            gridSize: cameraModel.analysisGridSize,
                            style: .zebra
                        )
                        .frame(width: previewRect.width, height: previewRect.height)
                        .position(x: previewRect.midX, y: previewRect.midY)
                    }
                    
                    if !cameraModel.isAutoFocus {
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
                    if cameraModel.shouldShowGrid {
                        CropOverlayView(aspectRatio: cameraModel.captureAspectRatio)
                            .ignoresSafeArea()
                            .allowsHitTesting(false)
                    }
                    
                    // MARK: - Level / Horizon overlay
                    if cameraModel.shouldShowLevel {
                        LevelOverlayView(model: levelModel)
                            .ignoresSafeArea()
                    }
                }
                
                // MARK: - UI Overlays
                VStack(spacing: 0) {
                    if !cameraModel.showSimpleView {
                        TopBarView(cameraModel: cameraModel, selectedControl: $selectedControl)
                        
                        Spacer()
                        
                        if cameraModel.histogramModeLarge != .none {
                            HistogramView(
                                mode: cameraModel.histogramModeLarge,
                                size: .large,
                                lumaData: cameraModel.histogramData,
                                redData: cameraModel.redHistogram,
                                greenData: cameraModel.greenHistogram,
                                blueData: cameraModel.blueHistogram,
                                waveformData: cameraModel.waveformData
                            )
                            .frame(height: 60)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 8)
                            .onTapGesture {
                                hapticTrigger += 1
                                cameraModel.cycleHistogramMode(mode: &cameraModel.histogramModeLarge)
                            }
                            .onLongPressGesture {
                                hapticTriggerR += 1
                                cameraModel.hideHistogram(for: .large)
                            }
                        }
                        
                        if let selectedControl {
                            ManualControlsView(cameraModel: cameraModel, control: selectedControl)
                                .padding(.bottom, 8)
                        }
                        
                        LensSelectorView(cameraModel: cameraModel)
                            .padding(.bottom, 30)
                    } else {
                        Spacer()
                    }
                    
                    BottomBarView(cameraModel: cameraModel, shutterCount: $shutterCount)
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
        .safeAreaInset(edge: .top) {
            if !cameraModel.showSimpleView {
                StatusBarAreaView(cameraModel: cameraModel)
                    .padding()
                    .ignoresSafeArea()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: .zero)
            } else {
                Color.clear
                    .padding()
                    .ignoresSafeArea()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: .zero)
            }
        }
        .statusBarHidden()
        .sensoryFeedback(.impact, trigger: hapticTrigger)
        .sensoryFeedback(.impact(flexibility: .soft), trigger: hapticTriggerR)
        .onAppear {
            cameraModel.configure()
            levelModel.startUpdates()
        }
        .onDisappear {
            levelModel.stopUpdates()
        }
        .onChange(of: cameraModel.shouldShowLevel) { _, new in
            if new {
                levelModel.startUpdates()
            } else {
                levelModel.stopUpdates()
            }
        }
        .onChange(of: cameraModel.appView) { _, new in
            if new == AppView.standard {
                levelModel.startUpdates()
            } else {
                levelModel.stopUpdates()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                levelModel.startUpdates()
            } else {
                levelModel.stopUpdates()
            }
        }
        .alert("Error", isPresented: $cameraModel.showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(cameraModel.errorMessage)
        }
        .fullScreenCover(isPresented: Binding(get: {
            cameraModel.appView == .settings
        }, set: { _, _ in
            cameraModel.hideSettings()
        })) {
            SettingsView(cameraModel: cameraModel)
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
