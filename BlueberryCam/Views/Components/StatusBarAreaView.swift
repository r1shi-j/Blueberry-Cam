import SwiftUI

extension StatusBarAreaView {
    // MARK: - Constants
    private enum Style {
        static let viewHeight: CGFloat = 30
        static let viewHPadding: CGFloat = 30
        static let viewHSpacing: CGFloat = 24
        static let viewVSpacing: CGFloat = 8
        static let overlayButtonsHSpacing: CGFloat = 16
        static let disabledOpacity = 0.3
        static let selectedForeground: Color = .black
        static let selectedBackground: Color = .yellow
        static let horizontalButtonPadding: CGFloat = 8
        static let verticalButtonPadding: CGFloat = 5
    }
    
    private enum Fonts {
        static let button: Font = .system(size: 12, weight: .bold)
        static let text: Font = .system(size: 12, weight: .bold, design: .monospaced)
    }
    
    // MARK: - Properties
    private var chartSymbolName: String {
        "chart.bar.fill"
    }
    
    private var zebrasTitle: String {
        "Z"
    }
    
    private var zebrasForegroundColor: Color {
        cameraModel.showZebraStripes ? .black : Colors.buttonText
    }
    
    private var zebrasBackgroundColor: Color {
        cameraModel.showZebraStripes ? .yellow : Colors.buttonBackground
    }
    
    private var highlightClippingTitle: String {
        "P"
    }
    
    private var clippingForegroundColor: Color {
        cameraModel.showClipping ? .black : Colors.buttonText
    }
    
    private var clippingBackgroundColor: Color {
        cameraModel.showClipping ? .yellow : Colors.buttonBackground
    }
    
    private var shouldShowSmallHistogram: Bool {
        cameraModel.histogramModeSmall != .none
    }
    
    private var shouldShowHideLargeHistogram: Bool {
        cameraModel.histogramModeLarge != .none
    }
    
    // MARK: Subviews
    // MARK: - Small histogram
    private func smallHistogram() -> some View {
        HistogramView(
            mode: cameraModel.histogramModeSmall,
            size: .small,
            lumaData: cameraModel.histogramData,
            redData: cameraModel.redHistogram,
            greenData: cameraModel.greenHistogram,
            blueData: cameraModel.blueHistogram,
            waveformData: cameraModel.waveformData
        )
        .onTapGesture {
            hapticTrigger += 1
            cameraModel.cycleHistogramMode(mode: &cameraModel.histogramModeSmall)
        }
        .onLongPressGesture {
            hapticTriggerR += 1
            cameraModel.hideHistogram(for: .small)
        }
        .transition(.scale(scale: 0.5, anchor: .center).combined(with: .opacity))
    }
    
    // MARK: - Hide large histogram
    private func hideLargeHistogram() -> some View {
        Button {
            hapticTrigger += 1
            cameraModel.hideHistogram(for: .large)
        } label: {
            Image(systemName: chartSymbolName)
                .font(Fonts.button)
                .foregroundStyle(.black)
                .padding(.horizontal, Style.horizontalButtonPadding)
                .padding(.vertical, Style.verticalButtonPadding)
                .background(.yellow)
                .clipShape(.capsule)
        }
        .padding(.leading)
    }
    
    // MARK: - Show histograms
    private func showHistograms() -> some View {
        Button {
            hapticTrigger += 1
            cameraModel.cycleHistogramMode(mode: &cameraModel.histogramModeSmall, size: .small)
            cameraModel.cycleHistogramMode(mode: &cameraModel.histogramModeLarge, size: .large)
        } label: {
            Image(systemName: chartSymbolName)
                .font(Fonts.button)
                .foregroundStyle(Colors.buttonText)
                .padding(.horizontal, Style.horizontalButtonPadding)
                .padding(.vertical, Style.verticalButtonPadding)
                .background(Colors.buttonBackground)
                .clipShape(.capsule)
        }
        .padding(.leading)
    }
    
    // MARK: - Zebra toggle
    private func zebras() -> some View {
        Button {
            hapticTrigger += 1
            cameraModel.toggleZebraStripes()
        } label: {
            Text(zebrasTitle)
                .font(Fonts.text)
                .foregroundStyle(zebrasForegroundColor)
                .padding(.horizontal, Style.horizontalButtonPadding)
                .padding(.vertical, Style.verticalButtonPadding)
                .background(zebrasBackgroundColor)
                .clipShape(.circle)
        }
    }
    
    // MARK: - Highlight clipping toggle
    private func clipping() -> some View {
        Button {
            hapticTrigger += 1
            cameraModel.toggleClipping()
        } label: {
            Text(highlightClippingTitle)
                .font(Fonts.text)
                .foregroundStyle(clippingForegroundColor)
                .padding(.horizontal, Style.horizontalButtonPadding)
                .padding(.vertical, Style.verticalButtonPadding)
                .background(clippingBackgroundColor)
                .clipShape(.circle)
        }
    }
}

// MARK: - View
struct StatusBarAreaView: View {
    @Bindable var cameraModel: CameraModel
    @State private var hapticTrigger = 0
    @State private var hapticTriggerR = 0
    
    var body: some View {
        VStack(spacing: Style.viewVSpacing) {
            if !cameraModel.isLiveFilterPreviewActive, !cameraModel.isDualCameraEnabled {
                HStack(alignment: .center, spacing: Style.viewHSpacing) {
                    ZStack {
                        if shouldShowSmallHistogram {
                            smallHistogram()
                        } else {
                            if shouldShowHideLargeHistogram {
                                hideLargeHistogram()
                            } else {
                                showHistograms()
                            }
                        }
                    }
                    .animation(Animations.bouncy, value: cameraModel.histogramModeSmall)
                    
                    Spacer()
                    
                    HStack(alignment: .center, spacing: Style.overlayButtonsHSpacing) {
                        zebras()
                        clipping()
                    }
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.horizontal, Style.viewHPadding)
        .frame(height: Style.viewHeight)
        .animation(Animations.bouncy, value: cameraModel.isLiveFilterPreviewActive)
        .animation(Animations.bouncy, value: cameraModel.isDualCameraEnabled)
        .sensoryFeedback(.impact, trigger: hapticTrigger)
        .sensoryFeedback(.impact(flexibility: .soft), trigger: hapticTriggerR)
    }
}
