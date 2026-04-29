import SwiftUI

extension CameraModel {
    fileprivate var shutterTint: Color {
        if isBurstCapturing { return .yellow.mix(with: .orange, by: 0.3).opacity(0.6) }
        if isBurstModeEnabled { return .yellow.opacity(0.8) }
        return captureMode == .raw ? .blue.mix(with: .mint, by: 0.5).opacity(0.4) : .white.opacity(0.2)
    }
}

// MARK: Properties
extension BottomBarView {
    private var photosLinkSymbolName: String {
        "photo.on.rectangle.angled.fill"
    }
    
    private func openPhotosApp() {
        guard let url = URL(string: "photos-redirect://") else { return }
        UIApplication.shared.open(url)
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
}

// MARK: Subviews
extension BottomBarView {
    // MARK: - Photos shortcut
    @ViewBuilder
    private func photosShortcut() -> some View {
        if !cameraModel.showSimpleView {
            Button(action: openPhotosApp) {
                Image(systemName: photosLinkSymbolName)
                    .font(.system(size: 20))
                    .symbolRenderingMode(.hierarchical)
                    .tint(.primary)
                    .padding()
                    .clipShape(.circle)
                    .glassEffect(.regular.interactive().tint(.black.mix(with: .white, by: 0.2)), in: .circle)
            }
            .frame(height: 82)
            .frame(maxWidth: .infinity)
            .overlay {
                Text(displayedShutterCountLabel)
                    .font(.caption)
                    .fontWidth(.expanded)
                    .foregroundStyle(.white.opacity(0.6))
                    .contentTransition(.numericText())
                    .offset(y: 41)
            }
            .transition(.opacity)
        }
    }
    
    // MARK: - Shutter button
    @ViewBuilder
    private func shutterButton() -> some View {
        if !(cameraModel.isTimerCountingDown && cameraModel.shouldHideUIWhileCountingDown) {
            ZStack {
                Circle()
                    .frame(width: 82, height: 82)
                    .glassEffect(.regular.tint(cameraModel.shutterTint).interactive())
                Button {
                    onShutterFeedback()
                    cameraModel.handleShutterButton {
                        withAnimation { cameraModel.changeCapturingState(to: true) }
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(150))
                            withAnimation { cameraModel.changeCapturingState(to: false) }
                        }
                    } onBurstPhotoCaptured: {
                        onShutterFeedback()
                        shutterCountBurst += 1
                    }
                } label: {
                    Circle()
                        .fill(.white)
                        .frame(width: 69, height: 69)
                }
                .glassEffect(.regular.interactive())
            }
            .frame(maxWidth: .infinity)
            .transition(.opacity)
        }
    }
    
    // MARK: - Lens picker
    @ViewBuilder
    private func lensPicker() -> some View {
        if !cameraModel.showSimpleView {
            LensSelectorView(cameraModel: cameraModel)
                .frame(height: 82)
                .frame(maxWidth: .infinity)
                .transition(.opacity)
        }
    }
}

struct BottomBarView: View {
    @Bindable var cameraModel: CameraModel
    @Binding var shutterCount: Int
    @Binding var shutterCountBurst: Int
    let onShutterFeedback: () -> Void
    
    var body: some View {
        VStack() {
            HStack(alignment: .center, spacing: 0) {
                photosShortcut()
                shutterButton()
                lensPicker()
            }
        }
        .animation(.easeInOut(duration: 0.2), value: cameraModel.showSimpleView)
    }
}
