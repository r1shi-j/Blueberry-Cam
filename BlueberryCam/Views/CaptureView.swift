import SwiftUI
import UIKit

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
    private var expandSymbolName: String { "arrow.up.left.and.arrow.down.right" }
    private var shrinkSymbolName: String { "arrow.down.right.and.arrow.up.left" }
    private var tapHoldDuration: TimeInterval { 0.7 }
    private var tapMoveTolerance: CGFloat { 18 }
    private var focusReticleSliderXTolerance: CGFloat { 24 }
    private var focusReticleSliderYTolerance: CGFloat { 96 }
    
    func makePreviewRect(in geo: GeometryProxy) -> CGRect {
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
    
    func isNearExistingExposureSlider(_ point: CGPoint) -> Bool {
        guard let indicatorPoint = cameraModel.tapFocusIndicatorPoint,
              cameraModel.isTapFocusIndicatorVisible else { return false }
        let sliderCenterX = indicatorPoint.x + 56
        let sliderCenterY = indicatorPoint.y + cameraModel.tapFocusIndicatorOffset
        let dx = abs(sliderCenterX - point.x)
        let dy = abs(sliderCenterY - point.y)
        return dx <= focusReticleSliderXTolerance && dy <= focusReticleSliderYTolerance
    }
    
    func beginPreviewInteraction(at location: CGPoint) {
        cameraModel.isTapFocusInteractionActive = true
        previewInteractionStartPoint = location
        previewInteractionStartTime = Date()
        previewInteractionDidLock = false
        previewInteractionIsBiasOnly = cameraModel.canAdjustTapPointExposureBias && isNearExistingExposureSlider(location)
        previewInteractionStartBias = previewInteractionIsBiasOnly ? cameraModel.tapExposureBias : 0
        cameraModel.suspendTapFocusIndicatorHide()
        
        guard cameraModel.canHandleTapPointInteraction else { return }
        if previewInteractionIsBiasOnly { return }
        guard cameraModel.isAutoFocus,
              let devicePoint = previewProxy.captureDevicePoint(fromLayerPoint: location) else { return }
        cameraModel.handleTapPointAction(devicePoint: devicePoint, previewPoint: location)
        cameraModel.suspendTapFocusIndicatorHide()
        schedulePreviewHold(at: location)
    }
    
    func updatePreviewInteraction(at location: CGPoint) {
        guard let startPoint = previewInteractionStartPoint,
              previewInteractionStartTime != nil else { return }
        
        let verticalDrag = location.y - startPoint.y
        let movement = hypot(location.x - startPoint.x, verticalDrag)
        if movement > tapMoveTolerance {
            previewInteractionHoldTask?.cancel()
        }
        
        if cameraModel.canAdjustTapPointExposureBias,
           (previewInteractionIsBiasOnly || cameraModel.isAutoFocus),
           !previewInteractionDidLock {
            cameraModel.suspendTapFocusIndicatorHide()
            cameraModel.keepTapFocusIndicatorAlive(at: startPoint)
            cameraModel.updateTapExposureBias(from: previewInteractionStartBias, verticalDrag: verticalDrag)
        }
    }
    
    func endPreviewInteraction(at location: CGPoint) {
        defer {
            cameraModel.isTapFocusInteractionActive = false
            previewInteractionHoldTask?.cancel()
            previewInteractionHoldTask = nil
            previewInteractionStartPoint = nil
            previewInteractionStartTime = nil
            previewInteractionDidLock = false
            previewInteractionIsBiasOnly = false
        }
        
        guard let startPoint = previewInteractionStartPoint else { return }
        let movement = hypot(location.x - startPoint.x, location.y - startPoint.y)
        
        if cameraModel.canAdjustTapPointExposureBias {
            if cameraModel.tapFocusLockLabel == nil {
                cameraModel.scheduleTapFocusIndicatorHide()
            }
        }
        
        guard movement <= tapMoveTolerance,
              !previewInteractionDidLock,
              !previewInteractionIsBiasOnly,
              !cameraModel.isAutoFocus,
              cameraModel.isAutoExposure,
              let devicePoint = previewProxy.captureDevicePoint(fromLayerPoint: startPoint) else { return }
        cameraModel.handleTapPointAction(devicePoint: devicePoint, previewPoint: startPoint)
    }
    
    func schedulePreviewHold(at location: CGPoint) {
        previewInteractionHoldTask?.cancel()
        guard cameraModel.canLockTapPoint else { return }
        previewInteractionHoldTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(tapHoldDuration * 1_000_000_000))
            guard !Task.isCancelled,
                  !previewInteractionDidLock,
                  let startPoint = previewInteractionStartPoint,
                  let devicePoint = previewProxy.captureDevicePoint(fromLayerPoint: startPoint) else { return }
            previewInteractionDidLock = true
            cameraModel.handleTapPointHold(devicePoint: devicePoint, previewPoint: location)
        }
    }
}

