import SwiftUI

extension CameraModel {
    fileprivate func resetURL() {
        detectedCodeURL = nil
        detectedCodeString = nil
    }
    
    fileprivate func ignoreCurrentCode() {
        if let code = detectedCodeString {
            ignoredCodes[code] = Date()
        }
        resetURL()
    }
    
    fileprivate func clearIgnoredCodes() {
        ignoredCodes.removeAll()
    }
}

extension CaptureView {
    private var copiedString: String { "Copied to clipboard!" }
    private var closeLinkTitle: String { "Close" }
    private var closeSymbolName: String { "xmark.square" }
    private var linkSymbolName: String { "link" }
    private var backupURLName: String { "Open Link" }
    private var lensCleaningTitle: String { "You lens may need cleaning" }
    private var closeCleaningTitle: String { "Done" }
    private var lensCleaningSymbolName: String { "camera.aperture" }
    private var errorString: String { "Error" }
    private var okButtonString: String { "OK" }
    
    private func changeLevelMonitoring(_ condition: Bool) {
        if condition {
            levelModel.startUpdates()
        } else {
            levelModel.stopUpdates()
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

struct CaptureView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Binding var shutterCount: Int
    @State private var cameraModel = CameraModel()
    @State private var levelModel  = LevelMotionModel()
    @State private var selectedControl: ManualControl?
    @State private var hapticTrigger = 0
    @State private var hapticTriggerR = 0
    
    // Transitions
    @State private var visualZoomScale: CGFloat = 1.0
    @State private var visualBlur: CGFloat = 0
    @State private var visualOpacity: CGFloat = 1.0
    @State private var isAwaitingFacingFlipCompletion = false
    @State private var isAwaitingSameFacingLensCompletion = false
    @State private var pendingFacingFlipRotation: Double = 0
    
    var body: some View {
        GeometryReader { geo in
            let previewRect = makePreviewRect(in: geo)
            
            ZStack {
                Color.black.ignoresSafeArea()
                
                // MARK: - Camera Overlays
                ZStack {
                    // MARK: - Viewfinder
                    CameraPreviewView(session: cameraModel.session, onCapture: {
                        cameraModel.capturePhoto {
                            withAnimation { cameraModel.changeCapturingState(to: true) }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                withAnimation { cameraModel.changeCapturingState(to: false) }
                            }
                        }
                    }, proxy: previewProxy)
                    .scaleEffect(visualZoomScale)
                    .rotation3DEffect(.degrees(cameraModel.flipRotation), axis: (x: 0, y: 1, z: 0))
                    .blur(radius: visualBlur)
                    .opacity(visualOpacity)
                    .animation(.easeInOut, value: scenePhase)
                    .frame(width: previewRect.width, height: previewRect.height)
                    .position(x: previewRect.midX, y: previewRect.midY)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                if previewInteractionStartPoint == nil {
                                    beginPreviewInteraction(at: value.startLocation)
                                }
                                updatePreviewInteraction(at: value.location)
                            }
                            .onEnded { value in
                                endPreviewInteraction(at: value.location)
                            }
                    )
                    .simultaneousGesture(
                        SpatialTapGesture(count: 2)
                            .onEnded { _ in
                                hapticTrigger += 1
                                withAnimation(.bouncy) {
                                    cameraModel.toggleSelfie()
                                }
                            }
                    )
                    
                    if !cameraModel.showSimpleView {
                        // MARK: - Peaking/Clipping overlays
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
                        }
                        
                        // MARK: - Level / Horizon overlay
                        if cameraModel.shouldShowLevel {
                            LevelOverlayView(model: levelModel)
                                .ignoresSafeArea()
                        }
                    }
                    
                    // MARK: - QR Code
                    ZStack {
                        if let url = cameraModel.detectedCodeURL {
                            VStack(spacing: 4) {
                                Text(copiedString)
                                    .font(.system(size: 10, weight: .bold))
                                    .fontWidth(.expanded)
                                    .foregroundStyle(.yellow.opacity(0.8))
                                    .padding(8)
                                    .glassEffect()
                                Button {
                                    UIApplication.shared.open(url)
                                    cameraModel.ignoreCurrentCode()
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: linkSymbolName)
                                        Text(url.host ?? backupURLName)
                                            .lineLimit(1)
                                    }
                                    .font(.system(size: 14, weight: .bold))
                                    .fontWidth(.expanded)
                                }
                                .buttonStyle(.glass)
                                .padding(.horizontal)
                                
                                Button(closeLinkTitle, systemImage: closeSymbolName) {
                                    cameraModel.ignoreCurrentCode()
                                }
                                .font(.system(size: 10, weight: .bold))
                                .fontWidth(.expanded)
                                .foregroundStyle(.yellow.opacity(0.8))
                                .buttonStyle(.glass)
                            }
                            .position(x: previewRect.midX, y: previewRect.midY)
                            .transition(.opacity)
                        }
                    }
                    .animation(.bouncy, value: cameraModel.detectedCodeURL)
                    
