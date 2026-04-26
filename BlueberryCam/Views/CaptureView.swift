import ConfettiSwiftUI
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
    private var tapHoldDuration: TimeInterval { 0.7 }
    private var tapMoveTolerance: CGFloat { 18 }
    private var focusReticleSliderXTolerance: CGFloat { 24 }
    private var focusReticleSliderYTolerance: CGFloat { 96 }
    private var countdownTextTransition: AnyTransition {
        .asymmetric(
            insertion: .scale(scale: 2.6).combined(with: .opacity),
            removal: .scale(scale: 0.2).combined(with: .opacity)
        )
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
    
    private func isNearExistingExposureSlider(_ point: CGPoint) -> Bool {
        guard let indicatorPoint = cameraModel.tapFocusIndicatorPoint,
              cameraModel.isTapFocusIndicatorVisible else { return false }
        let sliderCenterX = indicatorPoint.x + 56
        let sliderCenterY = indicatorPoint.y + cameraModel.tapFocusIndicatorOffset
        let dx = abs(sliderCenterX - point.x)
        let dy = abs(sliderCenterY - point.y)
        return dx <= focusReticleSliderXTolerance && dy <= focusReticleSliderYTolerance
    }
    
    private func countdownText(for value: Double) -> String {
        let clampedValue = max(value, 0)
        
        if cameraModel.detailedCountdownTimer {
            return clampedValue.formatted(.number.precision(.fractionLength(3)))
        }
        
        return Int(ceil(clampedValue)).formatted()
    }
    
    private func updateBurstFeedbackOverlay(_ message: String?) {
        burstFeedbackFadeTask?.cancel()
        
        if let message {
            displayedBurstFeedbackMessage = message
            withAnimation(.easeInOut(duration: 0.2)) {
                isBurstFeedbackVisible = true
            }
            return
        }
        
        withAnimation(.easeInOut(duration: 0.35)) {
            isBurstFeedbackVisible = false
        }
        burstFeedbackFadeTask = Task { @MainActor in
            do {
                try await Task.sleep(for: .milliseconds(350))
                displayedBurstFeedbackMessage = nil
                burstFeedbackFadeTask = nil
            } catch {
                return
            }
        }
    }
    
    private func beginPreviewInteraction(at location: CGPoint) {
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
    
    private func updatePreviewInteraction(at location: CGPoint) {
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
    
    private func endPreviewInteraction(at location: CGPoint) {
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
    
    private func schedulePreviewHold(at location: CGPoint) {
        previewInteractionHoldTask?.cancel()
        guard cameraModel.canLockTapPoint else { return }
        previewInteractionHoldTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(tapHoldDuration))
            guard !Task.isCancelled,
                  !previewInteractionDidLock,
                  let startPoint = previewInteractionStartPoint,
                  let devicePoint = previewProxy.captureDevicePoint(fromLayerPoint: startPoint) else { return }
            previewInteractionDidLock = true
            cameraModel.handleTapPointHold(devicePoint: devicePoint, previewPoint: location)
        }
    }
    
    @ViewBuilder
    private func timerCountdownOverlay(in previewRect: CGRect) -> some View {
        if cameraModel.isTimerCountingDown {
            ZStack {
                if let countdownValue = cameraModel.timerCountdownValue {
                    Text(countdownText(for: countdownValue))
                        .font(.system(size: cameraModel.detailedCountdownTimer ? 58 : 84, weight: .bold, design: cameraModel.detailedCountdownTimer ? .rounded : .default))
                        .fontWidth(cameraModel.detailedCountdownTimer ? .standard : .expanded)
                        .monospacedDigit()
                        .contentTransition(.numericText(countsDown: true))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.35), radius: 12, x: 0, y: 4)
                        .position(x: previewRect.midX, y: previewRect.midY)
                        .transition(countdownTextTransition)
                }
            }
            .animation(.spring(response: 0.45, dampingFraction: 0.8), value: cameraModel.isTimerCountingDown)
            .animation(.easeInOut(duration: 0.12), value: cameraModel.timerCountdownValue)
        }
    }
}

struct CaptureView: View {
    @Environment(\.scenePhase) private var scenePhase
    
    @Binding var shutterCount: Int
    @Binding var shutterCountBurst: Int
    @Bindable var permissionModel: PermissionModel
    @State private var cameraModel = CameraModel()
    @State private var levelModel = LevelMotionModel()
    @State private var selectedControl: ManualControl?
    
