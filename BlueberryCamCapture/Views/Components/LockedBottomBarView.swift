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
        switch cameraModel.captureMode {
            case .raw:
                return theme.shutterRaw
            case .proRaw:
                return theme.shutterProRaw
            case .heif, .jpeg:
                return theme.shutterProcessed
        }
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
            isProcessing: cameraModel.isProcessingPhoto,
            onPressBegan: {},
            onPressEnded: onShutterPressEnded,
            onPressCancelled: {}
        )
    }
    
    // MARK: - Lens picker
    private func lensPicker() -> some View {
        LockedLensSelectorView(cameraModel: cameraModel, theme: theme, height: Style.buttonHeight)
            .frame(height: Style.buttonHeight)
            .frame(maxWidth: .infinity)
            .transition(.opacity)
    }
}

// MARK: - View
struct LockedBottomBarView: View {
    @Bindable var cameraModel: LockedCameraModel
    let lockedSession: LockedCameraCaptureSession
    let theme: AppTheme
    let onShutterPressEnded: () -> Void
    
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
