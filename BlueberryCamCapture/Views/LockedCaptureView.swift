import LockedCameraCapture
import SwiftUI

// MARK: - Functions
extension LockedCaptureView {
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
    
    private func manualControlColor(for control: ManualControl) -> Color {
        switch control {
            case .ev: .orange.opacity(0.85)
            case .iso: .yellow.opacity(0.85)
            case .ss: .white.opacity(0.85)
            case .f: .green.opacity(0.85)
            case .wb: .cyan.opacity(0.85)
        }
    }
    
    private var manualRulerTickColor: Color {
        cameraModel.isViewfinderBright ? .black.opacity(0.72) : .white.opacity(0.92)
    }
    
    private var manualRulerCenterTickColor: Color {
        cameraModel.isViewfinderBright ? .black : .white
    }
    
    private var manualRulerCenterTickShadowColor: Color {
        cameraModel.isViewfinderBright ? .white.opacity(0.28) : .black.opacity(0.35)
    }
}

// MARK: Subviews
extension LockedCaptureView {
    // MARK: - Background Color
    private func backgroundColor() -> some View {
        Color.black.ignoresSafeArea()
    }
    
    // MARK: - Viewfinder
    private func viewFinder(_ previewRect: CGRect) -> some View {
        CameraPreviewView(
            session: cameraModel.session,
            onCaptureBegan: {},
            onCaptureEnded: capturePhoto,
            onCaptureCancelled: {},
            proxy: previewProxy
        )
        .scaleEffect(visualZoomScale)
        .blur(radius: visualBlur)
        .opacity(visualOpacity)
        .frame(width: previewRect.width, height: previewRect.height)
        .position(x: previewRect.midX, y: previewRect.midY)
        .allowsHitTesting(!cameraModel.isTimerCountingDown)
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
    }
    
    // MARK: - Tap to focus overlay
    @ViewBuilder
    private func focusBox() -> some View {
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
    }
    
    // MARK: - Focus lock overlay
    @ViewBuilder
    private func focusLock(_ previewRect: CGRect) -> some View {
        ZStack {
            if let lockLabel = cameraModel.tapFocusLockLabel {
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
        .animation(Animations.bouncy, value: cameraModel.tapFocusLockLabel)
    }
    
    // MARK: - Manual control rulers
    @ViewBuilder
    private func manualControlOverlays(in previewRect: CGRect) -> some View {
        ZStack {
            if !cameraModel.showSimpleView, let selectedControl {
                if selectedControl == .iso || selectedControl == .ss {
                    manualISOOverlay(in: previewRect)
                }
                
                switch selectedControl {
                    case .ev:
                        manualTrailingOverlay(
                            title: "EV",
                            color: manualControlColor(for: .ev),
                            value: Binding(
                                get: { cameraModel.exposureBias },
                                set: { cameraModel.setExposureBias($0) }
                            ),
                            range: -LockedCameraModel.minEV...LockedCameraModel.maxEV,
                            step: 0.1,
                            majorTickStride: 5,
                            accessibilityLabel: "Exposure value",
                            previewRect: previewRect
                        )
                    case .f:
                        manualTrailingOverlay(
                            title: "F",
                            color: manualControlColor(for: .f),
                            value: Binding(
                                get: { cameraModel.lensPosition },
                                set: { cameraModel.setManualFocusPosition($0) }
                            ),
                            range: 0...1,
                            step: 0.01,
                            majorTickStride: 10,
                            accessibilityLabel: "Focus",
                            previewRect: previewRect
                        )
                    case .wb:
                        manualTrailingOverlay(
                            title: "WB",
                            color: manualControlColor(for: .wb),
                            value: Binding(
                                get: { cameraModel.whiteBalanceTargetKelvin },
                                set: { cameraModel.setWhiteBalanceTargetKelvin($0) }
                            ),
                            range: LockedCameraModel.minWhiteBalance...LockedCameraModel.maxWhiteBalance,
                            step: 100,
                            majorTickStride: 5,
                            accessibilityLabel: "White balance",
                            previewRect: previewRect
                        )
                    case .iso, .ss:
                        manualTrailingOverlay(
                            title: "SS",
                            color: manualControlColor(for: .ss),
                            value: Binding(
                                get: { Float(cameraModel.shutterIndex) },
                                set: { cameraModel.setManualShutterIndex($0) }
                            ),
                            range: 0...cameraModel.maxShutterIndex,
                            step: 1,
                            majorTickStride: 4,
                            accessibilityLabel: "Shutter speed",
                            previewRect: previewRect
                        )
                }
            }
        }
        .animation(Animations.manualControlShown, value: selectedControl)
    }
    
    private func manualISOOverlay(in previewRect: CGRect) -> some View {
        VStack(spacing: 4) {
            ManualRulerView(
                value: Binding(
                    get: { cameraModel.isoStopIndex },
                    set: { cameraModel.setManualISOStopIndex($0) }
                ),
                range: 0...cameraModel.maxISOStopIndex,
                step: 1,
                axis: .horizontal,
                majorTickStride: 4,
                accessibilityLabel: "ISO",
                tickColor: manualRulerTickColor,
                centerTickColor: manualRulerCenterTickColor,
                centerTickShadowColor: manualRulerCenterTickShadowColor
            )
            .frame(width: previewRect.width * 0.78, height: 70)
            
            Text("ISO")
                .font(Fonts.manualLabel)
                .foregroundStyle(manualControlColor(for: .iso))
                .tracking(2)
        }
        .frame(width: previewRect.width, height: previewRect.height, alignment: .top)
        .padding(.top, 14)
        .position(x: previewRect.midX, y: previewRect.midY)
        .transition(
            .asymmetric(
                insertion: .scale(scale: 0.72, anchor: .top)
                    .combined(with: .opacity)
                    .animation(.smooth(duration: 0.42)),
                removal: .scale(scale: 0.72, anchor: .top)
                    .combined(with: .opacity)
                    .animation(.smooth(duration: 0.38))
            )
        )
    }
    
    private func manualTrailingOverlay(
        title: String,
        color: Color,
        value: Binding<Float>,
        range: ClosedRange<Float>,
        step: Float,
        majorTickStride: Int,
        accessibilityLabel: String,
        previewRect: CGRect
    ) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(Fonts.manualLabel)
                .foregroundStyle(color)
                .tracking(2)
            
            ManualRulerView(
                value: value,
                range: range,
                step: step,
                axis: .vertical,
                majorTickStride: majorTickStride,
                accessibilityLabel: accessibilityLabel,
                tickColor: manualRulerTickColor,
                centerTickColor: manualRulerCenterTickColor,
                centerTickShadowColor: manualRulerCenterTickShadowColor
            )
            .frame(width: 70, height: previewRect.height * 0.72)
        }
        .frame(width: previewRect.width, height: previewRect.height, alignment: .trailing)
        .padding(.trailing, 14)
        .position(x: previewRect.midX, y: previewRect.midY)
        .transition(.move(edge: .trailing).combined(with: .opacity))
    }
    