    // Haptics
    @State private var hapticTrigger = 0
    @State private var hapticTriggerR = 0
    
    // Preview focus
    @State private var previewProxy = PreviewViewProxy()
    @State private var previewInteractionStartPoint: CGPoint?
    @State private var previewInteractionStartTime: Date?
    @State private var previewInteractionDidLock = false
    @State private var previewInteractionIsBiasOnly = false
    @State private var previewInteractionStartBias: Float = 0
    @State private var previewInteractionHoldTask: Task<Void, Never>?
    
    // Transitions
    @State private var visualZoomScale: CGFloat = 1.0
    @State private var visualBlur: CGFloat = 0
    @State private var visualOpacity: CGFloat = 1.0
    @State private var isAwaitingFacingFlipCompletion = false
    @State private var isAwaitingSameFacingLensCompletion = false
    @State private var pendingFacingFlipRotation: Double = 0
    @State private var displayedBurstFeedbackMessage: String?
    @State private var isBurstFeedbackVisible = false
    @State private var burstFeedbackFadeTask: Task<Void, Never>?
    
    private var cameraContent: some View {
        GeometryReader { geo in
            let previewRect = makePreviewRect(in: geo)
            
            ZStack {
                Color.black.ignoresSafeArea()
                
                // MARK: - Camera Overlays
                ZStack {
                    // MARK: - Viewfinder
                    CameraPreviewView(session: cameraModel.session, onCapture: {
                        cameraModel.handleShutterButton {
                            withAnimation { cameraModel.changeCapturingState(to: true) }
                            Task { @MainActor in
                                try? await Task.sleep(for: .milliseconds(150))
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
                    .allowsHitTesting(!cameraModel.isTimerCountingDown && !cameraModel.isBurstCapturing)
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
                        
                        // MARK: - Focus Peaking
                        if !cameraModel.isAutoFocus && cameraModel.showFocusPeaking {
                            AnalysisOverlayView(
                                mask: cameraModel.focusPeakingMask,
                                gridSize: cameraModel.analysisGridSize,
                                style: .focusPeaking
                            )
                            .frame(width: previewRect.width, height: previewRect.height)
                            .position(x: previewRect.midX, y: previewRect.midY)
                        }
                        
                        // MARK: - Focus Loupe
                        if !cameraModel.isAutoFocus && cameraModel.showFocusLoupe, cameraModel.loupeImage != nil {
                            let loupeSize: CGFloat = previewRect.width / 3
                            FocusLoupeView(loupeImage: cameraModel.loupeImage)
                                .frame(width: loupeSize, height: loupeSize)
                                .clipShape(Circle())
                                .overlay(
                                    Circle()
                                        .stroke(.white.opacity(0.5), lineWidth: 1.5)
                                )
                                .shadow(color: .black.opacity(0.5), radius: 8, x: 0, y: 2)
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
                    if !cameraModel.isBurstCapturing, cameraModel.isTapFocusIndicatorVisible, let indicatorPoint = cameraModel.tapFocusIndicatorPoint {
                        FocusReticleView(
                            lockLabel: cameraModel.tapFocusLockLabel,
                            exposureOffset: cameraModel.tapFocusIndicatorOffset,
                            showsExposureHandle: cameraModel.canAdjustTapPointExposureBias,
                            isDimmed: cameraModel.isTapFocusIndicatorDimmed
                        )
                        .position(indicatorPoint)
                        .transition(.opacity)
                    }
                    
                    // MARK: - Focus lock overlay
                    ZStack {
                        if !cameraModel.isBurstCapturing, let lockLabel = cameraModel.tapFocusLockLabel {
                            Text(lockLabel)
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.yellow)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(.black.opacity(0.55), in: .capsule)
                                .position(x: previewRect.midX, y: previewRect.midY - previewRect.height / 2 + 20)
                                .transition(.opacity)
                        }
                    }
                    .animation(.bouncy, value: cameraModel.tapFocusLockLabel)
                    
                    // MARK: - QR Code
                    ZStack {
                        if !cameraModel.isTimerCountingDown, !cameraModel.isBurstCapturing, let url = cameraModel.detectedCodeURL {
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
                        if !cameraModel.isTimerCountingDown, !cameraModel.isBurstCapturing, cameraModel.shouldShowLensCleaningHint {
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
                    
                    // MARK: - Burst Feedback
                    if let displayedBurstFeedbackMessage {
                        Text(displayedBurstFeedbackMessage)
                            .font(.system(size: 16, weight: .bold))
                            .fontWidth(.expanded)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(.black.opacity(0.6), in: .capsule)
                            .position(x: previewRect.midX, y: previewRect.midY)
                            .allowsHitTesting(false)
                            .opacity(isBurstFeedbackVisible ? 1 : 0)
                    }
                }
                .blur(radius: scenePhase != .active ? 20 : 0)
                
                // MARK: - UI Overlays
                VStack(spacing: 0) {
                    if !cameraModel.showSimpleView {
                        VStack(spacing: 0) {
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
                        }
                        .transition(.opacity)
                    } else {
                        if cameraModel.isBurstCapturing {
                            VStack(spacing: 6) {
                                Text(cameraModel.burstCaptureStatusLabel)
                                    .font(.system(size: 16, weight: .bold))
                                    .fontWidth(.expanded)
                                    .monospacedDigit()
                                    .contentTransition(.numericText())
                                
                                if cameraModel.shouldShowBurstIntervalCountdown {
                                    Text(cameraModel.burstIntervalCountdownLabel)
                                        .font(.system(size: 16, weight: .bold))
                                        .fontWidth(.expanded)
                                        .monospacedDigit()
                                        .contentTransition(.numericText(countsDown: true))
                                }
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(.black.opacity(0.6), in: .rect(cornerRadius: 8))
                            .allowsHitTesting(false)
                            .padding(.top, 16)
                            .transition(.opacity)
                        }
                        
                        Spacer()
                    }
                    
                    BottomBarView(
                        cameraModel: cameraModel,
                        shutterCount: $shutterCount,
                        shutterCountBurst: $shutterCountBurst
                    )
                    .padding(.bottom, 30)
                }
                .allowsHitTesting(!cameraModel.isTimerCountingDown)
                .animation(.easeInOut(duration: 0.2), value: cameraModel.showSimpleView)
                
                // MARK: - Timer countdown
                timerCountdownOverlay(in: previewRect)
                
                // MARK: - Capture flash
                if cameraModel.isCapturing {
                    Color.white.opacity(0.3)
                        .frame(width: previewRect.width, height: previewRect.height)
                        .position(x: previewRect.midX, y: previewRect.midY)
                        .animation(.easeOut(duration: 0.15), value: cameraModel.isCapturing)
                }
                
                // MARK: - Confetti cannons
                ConfettiCannon(
                    trigger: $cameraModel.confettiCannonTrigger,
                    num: 50,
                    confettis: [
                        .sfSymbol(symbolName: "bolt.fill"),
//                        .sfSymbol(symbolName: "camera.macro"),
                        .sfSymbol(symbolName: "camera.aperture"),
//                        .sfSymbol(symbolName: "camera.filters"),
                        .sfSymbol(symbolName: "camera.shutter.button.fill"),
//                        .sfSymbol(symbolName: "photo.stack.fill"),
                        .sfSymbol(symbolName: "cloud.sun.fill"),
//                        .sfSymbol(symbolName: "cloud.bolt.rain"),
                        .sfSymbol(symbolName: "rainbow"),
//                        .sfSymbol(symbolName: "person.fill"),
                        .sfSymbol(symbolName: "bird"),
//                        .sfSymbol(symbolName: "mountain.2"),
                        .image("camera.blueberry"),
//                        .text("📸"),
                        .text("🫐"),
//                        .text("🌤️"),
                        .text("🌉"),
//                        .text("🌄"),
                        .text("🌅"),
//                        .text("🌃"),
                        .text("🍛"),
//                        .text("🐶"),
                        .text("🏎️"),
//                        .text("🚙"),
                        .text("🏀"),
//                        .text("⚽️"),
                        .text("🏈"),
                    ],
                    confettiSize: 12,
                    rainHeight: 800,
                    openingAngle: .degrees(45),
                    closingAngle: .degrees(75),
                    radius: 350
                )
                .position(x: previewRect.minX, y: previewRect.maxY - 60)
                .allowsHitTesting(false)
                
                ConfettiCannon(
                    trigger: $cameraModel.confettiCannonTrigger,
                    num: 50,
                    confettis: [
//                        .sfSymbol(symbolName: "bolt.fill"),
                        .sfSymbol(symbolName: "camera.macro"),
//                        .sfSymbol(symbolName: "camera.aperture"),
                        .sfSymbol(symbolName: "camera.filters"),
//                        .sfSymbol(symbolName: "camera.shutter.button.fill"),
                        .sfSymbol(symbolName: "photo.stack.fill"),
//                        .sfSymbol(symbolName: "cloud.sun.fill"),
                        .sfSymbol(symbolName: "cloud.bolt.rain"),
//                        .sfSymbol(symbolName: "rainbow"),
                        .sfSymbol(symbolName: "person.fill"),
//                        .sfSymbol(symbolName: "bird"),
                        .sfSymbol(symbolName: "mountain.2"),
//                        .image("camera.blueberry"),
                        .text("📸"),
//                        .text("🫐")
                        .text("🌤️"),
//                        .text("🌉"),
                        .text("🌄"),
//                        .text("🌅"),
                        .text("🌃"),
//                        .text("🍛"),
                        .text("🐶"),
//                        .text("🏎️"),
                        .text("🚙"),
//                        .text("🏀"),
                        .text("⚽️"),
//                        .text("🏈"),
                    ],
                    confettiSize: 12,
                    rainHeight: 800,
                    openingAngle: .degrees(105),
                    closingAngle: .degrees(135),
                    radius: 350
                )
                .position(x: previewRect.maxX, y: previewRect.maxY - 60)
                .allowsHitTesting(false)
            }
            .ignoresSafeArea(.keyboard)
        }
        .safeAreaInset(edge: .top) {
            // MARK: - Status bar
            if !cameraModel.showSimpleView {
                StatusBarAreaView(cameraModel: cameraModel)
                    .padding()
                    .ignoresSafeArea()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: .zero)
                    .transition(.opacity)
            } else {
                Color.clear
                    .padding()
                    .ignoresSafeArea()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: .zero)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: cameraModel.showSimpleView)
        .animation(.easeInOut(duration: 0.2), value: cameraModel.isBurstCapturing)
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
        .sensoryFeedback(.impact, trigger: hapticTrigger)
        .sensoryFeedback(.impact(flexibility: .soft), trigger: hapticTriggerR)
        .sensoryFeedback(.impact(flexibility: .soft), trigger: cameraModel.detectedCodeURL)
        .sensoryFeedback(.impact(flexibility: .soft), trigger: cameraModel.tap​Focus​Lock​Haptic​Trigger)
        .onAppear {
            cameraModel.configure()
            levelModel.startUpdates()
            levelModel.setLevelDisplayEnabled(cameraModel.shouldShowLevel && !cameraModel.showSimpleView)
            
            // Pass gravity updates to camera model
            levelModel.onGravityUpdate = { gx, gy, gz in
                cameraModel.lastGravity = (gx, gy, gz)
            }
        }
        .onDisappear {
            cameraModel.stopBurstCapture()
            burstFeedbackFadeTask?.cancel()
            levelModel.stopUpdates()
            cameraModel.clearTapPointInteraction(resetDeviceState: false)
        }
        .onChange(of: cameraModel.shouldShowLevel) { _, new in
            levelModel.setLevelDisplayEnabled(new && !cameraModel.showSimpleView)
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                cameraModel.startSession()
                levelModel.startUpdates() // Always start
                levelModel.setLevelDisplayEnabled(cameraModel.shouldShowLevel && !cameraModel.showSimpleView)
            } else {
                cameraModel.stopBurstCapture()
                cameraModel.stopSession()
                levelModel.stopUpdates() // Only stop when backgrounded
                if newPhase == .background {
                    cameraModel.clearIgnoredCodes()
                }
            }
        }
        .onChange(of: cameraModel.showSimpleView) { _, new in
            levelModel.setLevelDisplayEnabled(!new && cameraModel.shouldShowLevel)
        }
        .onChange(of: cameraModel.burstFeedbackMessage) { _, new in
            updateBurstFeedbackOverlay(new)
        }
        .onChange(of: cameraModel.activeLens) { oldLens, newLens in
            cameraModel.clearTapPointInteraction(resetDeviceState: false)
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
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(120))
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
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.deviceDidShakeNotification)) { _ in
            guard !cameraModel.isBurstCapturing else { return }
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
            SettingsView(
                cameraModel: cameraModel,
                shutterCount: $shutterCount,
                shutterCountBurst: $shutterCountBurst
            )
        }
    }
}
