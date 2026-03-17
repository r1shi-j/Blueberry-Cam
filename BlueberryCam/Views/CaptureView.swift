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
                
                // MARK: - QR Code
                if let url = cameraModel.detectedCodeURL {
                    VStack(spacing: 4) {
                        Text(copiedString)
                            .font(.system(size: 10, weight: .bold))
                            .fontWidth(.expanded)
                            .foregroundStyle(.yellow.opacity(0.8))
                            .padding(8)
                            .glassEffect()
                        Button {
                            if let raw = cameraModel.detectedCodeString {
                                UIPasteboard.general.string = raw
                            }
                            hapticTriggerR += 1
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
                        
                        Button(closeLinkTitle, systemImage: closeSymbolName) {
                            cameraModel.ignoreCurrentCode()
                        }
                        .font(.system(size: 10, weight: .bold))
                        .fontWidth(.expanded)
                        .foregroundStyle(.yellow.opacity(0.8))
                        .buttonStyle(.glass)
                    }
                    .position(x: previewRect.midX, y: previewRect.midY)
                    .animation(.bouncy, value: cameraModel.detectedCodeURL)
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
            changeLevelMonitoring(new)
        }
        .onChange(of: cameraModel.appView) { _, new in
            changeLevelMonitoring(new == AppView.standard)
        }
        .onChange(of: scenePhase) { _, newPhase in
            changeLevelMonitoring(newPhase == .active)
            if newPhase == .background {
                cameraModel.clearIgnoredCodes()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.deviceDidShakeNotification)) { _ in
            if let url = cameraModel.detectedCodeURL {
                if let raw = cameraModel.detectedCodeString {
                    UIPasteboard.general.string = raw
                }
                hapticTriggerR += 1
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
            SettingsView(cameraModel: cameraModel)
        }
    }
}
