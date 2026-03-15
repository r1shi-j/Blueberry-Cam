import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Binding var shutterCount: Int
    @State private var cameraModel = CameraModel()
    @State private var levelModel  = LevelMotionModel()
    @State private var selectedControl: ManualControl?
    @State private var hapticTrigger = 0
    
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
                    
                    // MARK: - Level / Horizon overlay
                    LevelOverlayView(model: levelModel)
                        .ignoresSafeArea()
                }
                
                // MARK: - UI Overlays
                VStack(spacing: 0) {
                    if !cameraModel.showSimpleView {
                        TopBarView(cameraModel: cameraModel, selectedControl: $selectedControl)
                        
                        Spacer()
                        
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
                            .padding(.bottom, 8)
                            .onTapGesture {
                                hapticTrigger += 1
                                cameraModel.cycleHistogramMode()
                            }
                        }
                        
                        if let selectedControl {
                            ManualControlsView(cameraModel: cameraModel, control: selectedControl)
                                .padding(.bottom, 8)
                        }
                        
                        LensSelectorView(cameraModel: cameraModel)
                            .padding(.bottom, 20)
                    } else {
                        Spacer()
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
            if !cameraModel.showSimpleView {
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
        .sensoryFeedback(.impact, trigger: hapticTrigger)
        .fullScreenCover(isPresented: Binding(get: {
            cameraModel.appView == .settings
        }, set: { _, _ in
            cameraModel.appView = .standard
        })) {
            SettingsPlaceholderView(cameraModel: cameraModel)
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

struct SettingsPlaceholderView: View {
    let cameraModel: CameraModel
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                Section("Information") {
                    Text("Settings are currently under development.")
                    Text("Blueberry Cam v1.0")
                }
                
                Section("Help") {
                    Text("Dismissing this sheet will re-enable Camera Control.")
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
