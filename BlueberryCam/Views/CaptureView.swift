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

// MARK: - Functions
extension CaptureView {
    private var closeTitle: String { "Close" }
    private var copiedString: String { "Copied to clipboard!" }
    private var linkSymbolName: String { "link" }
    private var backupURLName: String { "Open Link" }
    private var lensCleaningTitle: String { "Clean the camera lens" }
    private var lensCleaningSymbolName: String { "camera.aperture" }
    private var tapHoldDuration: TimeInterval { 0.7 }
    private var tapMoveTolerance: CGFloat { 18 }
    private var focusReticleSliderXTolerance: CGFloat { 24 }
    private var focusReticleSliderYTolerance: CGFloat { 96 }
    private var appTheme: AppTheme {
        appSettings.selectedTheme
    }
    private var usesThemedReadouts: Bool {
        appSettings.usesAppThemeReadouts && appSettings.selectedThemeID != AppTheme.defaultID
    }
    private var shouldMaskCaptureAspectRatioTransition: Bool {
        cameraModel.isCaptureAspectRatioTransitioning && cameraModel.activeLens.zoomFactor > 1
    }
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
        let aspect: CGFloat = CaptureAspectRatioOption.portrait4x3.widthToHeightRatio
        let previewW = size.width
        let previewH = size.width / aspect
        let previewX: CGFloat = 0
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
    
    private func dualCameraPipRect(in previewSize: CGSize) -> CGRect {
        let pipWidth = previewSize.width * 0.32
        let pipHeight = pipWidth / cameraModel.dualCameraPipAspectRatio
        let inset = previewSize.width * 0.035
        return cameraModel.dualCameraPipPlacement.previewRect(
            in: previewSize,
            pipSize: CGSize(width: pipWidth, height: pipHeight),
            inset: inset
        )
    }
    
    private func isPointInsideDualCameraPip(_ point: CGPoint, previewSize: CGSize) -> Bool {
        guard cameraModel.isDualCameraEnabled,
              !cameraModel.isDetachingPreviewForReconfiguration,
              cameraModel.pipPreviewDeviceUniqueID != nil else { return false }
        return dualCameraPipRect(in: previewSize)
            .insetBy(dx: -8, dy: -8)
            .contains(point)
    }
    
    private func countdownText(for value: Double) -> String {
        let clampedValue = max(value, 0)
        
        if cameraModel.detailedCountdownTimer {
            return clampedValue.formatted(.number.precision(.fractionLength(3)))
        }
        
        return Int(ceil(clampedValue)).formatted()
    }
    
