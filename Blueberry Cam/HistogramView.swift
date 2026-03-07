import SwiftUI

struct HistogramView: View {
    let data: [Float]

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                // Background
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.black.opacity(0.5))

                // Bars
                Canvas { context, size in
                    guard !data.isEmpty else { return }

                    let maxVal = data.max() ?? 1
                    let barWidth = size.width / CGFloat(data.count)

                    for (i, val) in data.enumerated() {
                        let normalized = maxVal > 0 ? CGFloat(val / maxVal) : 0
                        let barHeight = normalized * size.height * 0.9
                        let x = CGFloat(i) * barWidth
                        let rect = CGRect(
                            x: x,
                            y: size.height - barHeight,
                            width: max(barWidth - 0.3, 0.5),
                            height: barHeight
                        )

                        // Color gradient: shadows=blue, mids=green, highlights=red
                        let t = CGFloat(i) / CGFloat(data.count)
                        let color: Color
                        if t < 0.33 {
                            color = Color(red: 0.3, green: 0.5, blue: 1.0).opacity(0.8)
                        } else if t < 0.66 {
                            color = Color(red: 0.3, green: 1.0, blue: 0.3).opacity(0.8)
                        } else {
                            color = Color(red: 1.0, green: 0.4, blue: 0.3).opacity(0.8)
                        }

                        context.fill(Path(rect), with: .color(color))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 6))

                // Zone labels
                HStack {
                    Text("SHADOWS")
                    Spacer()
                    Text("MIDS")
                    Spacer()
                    Text("HIGHLIGHTS")
                }
                .font(.system(size: 7, weight: .medium))
                .foregroundColor(.white.opacity(0.35))
                .padding(.horizontal, 4)
                .padding(.bottom, 2)
            }
        }
    }
}
