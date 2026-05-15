import LockedCameraCapture
import SwiftUI

extension LockedBottomBarView {
    // MARK: - Constants
    private enum Style {
        static let buttonHeight: CGFloat = 82
    }
    
    // MARK: - Properties
    private var openString: String {
        "Open"
    }
    
    private func openMainApp() {
        Task {
            let activity = NSUserActivity(activityType: "\(BundleIDs.fullBundleID).opencamera")
            try? await lockedSession.openApplication(for: activity)
        }
    }
    
    private var shutterTint: Color {
        cameraModel.captureMode.isRawLike ? .blue.mix(with: .mint, by: 0.5).opacity(0.4) : .white.opacity(0.2)
    }
    
    // MARK: Subviews
    // MARK: - Main app shortcut
    private func mainAppShortcut() -> some View {
        Button(action: openMainApp) {
            Image(BundleIDs.appSymbolName)
                .font(.system(size: 20))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.black, .blue, .green)
                .padding()
                .clipShape(.circle)
                .glassEffect(.regular.interactive().tint(.white.mix(with: .teal, by: 0.4)), in: .circle)
        }
        .frame(height: 82)
        .frame(maxWidth: .infinity)
        .overlay {
            Text(openString.uppercased())
                .font(.caption)
                .fontWidth(.expanded)
                .foregroundStyle(.white.opacity(0.6))
                .offset(y: 41)
        }
    }
    
    // MARK: - Shutter button
    private func shutterButton() -> some View {
        ShutterButton(
            tint: shutterTint,
            height: Style.buttonHeight,
            onPressBegan: {},
            onPressEnded: capturePhoto,
            onPressCancelled: {}
        )
    }
    
    private func capturePhoto() {
        cameraModel.capturePhoto {
            onShutterFeedback()
            withAnimation { cameraModel.changeCapturingState(to: true) }
            Task { @MainActor in
                try? await Task.sleep(for: Durations.shutter)
                withAnimation { cameraModel.changeCapturingState(to: false) }
            }
        }
    }
    
    // MARK: - Lens picker
    private func lensPicker() -> some View {
        LockedLensSelectorView(cameraModel: cameraModel, height: Style.buttonHeight)
            .frame(height: Style.buttonHeight)
            .frame(maxWidth: .infinity)
            .transition(.opacity)
    }
}

// MARK: - View
struct LockedBottomBarView: View {
    @Bindable var cameraModel: LockedCameraModel
    let lockedSession: LockedCameraCaptureSession
    let onShutterFeedback: () -> Void
    
    var body: some View {
        VStack {
            HStack(alignment: .center, spacing: 0) {
                if !cameraModel.showSimpleView {
                    mainAppShortcut()
                }
                if !(cameraModel.isTimerCountingDown && cameraModel.shouldHideUIWhileCountingDown) {
                    shutterButton()
                }
                if !cameraModel.showSimpleView {
                    lensPicker()
                }
            }
        }
        .animation(Animations.easeInOut, value: cameraModel.showSimpleView)
    }
}
