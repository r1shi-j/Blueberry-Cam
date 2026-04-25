import SwiftUI

extension CameraModel {
    fileprivate var shouldShowSmallHistogram: Bool {
        histogramModeSmall != .none
    }
    
    fileprivate var shouldShowHideLargeHistogram: Bool {
        histogramModeLarge != .none
    }
}

extension StatusBarAreaView {
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
}

struct StatusBarAreaView: View {
    @Bindable var cameraModel: CameraModel
    @State private var hapticTrigger = 0
    @State private var hapticTriggerR = 0
    
    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .center, spacing: 24) {
                // MARK: - Histogram toggle
                ZStack {
                    if cameraModel.shouldShowSmallHistogram {
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
                    } else {
                        if cameraModel.shouldShowHideLargeHistogram {
                            Button {
                                hapticTrigger += 1
                                cameraModel.hideHistogram(for: .large)
                            } label: {
                                Image(systemName: chartSymbolName)
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(.black)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 5)
                                    .background(.yellow)
                                    .clipShape(.capsule)
                            }
                            .padding(.leading)
                        } else {
                            Button {
                                hapticTrigger += 1
                                cameraModel.cycleHistogramMode(mode: &cameraModel.histogramModeSmall, size: .small)
                                cameraModel.cycleHistogramMode(mode: &cameraModel.histogramModeLarge, size: .large)
                            } label: {
                                Image(systemName: chartSymbolName)
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(Colors.buttonText)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 5)
                                    .background(Colors.buttonBackground)
                                    .clipShape(.capsule)
                            }
                            .padding(.leading)
                        }
                    }
                }
                .animation(.bouncy, value: cameraModel.histogramModeSmall)
                
                Spacer()
                
                HStack(alignment: .center, spacing: 12) {
                    // MARK: - Zebra toggle
                    Button {
                        hapticTrigger += 1
                        cameraModel.toggleZebraStripes()
                    } label: {
                        Text(zebrasTitle)
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundStyle(zebrasForegroundColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(zebrasBackgroundColor)
                            .clipShape(.capsule)
                    }
                    
                    // MARK: - Highlight clipping toggle
                    Button {
                        hapticTrigger += 1
                        cameraModel.toggleClipping()
                    } label: {
                        Text(highlightClippingTitle)
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundStyle(clippingForegroundColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(clippingBackgroundColor)
                            .clipShape(.capsule)
                    }
                }
            }
        }
        .padding(.horizontal, 30)
        .frame(height: 30)
        .sensoryFeedback(.impact, trigger: hapticTrigger)
        .sensoryFeedback(.impact(flexibility: .soft), trigger: hapticTriggerR)
    }
}