struct CaptureView: View {
    @Environment(\.scenePhase) private var scenePhase
    
    @Binding var shutterCount: Int
    @ObservedObject var permissionModel: PermissionModel
    @StateObject private var cameraModel = CameraModel()
    @StateObject private var levelModel = LevelMotionModel()
    @State private var selectedControl: ManualControl?
    
    // Haptics - driven imperatively with UIKit
    private let impactLight = UIImpactFeedbackGenerator(style: .light)
    private let impactSoft = UIImpactFeedbackGenerator(style: .medium)
    
    // Preview focus
    @State var previewProxy = PreviewViewProxy()
    @State var previewInteractionStartPoint: CGPoint?
    @State var previewInteractionStartTime: Date?
    @State var previewInteractionDidLock = false
    @State var previewInteractionIsBiasOnly = false
    @State var previewInteractionStartBias: Float = 0
    @State var previewInteractionHoldTask: Task<Void, Never>?
    
    // Transitions
    @State private var visualBlur: CGFloat = 0
    @State private var visualOpacity: CGFloat = 1.0
    @State private var isAwaitingFacingFlipCompletion = false
    @State private var pendingFacingFlipRotation: Double = 0
    
    // Track previous values for onChange equivalents
    @State private var prevLensCount = 0
    
    private var cameraContent: some View {
        GeometryReader { geo in
            let previewRect = makePreviewRect(in: geo)
            
            ZStack {
                Color.black.ignoresSafeArea()
                
                ZStack {
                    // MARK: - Viewfinder
                    CameraPreviewView(session: cameraModel.session, proxy: previewProxy)
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
                            TapGesture(count: 2)
                                .onEnded {
                                    impactLight.impactOccurred()
                                    withAnimation(.spring()) {
                                        cameraModel.toggleSelfie()
                                    }
                                }
                        )
                    
                    if !cameraModel.showSimpleView {
                        // MARK: - Zebras
                        if cameraModel.showZebraStripes {
                            AnalysisOverlayView(
                                mask: cameraModel.zebraMask,
                                gridSize: cameraModel.analysisGridSize,
                                style: .zebra
                            )
                            .frame(width: previewRect.width, height: previewRect.height)
                            .position(x: previewRect.midX, y: previewRect.midY)
                        }
                        
                        // MARK: - Highlight Clipping
                        if cameraModel.showClipping {
                            AnalysisOverlayView(
                                mask: cameraModel.clippingMask,
                                gridSize: cameraModel.analysisGridSize,
                                style: .clipping
                            )
                            .frame(width: previewRect.width, height: previewRect.height)
                            .position(x: previewRect.midX, y: previewRect.midY)
                        }
                        
                        // MARK: - Focus Loupe
                        if !cameraModel.isAutoFocus && cameraModel.showFocusLoupe,
                           let _ = cameraModel.loupeImage {
                            let loupeSize: CGFloat = previewRect.width / 3
                            FocusLoupeView(loupeImage: cameraModel.loupeImage)
                                .frame(width: loupeSize, height: loupeSize)
                                .clipShape(Circle())
                                .overlay(
                                    Circle()
                                        .stroke(Color.white.opacity(0.5), lineWidth: 1.5)
                                )
                                .shadow(color: Color.black.opacity(0.5), radius: 8, x: 0, y: 2)
                                .position(x: previewRect.midX, y: previewRect.midY)
                                .allowsHitTesting(false)
                                .transition(.opacity)
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
                    
                    // MARK: - Tap to focus overlay
                    if cameraModel.isTapFocusIndicatorVisible, let indicatorPoint = cameraModel.tapFocusIndicatorPoint {
                        FocusReticleView(
                            lockLabel: cameraModel.tapFocusLockLabel,
                            exposureOffset: cameraModel.tapFocusIndicatorOffset,
                            showsExposureHandle: cameraModel.canAdjustTapPointExposureBias,
                            isDimmed: cameraModel.isTapFocusIndicatorDimmed
                        )
                        .position(indicatorPoint)
                        .transition(.opacity)
                    }
                    
                    // MARK: - AE/AF lock label
                    ZStack {
                        if let lockLabel = cameraModel.tapFocusLockLabel {
                            Text(lockLabel)
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.yellow)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Color.black.opacity(0.55))
                                .clipShape(Capsule())
                                .position(x: previewRect.midX, y: previewRect.midY - previewRect.height / 2 + 20)
                                .transition(.opacity)
                        }
                    }
                    .animation(.spring(), value: cameraModel.tapFocusLockLabel)
                    
                    // MARK: - QR Code banner
                    ZStack {
                        if let url = cameraModel.detectedCodeURL {
                            VStack(spacing: 4) {
                                Text(copiedString)
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(Color.yellow.opacity(0.8))
                                    .padding(8)
                                    .background(Color.black.opacity(0.55))
                                    .clipShape(Capsule())
                                
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
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                                    .background(Color.black.opacity(0.6))
                                    .clipShape(Capsule())
                                }
                                
                                Button {
                                    cameraModel.ignoreCurrentCode()
                                } label: {
                                    Label(closeLinkTitle, systemImage: closeSymbolName)
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(Color.yellow.opacity(0.8))
                                        .padding(8)
                                        .background(Color.black.opacity(0.55))
                                        .clipShape(Capsule())
                                }
                            }
                            .position(x: previewRect.midX, y: previewRect.midY)
                            .transition(.opacity)
                        }
                    }
                    .animation(.spring(), value: cameraModel.detectedCodeURL?.absoluteString)
                }
                .blur(radius: scenePhase != .active ? 20 : 0)
                
                // MARK: - UI Overlays
                VStack(spacing: 0) {
                    if !cameraModel.showSimpleView {
                        TopBarView(cameraModel: cameraModel, selectedControl: $selectedControl)
                        
                        ZStack {
                            HStack {
                                if cameraModel.histogramModeSmall != .none {
                                    HistogramView(
                                        mode: cameraModel.histogramModeSmall,
                                        size: .small,
                                        lumaData: cameraModel.histogramData,
                                        redData: cameraModel.redHistogram,
                                        greenData: cameraModel.greenHistogram,
                                        blueData: cameraModel.blueHistogram,
                                        waveformData: cameraModel.waveformData
                                    )
                                    .frame(maxWidth: 80, maxHeight: 20)
                                    .onTapGesture {
                                        impactLight.impactOccurred()
                                        cameraModel.cycleHistogramMode(mode: &cameraModel.histogramModeSmall)
                                    }
                                    .onLongPressGesture {
                                        impactSoft.impactOccurred()
                                        cameraModel.hideHistogram(for: .small)
                                    }
                                    .transition(.scale(scale: 0.5, anchor: .center).combined(with: .opacity))
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 12)
                        }
                        .animation(.spring(), value: cameraModel.histogramModeSmall)
                        
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
                                    impactLight.impactOccurred()
                                    cameraModel.cycleHistogramMode(mode: &cameraModel.histogramModeLarge)
                                }
                                .onLongPressGesture {
                                    impactSoft.impactOccurred()
                                    withAnimation(.spring()) {
                                        cameraModel.hideHistogram(for: .large)
                                    }
                                }
                                .transition(.scale(scale: 0.5, anchor: .center).combined(with: .opacity))
                            }
                        }
                        .animation(.spring(), value: cameraModel.histogramModeLarge)
                        
                        if let selectedControl = selectedControl {
                            ManualControlsView(cameraModel: cameraModel, control: selectedControl)
                                .padding(.bottom, 8)
                        }
                    } else {
                        // MARK: Exit Clean UI Button
                        VStack {
                            HStack {
                                Spacer()
                                
                                let isClean = cameraModel.appView == .clean
                                Button {
                                    impactLight.impactOccurred()
                                    withAnimation(.spring()) {
                                        cameraModel.appView = isClean ? .standard : .clean
                                    }
                                } label: {
                                    Image(systemName: isClean ? shrinkSymbolName : expandSymbolName)
                                        .font(.system(size: 13))
                                        .foregroundColor(isClean ? .black : Colors.buttonText)
                                        .frame(width: 26, height: 26)
                                        .background(isClean ? .yellow : Colors.buttonBackground)
                                        .clipShape(Circle())
                                }
                                .padding(8)
                            }
                        }
                        
                        Spacer()
                    }
                    