    // MARK: - Top Bar View
    private func topBarView() -> some View {
        LockedTopBarView(cameraModel: cameraModel, selectedControl: $selectedControl)
            .offset(y:-2)
    }
    
    // MARK: - Bottom Bar View
    private func bottomBarView() -> some View {
        LockedBottomBarView(
            cameraModel: cameraModel,
            lockedSession: lockedSession,
            onShutterFeedback: triggerShutterFeedback
        )
        .padding(.bottom, 30)
    }
    
    // MARK: - Timer countdown
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
            .animation(Animations.timerShown, value: cameraModel.isTimerCountingDown)
            .animation(Animations.timerCountdown, value: cameraModel.timerCountdownValue)
        }
    }
    
    // MARK: - Capture flash
    @ViewBuilder
    private func captureFlash(_ previewRect: CGRect) -> some View {
        if cameraModel.isCapturing {
            Color.white.opacity(0.3)
                .frame(width: previewRect.width, height: previewRect.height)
                .position(x: previewRect.midX, y: previewRect.midY)
                .animation(Animations.captureFlash, value: cameraModel.isCapturing)
        }
    }
    
    // MARK: - Camera Content
    private func cameraContent() -> some View {
        GeometryReader { geo in
            let previewRect = makePreviewRect(in: geo)
            
            ZStack {
                backgroundColor()
                
                ZStack {
                    viewFinder(previewRect)
                    
                    if !cameraModel.showSimpleView {
                        focusBox()
                        focusLock(previewRect)
                    }
                    
                    manualControlOverlays(in: previewRect)
                }
                
                VStack(spacing: 0) {
                    if !cameraModel.showSimpleView {
                        topBarView()
                            .transition(.opacity)
                    }
                    Spacer()
                    
                    bottomBarView()
                }
                
                .allowsHitTesting(!cameraModel.isTimerCountingDown)
                .animation(Animations.easeInOut, value: cameraModel.showSimpleView)
                
                timerCountdownOverlay(in: previewRect)
                captureFlash(previewRect)
            }
        }
    }
    
    // MARK: - App Content
    private func appContent() -> some View {
        ZStack {
            cameraContent()
                .disabled(!cameraModel.hasPhotosAccess)
            
            // MARK: - Photos Permission Denied Overlay
            if !cameraModel.hasPhotosAccess {
                LockedPermissionDeniedView {
                    Task {
                        let activity = NSUserActivity(activityType: "\(BundleIDs.fullBundleID).opencamera")
                        try? await lockedSession.openApplication(for: activity)
                    }
                }
            }
        }
    }
}

