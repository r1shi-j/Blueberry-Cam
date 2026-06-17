import SwiftUI

extension BottomBarView {
    // MARK: - Constants
    private enum Style {
        static let buttonHeight: CGFloat = 82
        static let counterForegroundStyle: Color = .white.opacity(0.6)
    }
    
    // MARK: - Properties
    private var shortcutLinkSymbolName: String {
        if cameraModel.saveLocation == .files {
            return "folder"
        }
        return "photo.on.rectangle.angled.fill"
    }
    
    private func openShortcutLocation() {
        if cameraModel.saveLocation == .files {
            if let folderURL = cameraModel.currentFileSaveLocationURL() {
                let path = folderURL.path
                if let encodedPath = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
                   let filesAppURL = URL(string: "shareddocuments://\(encodedPath)") {
                    openURL(filesAppURL)
                } else if let filesURL = URL(string: "shareddocuments://") {
                    openURL(filesURL)
                }
            } else if let filesURL = URL(string: "shareddocuments://") {
                openURL(filesURL)
            }
        } else {
            guard let url = URL(string: "photos-redirect://") else { return }
            openURL(url)
        }
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
        if cameraModel.isBurstModeEnabled { return theme.shutterBurst }
        
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
    // MARK: - Media shortcut
    private func mediaShortcut() -> some View {
        Button(action: openShortcutLocation) {
            Image(systemName: shortcutLinkSymbolName)
                .font(.system(size: 18))
                .symbolRenderingMode(.hierarchical)
                .tint(.white.opacity(0.8))
                .padding()
                .clipShape(.circle)
                .glassEffect(.regular.interactive().tint(.black.mix(with: theme.accent, by: 0.3)), in: .circle)
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
            isProcessing: cameraModel.isProcessingPhoto && !cameraModel.isBurstCapturing,
            onPressBegan: onShutterPressBegan,
            onPressEnded: onShutterPressEnded,
            onPressCancelled: onShutterPressCancelled,
            isForcePressed: $isForcePressed
        )
    }
    
    // MARK: - Lens picker
    private func lensPicker() -> some View {
        LensSelectorView(cameraModel: cameraModel, theme: theme, height: Style.buttonHeight)
            .frame(maxWidth: .infinity)
            .transition(.opacity)
    }
}

// MARK: - View
struct BottomBarView: View {
    @Environment(\.openURL) private var openURL
    
    @Bindable var cameraModel: CameraModel
    let theme: AppTheme
    @Binding var shutterCount: Int
    @Binding var shutterCountBurst: Int
    @Binding var isForcePressed: Bool
    let onShutterPressBegan: () -> Void
    let onShutterPressEnded: () -> Void
    let onShutterPressCancelled: () -> Void
    
    var body: some View {
        VStack {
            HStack(alignment: .center, spacing: 0) {
                if !cameraModel.showSimpleView {
                    mediaShortcut()
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