                    BottomBarView(cameraModel: cameraModel, shutterCount: $shutterCount)
                        .padding(.bottom, 2)
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
    }
    
    var body: some View {
        ZStack {
            if permissionModel.allGranted {
                cameraContent
                    .transition(.opacity)
            } else if permissionModel.anyDenied {
                PermissionDeniedView(
                    cameraGranted: permissionModel.cameraStatus == .granted,
                    photosGranted: permissionModel.photosStatus == .granted
                )
                .transition(.opacity)
            } else {
                Color.black.ignoresSafeArea()
            }
        }
        .animation(.easeInOut(duration: 0.4), value: permissionModel.allGranted)
        .animation(.easeInOut(duration: 0.4), value: permissionModel.anyDenied)
        .statusBarHidden()
        .onAppear {
            impactLight.prepare()
            impactSoft.prepare()
            cameraModel.configure()
            levelModel.startUpdates()
            levelModel.setLevelDisplayEnabled(cameraModel.shouldShowLevel && cameraModel.appView == .standard)
            levelModel.onGravityUpdate = { gx, gy, gz in
                cameraModel.lastGravity = (gx, gy, gz)
            }
        }
        .onDisappear {
            levelModel.stopUpdates()
            cameraModel.clearTapPointInteraction(resetDeviceState: false)
        }
        .onChange(of: cameraModel.shouldShowLevel) { new in
            levelModel.setLevelDisplayEnabled(new && cameraModel.appView == .standard)
        }
        .onChange(of: scenePhase) { newPhase in
            if newPhase == .active {
                cameraModel.startSession()
                levelModel.startUpdates()
                levelModel.setLevelDisplayEnabled(cameraModel.shouldShowLevel && cameraModel.appView == .standard)
            } else {
                cameraModel.stopSession()
                levelModel.stopUpdates()
                if newPhase == .background {
                    cameraModel.clearIgnoredCodes()
                }
            }
        }
        .onChange(of: cameraModel.appView) { new in
            levelModel.setLevelDisplayEnabled(new == .standard && cameraModel.shouldShowLevel)
            if new == .settings {
                cameraModel.stopSession()
            } else {
                cameraModel.startSession()
            }
        }
        .onChange(of: cameraModel.activeLens) { newLens in
            cameraModel.clearTapPointInteraction(resetDeviceState: false)
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
        .onChange(of: cameraModel.lensSwitchCompletionCount) { _ in
            if isAwaitingFacingFlipCompletion {
                isAwaitingFacingFlipCompletion = false
                withAnimation(.easeOut(duration: 0.18)) {
                    visualBlur = 0
                    visualOpacity = 1.0
                }
            }
        }
        .onChange(of: cameraModel.tap​Focus​Lock​Haptic​Trigger) { _ in
            impactSoft.impactOccurred()
        }
        .onChange(of: cameraModel.detectedCodeURL) { url in
            if url != nil { impactSoft.impactOccurred() }
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
        }, set: { _ in
            if cameraModel.appView == .settings {
                cameraModel.hideSettings()
            }
        })) {
            SettingsView(cameraModel: cameraModel) {
                shutterCount = 0
            }
        }
    }
}
