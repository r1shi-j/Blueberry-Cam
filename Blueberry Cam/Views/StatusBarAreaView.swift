import SwiftUI

struct StatusBarAreaView: View {
    @Bindable var cameraModel: CameraModel
    @State private var hapticTrigger = 0
    
    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .center, spacing: 24) {
                // Histogram toggle
                if cameraModel.showHistogram {
                    if cameraModel.histogramSize == .large {
                        // disable button
                        Button {
                            hapticTrigger += 1
                            cameraModel.showHistogram = false
                            cameraModel.histogramSize = .small
                            cameraModel.histogramMode = .luminance
                        } label: {
                            Image(systemName: "chart.bar.fill")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.black)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(Color.yellow)
                                .clipShape(.capsule)
                        }
                    } else {
                        // show small histogram
                        HistogramView(
                            mode: cameraModel.histogramMode,
                            size: cameraModel.histogramSize,
                            lumaData: cameraModel.histogramData,
                            redData: cameraModel.redHistogram,
                            greenData: cameraModel.greenHistogram,
                            blueData: cameraModel.blueHistogram,
                            waveformData: cameraModel.waveformData
                        )
                        .onTapGesture {
                            hapticTrigger += 1
                            cameraModel.cycleHistogramMode()
                        }
                    }
                } else {
                    // enable button
                    Button {
                        hapticTrigger += 1
                        cameraModel.showHistogram = true
                        // maybe force to small
                    } label: {
                        Image(systemName: "chart.bar.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white.opacity(0.7))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Color.white.opacity(0.15))
                            .clipShape(.capsule)
                    }
                }
                
                Spacer()
                
                HStack(alignment: .center, spacing: 12) {
                    // Zebra toggle
                    Button {
                        hapticTrigger += 1
                        cameraModel.toggleZebraStripes()
                    } label: {
                        Text("Z")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(cameraModel.showZebraStripes ? .black : .white.opacity(0.7))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(cameraModel.showZebraStripes ? Color.yellow : Color.white.opacity(0.15))
                            .clipShape(.capsule)
                    }
                    
                    // Highlight clipping toggle
                    Button {
                        hapticTrigger += 1
                        cameraModel.toggleClipping()
                    } label: {
                        Text("P")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(cameraModel.showClipping ? .black : .white.opacity(0.7))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(cameraModel.showClipping ? Color.yellow : Color.white.opacity(0.15))
                            .clipShape(.capsule)
                    }
                }
//                .disabled(true)
            }
        }
        .padding(.horizontal, 30)
        .frame(height: 30)
        .sensoryFeedback(.impact, trigger: hapticTrigger)
    }
}
