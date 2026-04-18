import SwiftUI

extension FocusReticleView {
    private var foregroundColor: Color {
        let baseOpacity: CGFloat = lockLabel == nil ? 1.0 : 0.75
        let dimmedOpacity: CGFloat = isDimmed ? 0.45 : 1.0
        return Color.yellow.opacity(baseOpacity * dimmedOpacity)
    }
    
    private var sunIcon: String {
        "sun.max.fill"
    }
}

struct FocusReticleView: View {
    let lockLabel: String?
    let exposureOffset: CGFloat
    let showsExposureHandle: Bool
    let isDimmed: Bool
    
    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(foregroundColor, lineWidth: 2)
                    .frame(width: 78, height: 78)
                
                VStack(spacing: 0) {
                    Rectangle()
                        .fill(foregroundColor)
                        .frame(width: 2, height: 8)
                    Spacer()
                    Rectangle()
                        .fill(foregroundColor)
                        .frame(width: 2, height: 8)
                }
                .frame(height: 78)
                
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(foregroundColor)
                        .frame(width: 8, height: 2)
                    Spacer()
                    Rectangle()
                        .fill(foregroundColor)
                        .frame(width: 8, height: 2)
                }
                .frame(width: 78)
                
                if showsExposureHandle {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(foregroundColor.opacity(0.45))
                        .frame(width: 2, height: 94)
                        .offset(x: 56)
                    
                    Image(systemName: sunIcon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(foregroundColor)
                        .offset(x: 56, y: exposureOffset)
                }
            }
        }
        .allowsHitTesting(false)
    }
}