                    // MARK: - Lens Cleaning Hint
                    ZStack {
                        if cameraModel.shouldShowLensCleaningHint {
                            VStack(spacing: 4) {
                                Button {
                                    hapticTriggerR += 1
                                    cameraModel.dismissLensCleaningHint()
                                } label: {
                                    HStack(spacing: 8) {
                                        Image(systemName: lensCleaningSymbolName)
                                        Text(lensCleaningTitle)
                                    }
                                    .font(.system(size: 14, weight: .bold))
                                    .fontWidth(.expanded)
                                }
                                .buttonStyle(.glass)
                                .padding(.horizontal)
                                
                                Button(closeCleaningTitle, systemImage: closeSymbolName) {
                                    cameraModel.dismissLensCleaningHint()
                                }
                                .font(.system(size: 10, weight: .bold))
                                .fontWidth(.expanded)
                                .foregroundStyle(.yellow.opacity(0.8))
                                .buttonStyle(.glass)
                            }
                            .position(x: previewRect.midX, y: previewRect.midY)
                            .transition(.opacity)
                        }
                    }
                    .animation(.bouncy, value: cameraModel.shouldShowLensCleaningHint)
                }
                .blur(radius: scenePhase != .active ? 20 : 0)
                
                // MARK: - UI Overlays
                VStack(spacing: 0) {
                    if !cameraModel.showSimpleView {
                        TopBarView(cameraModel: cameraModel, selectedControl: $selectedControl)
                            .offset(y:-10)
                        
                        Spacer()
                        
                        ZStack {
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
                                .transition(.scale(scale: 0.5, anchor: .center).combined(with: .opacity))
                            }
                        }
                        .animation(.bouncy, value: cameraModel.histogramModeLarge)
                        
                        if let selectedControl {
                            ManualControlsView(cameraModel: cameraModel, control: selectedControl)
                                .padding(.bottom, 8)
                        }
                        
                        ZStack {
                            LensSelectorView(cameraModel: cameraModel)
                                .padding(.bottom, 30)
                        }
                        .animation(.bouncy, value: cameraModel.activeLens)
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
            // MARK: - Status bar
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
        .sensoryFeedback(.impact(flexibility: .soft), trigger: cameraModel.detectedCodeURL)
        .onAppear {
            cameraModel.configure()
            levelModel.startUpdates()
        }
        .onDisappear {
            levelModel.stopUpdates()
        }
        .onChange(of: cameraModel.shouldShowLevel) { _, new in
            changeLevelMonitoring(new)
        }
        .onChange(of: cameraModel.activeLens) { oldLens, newLens in
            // Handle visual "zoom" bump to mask lens hardware switch
            if oldLens.isFront == newLens.isFront {
                // Use a light zoom/blur mask for same-facing lens changes.
                isAwaitingSameFacingLensCompletion = true
                let oldValue = Double(oldLens.label) ?? 1.0
                let newValue = Double(newLens.label) ?? 1.0
                let isZoomIn = newValue > oldValue
                let targetScale: CGFloat = isZoomIn ? 1.035 : 0.965
                withAnimation(.easeIn(duration: 0.14)) {
                    visualZoomScale = targetScale
                    visualOpacity = 0.72
                    visualBlur = 6
                }
            } else {
                // Keep the motion continuous; only the de-blur waits for the hardware swap.
                isAwaitingFacingFlipCompletion = true
                pendingFacingFlipRotation = newLens.isFront ? -80 : 80
                withAnimation(.easeIn(duration: 0.12)) {
                    visualOpacity = 0.1
                    visualBlur = 18
                    cameraModel.flipRotation = newLens.isFront ? 80 : -80
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    cameraModel.flipRotation = pendingFacingFlipRotation
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                        cameraModel.flipRotation = 0
                    }
                }
            }
        }
        .onChange(of: cameraModel.lensSwitchCompletionCount) {
            if isAwaitingSameFacingLensCompletion {
                isAwaitingSameFacingLensCompletion = false
                withAnimation(.easeOut(duration: 0.22)) {
                    visualZoomScale = 1.0
                    visualBlur = 0
                    visualOpacity = 1.0
                }
            }
            
            if isAwaitingFacingFlipCompletion {
                isAwaitingFacingFlipCompletion = false
                withAnimation(.easeOut(duration: 0.18)) {
                    visualBlur = 0
                    visualOpacity = 1.0
                }
            }
        }
        .onChange(of: cameraModel.appView) { _, new in
            changeLevelMonitoring(new == AppView.standard)
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                cameraModel.startSession()
                changeLevelMonitoring(cameraModel.shouldShowLevel && cameraModel.appView == .standard)
            } else {
                cameraModel.stopSession()
                levelModel.stopUpdates()
                if newPhase == .background {
                    cameraModel.clearIgnoredCodes()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.deviceDidShakeNotification)) { _ in
            if let url = cameraModel.detectedCodeURL {
                UIApplication.shared.open(url)
                cameraModel.ignoreCurrentCode()
            }
        }
        .alert(errorString, isPresented: $cameraModel.showError) {
            Button(okButtonString, role: .cancel) {}
        } message: {
            Text(cameraModel.errorMessage)
        }
        .fullScreenCover(isPresented: Binding(get: {
            cameraModel.appView == .settings
        }, set: { _, _ in
            cameraModel.hideSettings()
        })) {
            SettingsView(cameraModel: cameraModel) {
                shutterCount = 0
            }
        }
    }
}