struct LockedCaptureView: View {
    @Environment(\.scenePhase) private var scenePhase
    
    let lockedSession: LockedCameraCaptureSession
    
    @State private var cameraModel = LockedCameraModel()
    @State private var selectedControl: ManualControl?
    @State private var hasConfiguredCamera = false
    
    // Haptics
    @State private var hapticTrigger = 0
    @State private var countdownHapticTrigger = 0
    
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
    @State private var isAwaitingSameFacingLensCompletion = false
    
    var body: some View {
        appContent()
            .sensoryFeedback(.impact, trigger: hapticTrigger)
            .sensoryFeedback(.selection, trigger: countdownHapticTrigger)
            .sensoryFeedback(.impact(flexibility: .soft), trigger: cameraModel.tap​Focus​Lock​Haptic​Trigger)
            .onAppear(perform: handleOnAppear)
            .onDisappear(perform: handleOnDisappear)
            .onChange(of: scenePhase, handleOnChangeOfScenePhase)
            .onChange(of: cameraModel.activeLens, handleOnChangeOfActiveLens)
            .onChange(of: cameraModel.lensSwitchCompletionCount, handleOnChangeOfLensSwitchCount)
            .alert(Alerts.error, isPresented: $cameraModel.showError) {
                Button(Alerts.ok, role: .cancel) {}
            } message: {
                Text(cameraModel.errorMessage)
            }
    }
}

// MARK: - On Change functions
extension LockedCaptureView {
    private func triggerShutterFeedback() {
        hapticTrigger += 1
    }
    
    private func capturePhoto() {
        cameraModel.capturePhoto {
            triggerShutterFeedback()
            withAnimation { cameraModel.changeCapturingState(to: true) }
            Task { @MainActor in
                try? await Task.sleep(for: Durations.shutter)
                withAnimation { cameraModel.changeCapturingState(to: false) }
            }
        }
    }
    
    private func triggerCountdownFeedback() {
        countdownHapticTrigger += 1
    }
    
    private func handleOnAppear() {
        cameraModel.onTimerCountdownSecond = triggerCountdownFeedback
        cameraModel.startCaptureOrientationUpdates()
        configureCameraIfPermitted()
    }
    
    private func handleOnDisappear() {
        cameraModel.cancelTimerCountdown()
        cameraModel.onTimerCountdownSecond = nil
        cameraModel.stopSession()
        cameraModel.clearTapPointInteraction(resetDeviceState: false)
        cameraModel.stopCaptureOrientationUpdates()
    }
    
    private func configureCameraIfPermitted() {
        guard cameraModel.hasPhotosAccess else { return }
        
        if hasConfiguredCamera {
            cameraModel.startSession()
        } else {
            hasConfiguredCamera = true
            cameraModel.configure(with: lockedSession)
        }
    }
    
    private func handleOnChangeOfScenePhase(_ oldPhase: ScenePhase, _ newPhase: ScenePhase) {
        guard newPhase == .active else { return }
        
        configureCameraIfPermitted()
        cameraModel.startCaptureOrientationUpdates()
        cameraModel.updateCaptureOrientation()
    }
    
    private func handleOnChangeOfActiveLens(_ oldLens: Lens, _ newLens: Lens) {
        cameraModel.clearTapPointInteraction(resetDeviceState: false)
        // Handle visual "zoom" bump to mask lens hardware switch
        if oldLens.isFront == newLens.isFront {
            // Use a light zoom/blur mask for same-facing lens changes.
            isAwaitingSameFacingLensCompletion = true
            let oldValue = Double(oldLens.label) ?? 1.0
            let newValue = Double(newLens.label) ?? 1.0
            let isZoomIn = newValue > oldValue
            let targetScale: CGFloat = isZoomIn ? 1.035 : 0.965
            withAnimation(.easeIn(duration: 0.15)) {
                visualZoomScale = targetScale
                visualOpacity = 0.62
                visualBlur = 6
            }
        }
    }
    
    private func handleOnChangeOfLensSwitchCount() {
        if isAwaitingSameFacingLensCompletion {
            isAwaitingSameFacingLensCompletion = false
            withAnimation(.easeOut(duration: 0.22)) {
                visualZoomScale = 1.0
                visualBlur = 0
                visualOpacity = 1.0
            }
        }
    }
}