    private func updateBurstFeedbackOverlay(old: String?, message: String?) {
        burstFeedbackFadeTask?.cancel()
        
        if let message {
            displayedBurstFeedbackMessage = message
            withAnimation(Animations.easeInOut) {
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
    
    private func manualControlColor(for control: ManualControl) -> Color {
        if usesThemedReadouts {
            return appTheme.readoutColor
        }
        
        switch control {
            case .ev: return .orange.opacity(0.85)
            case .iso: return .yellow.opacity(0.85)
            case .ss: return .white.opacity(0.85)
            case .f: return .green.opacity(0.85)
            case .wb: return .cyan.opacity(0.85)
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
extension CaptureView {
    // MARK: - Background Color
    private func backgroundColor() -> some View {
        Color.black.ignoresSafeArea()
            .overlay(appTheme.background)
    }
    
    // MARK: - Viewfinder
    private func viewFinder(_ previewRect: CGRect) -> some View {
        let shouldMaskAspectRatioTransition = shouldMaskCaptureAspectRatioTransition
        
        return ZStack {
            CameraPreviewView(session: cameraModel.isDetachingPreviewForReconfiguration ? nil : cameraModel.previewSession,
                              onCaptureBegan: handleShutterPressBegan,
                              onCaptureEnded: handleShutterPressEnded,
                              onCaptureCancelled: handleShutterPressCancelled,
                              proxy: previewProxy,
                              deviceUniqueID: cameraModel.isDualCameraEnabled ? cameraModel.mainPreviewDeviceUniqueID : nil,
                              rotationAngle: cameraModel.mainPreviewRotationAngle,
                              isMirrored: cameraModel.isMainPreviewMirrored,
                              handlesCaptureEvents: cameraModel.canUseShutterButton)
            
            if cameraModel.isLiveFilterPreviewActive {
                FilteredCameraPreviewView(output: cameraModel.liveFilterPreviewOutput)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
            
            if shouldMaskAspectRatioTransition {
                Color.black
                    .opacity(0.22)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .topLeading) {
            if cameraModel.isDualCameraEnabled && !cameraModel.isDetachingPreviewForReconfiguration {
                let pipRect = dualCameraPipRect(in: previewRect.size)
                DualCameraPipPreviewView(cameraModel: cameraModel)
                    .frame(width: pipRect.width)
                    .position(x: pipRect.midX, y: pipRect.midY)
                    .transition(.identity)
            }
        }
        .animation(Animations.easeInOut, value: cameraModel.isLiveFilterPreviewActive)
        .scaleEffect(visualZoomScale * (shouldMaskAspectRatioTransition ? 1.016 : 1.0))
        .rotation3DEffect(
            .degrees(cameraModel.flipRotation),
            axis: (x: 0, y: 1, z: 0),
            perspective: 0.1
        )
        .blur(radius: visualBlur + (shouldMaskAspectRatioTransition ? 10 : 0))
        .opacity(visualOpacity)
        .animation(Animations.viewFinderShown, value: scenePhase)
        .animation(.smooth(duration: 0.08), value: shouldMaskAspectRatioTransition)
        .frame(width: previewRect.width, height: previewRect.height)
        .position(x: previewRect.midX, y: previewRect.midY)
        .allowsHitTesting(!cameraModel.isTimerCountingDown && !cameraModel.shouldShowDualCameraTransitionCurtain)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    guard !cameraModel.isBurstCapturing else { return }
                    if previewInteractionStartPoint == nil {
                        if isPointInsideDualCameraPip(value.startLocation, previewSize: previewRect.size) {
                            isIgnoringPreviewInteraction = true
                            return
                        }
                        beginPreviewInteraction(at: value.startLocation)
                    }
                    guard !isIgnoringPreviewInteraction else { return }
                    updatePreviewInteraction(at: value.location)
                }
                .onEnded { value in
                    guard !cameraModel.isBurstCapturing else {
                        isIgnoringPreviewInteraction = false
                        return
                    }
                    if isIgnoringPreviewInteraction {
                        isIgnoringPreviewInteraction = false
                        return
                    }
                    endPreviewInteraction(at: value.location)
                }
        )
        .simultaneousGesture(
            SpatialTapGesture(count: 2)
                .onEnded { value in
                    guard !isPointInsideDualCameraPip(value.location, previewSize: previewRect.size) else { return }
                    hapticTrigger += 1
                    guard !cameraModel.isDualCameraEnabled else {
                        cameraModel.toggleSelfie()
                        return
                    }
                    withAnimation(Animations.selfieToggled) {
                        cameraModel.toggleSelfie()
                    }
                }
        )
    }
    
    // MARK: - Zebras
    @ViewBuilder
    private func zebras(_ previewRect: CGRect) -> some View {
        if !cameraModel.isLiveFilterPreviewActive, cameraModel.showZebraStripes {
            AnalysisOverlayView(
                mask: cameraModel.zebraMask,
                gridSize: cameraModel.analysisGridSize,
                style: .zebra
            )
            .frame(width: previewRect.width, height: previewRect.height)
            .position(x: previewRect.midX, y: previewRect.midY)
        }
    }
    
    // MARK: - Highlight Clipping
    @ViewBuilder
    private func highlightClipping(_ previewRect: CGRect) -> some View {
        if !cameraModel.isLiveFilterPreviewActive, cameraModel.showClipping {
            AnalysisOverlayView(
                mask: cameraModel.clippingMask,
                gridSize: cameraModel.analysisGridSize,
                style: .clipping
            )
            .frame(width: previewRect.width, height: previewRect.height)
            .position(x: previewRect.midX, y: previewRect.midY)
        }
    }
    
    // MARK: - Focus Peaking
    @ViewBuilder
    private func focusPeaking(_ previewRect: CGRect) -> some View {
        if !cameraModel.isLiveFilterPreviewActive, !cameraModel.isAutoFocus && cameraModel.showFocusPeaking {
            AnalysisOverlayView(
                mask: cameraModel.focusPeakingMask,
                gridSize: cameraModel.analysisGridSize,
                style: .focusPeaking
            )
            .frame(width: previewRect.width, height: previewRect.height)
            .position(x: previewRect.midX, y: previewRect.midY)
        }
    }
    
    // MARK: - Focus Loupe
    @ViewBuilder
    private func focusLoupe(_ previewRect: CGRect) -> some View {
        if !cameraModel.isLiveFilterPreviewActive, !cameraModel.isAutoFocus && cameraModel.showFocusLoupe, cameraModel.loupeImage != nil {
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
    }
    
    // MARK: - Crop frame overlay
    @ViewBuilder
    private func grid(_ previewRect: CGRect) -> some View {
        if cameraModel.shouldShowGrid {
            CropOverlayView(aspectRatio: cameraModel.gridAspectRatio)
                .frame(width: previewRect.width, height: previewRect.height)
                .position(x: previewRect.midX, y: previewRect.midY)
                .animation(.smooth(duration: 0.28), value: cameraModel.gridAspectRatio)
        }
    }
    
    // MARK: - Level / Horizon overlay
    @ViewBuilder
    private func level() -> some View {
        if cameraModel.shouldShowLevel {
            LevelOverlayView(model: levelModel, theme: appTheme)
                .ignoresSafeArea()
        }
    }
    
    // MARK: - QR Code
    @ViewBuilder
    private func qrCode(_ previewRect: CGRect) -> some View {
        ZStack {
            if !cameraModel.isTimerCountingDown, !cameraModel.isBurstCapturing, let url = cameraModel.detectedCodeURL {
                VStack(spacing: 6) {
                    Text(copiedString)
                        .font(.system(size: 10, weight: .bold))
                        .fontWidth(.expanded)
                        .foregroundStyle(appTheme.accent.opacity(0.8))
                        .padding(8)
                        .glassEffect(.regular.tint(.black.opacity(0.3)))
                    Button {
                        openURL(url)
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
                    
                    Button(closeTitle) {
                        cameraModel.ignoreCurrentCode()
                    }
                    .font(.system(size: 14, weight: .bold))
                    .fontWidth(.expanded)
                    .tint(appTheme.accent.opacity(0.8))
                    .buttonStyle(.glassProminent)
                }
                .position(x: previewRect.midX, y: previewRect.midY)
                .transition(.opacity)
            }
        }
        .animation(Animations.bouncy, value: cameraModel.detectedCodeURL)
    }
    
    // MARK: - Lens Cleaning Hint
    @ViewBuilder
    private func lensCleaning(_ previewRect: CGRect) -> some View {
        ZStack {
            if !cameraModel.isTimerCountingDown, !cameraModel.isBurstCapturing, cameraModel.shouldShowLensCleaningHint {
                VStack(spacing: 6) {
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
                    
                    Button(closeTitle) {
                        hapticTriggerR += 1
                        cameraModel.dismissLensCleaningHint()
                    }
                    .font(.system(size: 14, weight: .bold))
                    .fontWidth(.expanded)
                    .tint(appTheme.accent.opacity(0.8))
                    .buttonStyle(.glassProminent)
                }
                .position(x: previewRect.midX, y: previewRect.midY)
                .transition(.opacity)
            }
        }
        .animation(Animations.bouncy, value: cameraModel.shouldShowLensCleaningHint)
    }
    
    // MARK: - Burst Feedback
    @ViewBuilder
    private func burstFeedback(_ previewRect: CGRect) -> some View {
        if let displayedBurstFeedbackMessage {
            Text(displayedBurstFeedbackMessage)
                .font(.system(size: 16, weight: .bold))
                .fontWidth(.expanded)
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .glassEffect(.regular, in: .capsule)
                .position(x: previewRect.midX, y: previewRect.midY)
                .allowsHitTesting(false)
                .opacity(isBurstFeedbackVisible ? 1 : 0)
        }
    }
    
    // MARK: - Tap to focus overlay
    @ViewBuilder
    private func focusBox() -> some View {
        if !cameraModel.isBurstCapturing, cameraModel.isTapFocusIndicatorVisible, let indicatorPoint = cameraModel.tapFocusIndicatorPoint {
            FocusReticleView(
                lockLabel: cameraModel.tapFocusLockLabel,
                exposureOffset: cameraModel.tapFocusIndicatorOffset,
                showsExposureHandle: cameraModel.canAdjustTapPointExposureBias,
                isDimmed: cameraModel.isTapFocusIndicatorDimmed,
                theme: appTheme
            )
            .position(indicatorPoint)
            .transition(.opacity)
        }
    }
    
    // MARK: - Focus lock overlay
    @ViewBuilder
    private func focusLock(_ previewRect: CGRect) -> some View {
        ZStack {
            if !cameraModel.isBurstCapturing, let lockLabel = cameraModel.tapFocusLockLabel {
                Text(lockLabel)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(appTheme.accent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .glassEffect(.regular.tint(.black.opacity(0.35)), in: .capsule)
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
                            range: -CameraModel.minEV...CameraModel.maxEV,
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
                            range: CameraModel.minWhiteBalance...CameraModel.maxWhiteBalance,
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
    
    // MARK: - Dual cam transition cover
    private func dualCameraTransitionCurtain() -> some View {
        Color.black
            .ignoresSafeArea()
            .opacity(cameraModel.shouldShowDualCameraTransitionCurtain ? 1 : 0)
            .allowsHitTesting(cameraModel.shouldShowDualCameraTransitionCurtain)
            .accessibilityHidden(true)
            .animation(.easeOut(duration: 0.08), value: cameraModel.shouldShowDualCameraTransitionCurtain)
    }
    
    // MARK: - Top Bar View
    private func topBarView() -> some View {
        TopBarView(
            cameraModel: cameraModel,
            selectedControl: $selectedControl,
            theme: appTheme,
            usesAppThemeReadouts: usesThemedReadouts
        )
        .offset(y:-10)
    }
    
    // MARK: - Bottom Histogram
    private func bottomHistogram() -> some View {
        ZStack {
            if !cameraModel.isLiveFilterPreviewActive, cameraModel.histogramModeLarge != .none {
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
                .padding(.bottom, 30)
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
        .animation(Animations.bouncy, value: cameraModel.histogramModeLarge)
        .animation(Animations.bouncy, value: cameraModel.isLiveFilterPreviewActive)
    }
    
    // MARK: - Burst Real time Feedback
    @ViewBuilder
    private func burstRealtimeFeedback() -> some View {
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
            .glassEffect(.regular, in: .capsule)
            .allowsHitTesting(false)
            .padding(.top, 16)
            .transition(.opacity)
        }
    }
    
    // MARK: - Bottom Bar View
    private func bottomBarView() -> some View {
        BottomBarView(
            cameraModel: cameraModel,
            theme: appTheme,
            shutterCount: $appSettings.shutterCount,
            shutterCountBurst: $appSettings.shutterCountBurst,
            isForcePressed: forcePressedBinding,
            onShutterPressBegan: handleShutterPressBegan,
            onShutterPressEnded: handleShutterPressEnded,
            onShutterPressCancelled: handleShutterPressCancelled
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
    
    // MARK: - Confetti cannons
    @ViewBuilder
    private func confettiCannons(_ previewRect: CGRect) -> some View {
        ConfettiCannon(
            trigger: $cameraModel.confettiCannonTrigger,
            num: 50,
            confettis: ConfettiObjects.captureLeft,
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
            confettis: ConfettiObjects.captureRight,
            confettiSize: 12,
            rainHeight: 800,
            openingAngle: .degrees(105),
            closingAngle: .degrees(135),
            radius: 350
        )
        .position(x: previewRect.maxX, y: previewRect.maxY - 60)
        .allowsHitTesting(false)
    }
    
    // MARK: - Status bar
    @ViewBuilder
    private func statusBarView() -> some View {
        if !cameraModel.showSimpleView {
            StatusBarAreaView(cameraModel: cameraModel, theme: appTheme)
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
    
    // MARK: - Camera Content
    private func cameraContent() -> some View {
        GeometryReader { geo in
            let previewRect = makePreviewRect(in: geo)
            
            ZStack {
                backgroundColor()
                
                ZStack {
                    viewFinder(previewRect)
                    if !cameraModel.showSimpleView {
                        zebras(previewRect)
                        highlightClipping(previewRect)
                        focusPeaking(previewRect)
                        focusLoupe(previewRect)
                        grid(previewRect)
                        level()
                    }
                    qrCode(previewRect)
                    lensCleaning(previewRect)
                    burstFeedback(previewRect)
                    if !(cameraModel.isTimerCountingDown && cameraModel.shouldHideUIWhileCountingDown) && !$cameraModel.isBurstCapturing.wrappedValue {
                        focusLock(previewRect)
                        focusBox()
                    }
                    manualControlOverlays(in: previewRect)
                }
                .blur(radius: scenePhase != .active ? 20 : 0)
                
                dualCameraTransitionCurtain()
                
                VStack(spacing: 0) {
                    if !cameraModel.showSimpleView {
                        VStack(spacing: 0) {
                            topBarView()
                            Spacer()
                            bottomHistogram()
                        }
                        .transition(.opacity)
                    } else {
                        burstRealtimeFeedback()
                        Spacer()
                    }
                    bottomBarView()
                }
                .allowsHitTesting(!cameraModel.isTimerCountingDown && !cameraModel.shouldShowDualCameraTransitionCurtain)
                .animation(Animations.easeInOut, value: cameraModel.showSimpleView)
                
                timerCountdownOverlay(in: previewRect)
                captureFlash(previewRect)
                confettiCannons(previewRect)
            }
            .ignoresSafeArea(.keyboard)
        }
        .safeAreaInset(edge: .top, content: statusBarView)
    }
    
    // MARK: - App Content
    private func appContent() -> some View {
        ZStack {
            if permissionModel.allGranted {
                cameraContent()
                    .animation(Animations.easeInOut, value: cameraModel.showSimpleView)
                    .animation(Animations.easeInOut, value: cameraModel.isBurstCapturing)
                    .transition(.opacity)
            } else if permissionModel.anyDenied {
                PermissionDeniedView(
                    cameraGranted: permissionModel.cameraStatus == .granted,
                    photosGranted: permissionModel.photosStatus == .granted,
                    requiresPhotos: permissionModel.requiresPhotos
                )
                .transition(.opacity)
            } else {
                Color.black.ignoresSafeArea()
            }
        }
    }
}

struct CaptureView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    
    @Bindable var appSettings: AppSettings
    @Bindable var permissionModel: PermissionModel
    @State private var cameraModel = CameraModel()
    @State private var levelModel = LevelMotionModel()
    @State private var selectedControl: ManualControl?
    @State private var hasConfiguredCamera = false
    
    // Haptics
    @State private var hapticTrigger = 0
    @State private var captureHapticTrigger = 0
    @State private var hardwarePressedOverride = false
    @State private var hapticTriggerR = 0
    @State private var countdownHapticTrigger = 0
    
    // Preview focus
    @State private var previewProxy = PreviewViewProxy()
    @State private var previewInteractionStartPoint: CGPoint?
    @State private var previewInteractionStartTime: Date?
    @State private var previewInteractionDidLock = false
    @State private var previewInteractionIsBiasOnly = false
    @State private var previewInteractionStartBias: Float = 0
    @State private var isIgnoringPreviewInteraction = false
    @State private var previewInteractionHoldTask: Task<Void, Never>?
    
    // Transitions
    @State private var visualZoomScale: CGFloat = 1.0
    @State private var visualBlur: CGFloat = 0
    @State private var visualOpacity: CGFloat = 1.0
    @State private var isAwaitingFacingFlipCompletion = false
    @State private var isAwaitingSameFacingLensCompletion = false
    @State private var displayedBurstFeedbackMessage: String?
    @State private var isBurstFeedbackVisible = false
    @State private var burstFeedbackFadeTask: Task<Void, Never>?
    
    private var forcePressedBinding: Binding<Bool> {
        Binding(
            get: { cameraModel.isBurstCapturing || hardwarePressedOverride },
            set: { _ in }
        )
    }
    
    var body: some View {
        appContent()
            .animation(Animations.permissionsShown, value: permissionModel.allGranted)
            .animation(Animations.permissionsShown, value: permissionModel.anyDenied)
            .sensoryFeedback(.impact, trigger: hapticTrigger)
            .sensoryFeedback(.impact(weight: .heavy), trigger: captureHapticTrigger)
            .sensoryFeedback(.impact(flexibility: .soft), trigger: hapticTriggerR)
            .sensoryFeedback(.selection, trigger: countdownHapticTrigger)
            .sensoryFeedback(.impact(flexibility: .soft), trigger: cameraModel.detectedCodeURL)
            .sensoryFeedback(.impact(flexibility: .soft), trigger: cameraModel.tap​Focus​Lock​Haptic​Trigger)
            .statusBarHidden()
            .onAppear(perform: handleOnAppear)
            .onDisappear(perform: handleOnDisappear)
            .onChange(of: permissionModel.allGranted, handleOnChangeOfPermissionsGranted)
            .onChange(of: cameraModel.shouldShowLevel, handleOnChangeOfShowingLevel)
            .onChange(of: scenePhase, handleOnChangeOfScenePhase)
            .onChange(of: cameraModel.showSimpleView, handleOnChangeOfSimpleView)
            .onChange(of: cameraModel.saveLocation, handleOnChangeOfSaveLocation)
            .onChange(of: cameraModel.burstFeedbackMessage, updateBurstFeedbackOverlay)
            .onChange(of: cameraModel.activeLens, handleOnChangeOfActiveLens)
            .onChange(of: cameraModel.lensSwitchCompletionCount, handleOnChangeOfLensSwitchCount)
            .onReceive(NotificationCenter.default.publisher(for: UIDevice.deviceDidShakeNotification), perform: handleOnRecieveShake)
            .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification), perform: handleOnReceiveOrientationChange)
            .alert(Alerts.error, isPresented: $cameraModel.showError) {
                Button(Alerts.ok, role: .cancel) {}
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
                    appSettings: appSettings,
                    resetToDefaults: cameraModel.resetToDefaults)
            }
    }
}

// MARK: - On Change functions
extension CaptureView {
    private func triggerShutterFeedback() {
        hapticTrigger += 1
    }
    
    private func triggerStandardCaptureFeedback() {
        captureHapticTrigger += 1
        withAnimation { cameraModel.changeCapturingState(to: true) }
        Task { @MainActor in
            try? await Task.sleep(for: Durations.shutter)
            withAnimation { cameraModel.changeCapturingState(to: false) }
        }
    }
    
    private func handleBurstPhotoCaptured() {
        triggerShutterFeedback()
        appSettings.shutterCountBurst += 1
    }
    
    private func handleShutterPressBegan() {
        hardwarePressedOverride = true
        cameraModel.handleShutterPressBegan(onBurstPhotoCaptured: handleBurstPhotoCaptured)
    }
    
    private func handleShutterPressEnded() {
        hardwarePressedOverride = false
        cameraModel.handleShutterPressEnded(
            onCapture: triggerStandardCaptureFeedback,
            onBurstPhotoCaptured: handleBurstPhotoCaptured
        )
    }
    
    private func handleShutterPressCancelled() {
        hardwarePressedOverride = false
        cameraModel.handleShutterPressCancelled()
    }
    
    private func triggerCountdownFeedback() {
        countdownHapticTrigger += 1
    }
    
    private func handleOnAppear() {
        permissionModel.saveLocation = cameraModel.saveLocation
        let appSettings = appSettings
        cameraModel.onStandardPhotoSaved = {
            appSettings.shutterCount += 1
        }
        cameraModel.onTimerCountdownSecond = triggerCountdownFeedback
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        configureCameraIfPermitted()
        syncLevelMotionUpdates()
    }
    
    private func handleOnDisappear() {
        cameraModel.cancelTimerCountdown()
        cameraModel.handleShutterPressCancelled()
        cameraModel.stopBurstCapture()
        cameraModel.onStandardPhotoSaved = nil
        cameraModel.onTimerCountdownSecond = nil
        burstFeedbackFadeTask?.cancel()
        levelModel.setLevelDisplayEnabled(false)
        levelModel.stopUpdates()
        cameraModel.clearTapPointInteraction(resetDeviceState: false)
        UIDevice.current.endGeneratingDeviceOrientationNotifications()
    }
    
    private func configureCameraIfPermitted() {
        guard permissionModel.allGranted else { return }
        
        if hasConfiguredCamera {
            cameraModel.startSession()
        } else {
            hasConfiguredCamera = true
            cameraModel.configure()
        }
    }
    
    private func handleOnChangeOfPermissionsGranted(_: Bool, new: Bool) {
        if new {
            configureCameraIfPermitted()
            cameraModel.confettiCannonTrigger += 1
        } else {
            cameraModel.stopBurstCapture()
            cameraModel.stopSession()
        }
        syncLevelMotionUpdates()
    }
    
    private func handleOnChangeOfSaveLocation(_: SaveLocation, new: SaveLocation) {
        permissionModel.saveLocation = new
        Task { await permissionModel.checkAndRequest() }
    }
    
    private func handleOnChangeOfShowingLevel(_: Bool, _: Bool) {
        syncLevelMotionUpdates()
    }
    
    private func handleOnChangeOfScenePhase(_: ScenePhase, newPhase: ScenePhase) {
        if newPhase == .active {
            cameraModel.validateFilesSaveLocation()
            configureCameraIfPermitted()
            cameraModel.updateCaptureOrientation()
        } else {
            cameraModel.cancelTimerCountdown()
            cameraModel.stopBurstCapture()
            cameraModel.stopSession()
            if newPhase == .background {
                cameraModel.clearIgnoredCodes()
            }
        }
        syncLevelMotionUpdates()
    }
    
    private func handleOnChangeOfSimpleView(_: Bool, _: Bool) {
        syncLevelMotionUpdates()
    }
    
    private func syncLevelMotionUpdates() {
        let shouldRunLevelMotion = permissionModel.allGranted
        && scenePhase == .active
        && cameraModel.shouldShowLevel
        && !cameraModel.showSimpleView
        
        levelModel.setLevelDisplayEnabled(shouldRunLevelMotion)
        if shouldRunLevelMotion {
            levelModel.startUpdates()
        } else {
            levelModel.stopUpdates()
        }
    }
    
    private func handleOnChangeOfActiveLens(_ oldLens: Lens, _ newLens: Lens) {
        cameraModel.clearTapPointInteraction(resetDeviceState: false)
        guard !cameraModel.shouldShowDualCameraTransitionCurtain else {
            isAwaitingSameFacingLensCompletion = false
            isAwaitingFacingFlipCompletion = false
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                visualZoomScale = 1.0
                visualBlur = 0
                visualOpacity = 1.0
                cameraModel.flipRotation = 0
            }
            return
        }
        
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
        } else {
            // Keep the motion continuous; only the de-blur waits for the hardware swap.
            isAwaitingFacingFlipCompletion = true
            let edgeRotation: Double = newLens.isFront ? -82 : 82
            withAnimation(.easeInOut(duration: 0.22)) {
                visualOpacity = 0.06
                visualBlur = 18
                cameraModel.flipRotation = edgeRotation
            }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(220))
                withAnimation(.easeOut(duration: 0.05)) {
                    cameraModel.flipRotation = 0
                }
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
        
        if isAwaitingFacingFlipCompletion {
            isAwaitingFacingFlipCompletion = false
            withAnimation(.easeOut(duration: 0.28)) {
                visualBlur = 0
                visualOpacity = 1.0
            }
        }
    }
    
    private func handleOnRecieveShake(_: Notification) {
        guard !cameraModel.isBurstCapturing else { return }
        if let url = cameraModel.detectedCodeURL {
            openURL(url)
            cameraModel.ignoreCurrentCode()
        }
    }
    
    private func handleOnReceiveOrientationChange(_: Notification) {
        cameraModel.updateCaptureOrientation()
    }
}
