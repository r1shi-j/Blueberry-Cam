import SwiftUI

extension BottomBarView {
    // MARK: - Constants
    private enum Style {
        static let buttonHeight: CGFloat = 82
        static let counterForegroundStyle: Color = .white.opacity(0.6)
    }
    
    // MARK: - Properties
    private var photosLinkSymbolName: String {
        "photo.on.rectangle.angled.fill"
    }
    
    private func openPhotosApp() {
        guard let url = URL(string: "photos-redirect://") else { return }
        openURL(url)
    }
    
    private var isShowingBurstCount: Bool {
        cameraModel.isBurstModeEnabled
    }
    
    private var displayedShutterCount: Int {
        isShowingBurstCount ? shutterCountBurst : shutterCount
    }
    
    private var displayedShutterCountLabel: String {
        displayedShutterCount.formatted()
    }
    
    private var shutterTint: Color {
        if cameraModel.isBurstCapturing { return .yellow.mix(with: .orange, by: 0.2).opacity(0.6) }
        if cameraModel.isBurstModeEnabled { return .yellow.opacity(0.8) }
        
        switch cameraModel.captureMode {
            case .raw:
                return .blue.mix(with: .mint, by: 0.5).opacity(0.4)
            case .proRaw:
                return .purple.mix(with: .pink, by: 0.35).opacity(0.45)
            case .heif, .jpeg:
                return .white.opacity(0.2)
        }
    }
    
    // MARK: Subviews
    // MARK: - Photos shortcut
    private func photosShortcut() -> some View {
        Button(action: openPhotosApp) {
            Image(systemName: photosLinkSymbolName)
                .font(.system(size: 20))
                .symbolRenderingMode(.hierarchical)
                .tint(.primary)
                .padding()
                .clipShape(.circle)
                .glassEffect(.regular.interactive().tint(.black.mix(with: .white, by: 0.2)), in: .circle)
        }
        .frame(height: Style.buttonHeight)
        .frame(maxWidth: .infinity)
        .overlay {
            Text(displayedShutterCountLabel)
                .font(.caption)
                .fontWidth(.expanded)
                .foregroundStyle(Style.counterForegroundStyle)
                .contentTransition(.numericText())
                .offset(y: Style.buttonHeight / 2)
        }
        .transition(.opacity)
    }
    
    // MARK: - Shutter button
    private func shutterButton() -> some View {
        ShutterButton(
            tint: shutterTint,
            height: Style.buttonHeight,
            isEnabled: cameraModel.canUseShutterButton,
            onPressBegan: onShutterPressBegan,
            onPressEnded: onShutterPressEnded,
            onPressCancelled: onShutterPressCancelled
        )
    }
    
    // MARK: - Lens picker
    private func lensPicker() -> some View {
        LensSelectorView(cameraModel: cameraModel, height: Style.buttonHeight)
            .frame(height: Style.buttonHeight)
            .frame(maxWidth: .infinity)
            .transition(.opacity)
    }
}

// MARK: - View
struct BottomBarView: View {
    @Environment(\.openURL) private var openURL
    
    @Bindable var cameraModel: CameraModel
    @Binding var shutterCount: Int
    @Binding var shutterCountBurst: Int
    let onShutterPressBegan: () -> Void
    let onShutterPressEnded: () -> Void
    let onShutterPressCancelled: () -> Void
    
    var body: some View {
        VStack {
            HStack(alignment: .center, spacing: 0) {
                if !cameraModel.showSimpleView {
                    photosShortcut()
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
