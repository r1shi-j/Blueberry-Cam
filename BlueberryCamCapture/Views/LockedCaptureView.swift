import LockedCameraCapture
internal import Photos
import SwiftUI

extension LockedCaptureView {
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

struct LockedCaptureView: View {
    let lockedSession: LockedCameraCaptureSession
    
    @State private var cameraModel = LockedCameraModel()
    @State private var levelModel = LockedLevelMotionModel()
    @State private var selectedControl: ManualControl?
    
    // Haptics
    @State private var hapticTrigger = 0
    
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
    
    private var cameraContent: some View {
        GeometryReader { geo in
            let previewRect = makePreviewRect(in: geo)
            
            ZStack {
                Color.black.ignoresSafeArea()
                
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
                
                // MARK: - Focus lock overlay
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
                .animation(.bouncy, value: cameraModel.tapFocusLockLabel)
                
                // MARK: - UI Overlays
                VStack(spacing: 0) {
                    if !cameraModel.showSimpleView {
                        VStack(spacing: 0) {
                            LockedTopBarView(cameraModel: cameraModel, selectedControl: $selectedControl)
                                .offset(y:-2)
                            
                            Spacer()
                            
                            if let selectedControl {
                                LockedManualControlsView(cameraModel: cameraModel, control: selectedControl)
                                    .padding(.bottom, 8)
                            }
                            
                            ZStack {
                                LockedLensSelectorView(cameraModel: cameraModel)
                                    .padding(.bottom, 30)
                            }
                            .animation(.bouncy, value: cameraModel.activeLens)
                            
                            LockedBottomBarView(cameraModel: cameraModel, lockedSession: lockedSession)
                                .padding(.bottom, 30)
                        }
                        .transition(.opacity)
                    }
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
            }
        }
    }
    
    var body: some View {
        ZStack {
            cameraContent
                .disabled(!cameraModel.hasPhotosAccess)
            
            // MARK: - Photos Permission Denied Overlay
            if !cameraModel.hasPhotosAccess {
                ZStack {
                    Color.black.opacity(0.85).ignoresSafeArea()
                    
                    VStack(spacing: 20) {
                        Image(systemName: "photo.badge.exclamationmark")
                            .font(.system(size: 48))
                            .foregroundStyle(.white)
                        
                        Text("Photos Access Required")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.white)
                        
                        Text("Blueberry Cam needs permission to save photos.")
                            .font(.system(size: 14))
                            .foregroundStyle(.white.opacity(0.7))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                        
                        Button {
                            Task {
                                let activity = NSUserActivity(activityType: "\(BundleIDs.fullBundleID).opencamera")
                                try? await lockedSession.openApplication(for: activity)
                            }
                        } label: {
                            Text("Open App to Grant Access")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.black)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 12)
                                .background(.white)
                                .clipShape(.capsule)
                        }
                    }
                }
                .transition(.opacity)
            }
        }
        .environment(\.scenePhase, .active)
        .sensoryFeedback(.impact, trigger: hapticTrigger)
        .sensoryFeedback(.impact(flexibility: .soft), trigger: cameraModel.tap​Focus​Lock​Haptic​Trigger)
        .onAppear {
            cameraModel.configure(with: lockedSession)
            levelModel.startUpdates()
            
            // Pass gravity updates to camera model
            levelModel.onGravityUpdate = { gx, gy, gz in
                cameraModel.lastGravity = (gx, gy, gz)
            }
        }
        .onDisappear {
            levelModel.stopUpdates()
            cameraModel.clearTapPointInteraction(resetDeviceState: false)
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
        }
        .alert(errorString, isPresented: $cameraModel.showError) {
            Button(okButtonString, role: .cancel) {}
        } message: {
            Text(cameraModel.errorMessage)
        }
    }
}
