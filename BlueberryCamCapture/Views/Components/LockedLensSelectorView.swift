import SwiftUI

extension LockedLensSelectorView {
    private func lensIconFont(isActive: Bool) -> Font {
        .system(size: 14, weight: isActive ? .bold : .regular , design: .monospaced)
    }
    
    private func lensIconBackground(isActive: Bool) -> Color {
        isActive ? Colors.buttonBackground : .clear
    }
    
    private func lensIconForeground(isActive: Bool) -> Color {
        isActive ? .yellow : Colors.buttonText
    }
}

struct LockedLensSelectorView: View {
    @Bindable var cameraModel: LockedCameraModel
    @State private var hapticTrigger = 0
    
    private let backLenses: [Lens] = [.ultraWide, .wide, .tele2x, .tele4x, .tele8x]
    
    var body: some View {
        HStack(spacing: 6) {
            // MARK: Lens picker
            ForEach(backLenses, id: \.self) { lens in
                let isActive = cameraModel.activeLens == lens
                Button {
                    hapticTrigger += 1
                    cameraModel.switchLens(to: lens)
                } label: {
                    Text(lens.label)
                        .font(lensIconFont(isActive: isActive))
                        .foregroundColor(lensIconForeground(isActive: isActive))
                        .frame(minWidth: 36, minHeight: 36)
                        .background(lensIconBackground(isActive: isActive))
                        .clipShape(.circle)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.black.opacity(0.4))
        .clipShape(.capsule)
        .sensoryFeedback(.impact, trigger: hapticTrigger)
    }
}
