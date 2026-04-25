import SwiftUI

extension LensSelectorView {
    private var flipLensSymbolName: String {
        "arrow.triangle.2.circlepath.camera"
    }
    
    private func lensIconFont(isActive: Bool) -> Font {
        .system(size: 14, weight: isActive ? .bold : .regular , design: .monospaced)
    }
    
    private func lensIconBackground(isActive: Bool) -> Color {
        isActive ? Colors.buttonBackground : .clear
    }
    
    private func lensIconForeground(isActive: Bool) -> Color {
        isActive ? .yellow : Colors.buttonText
    }
    
    private func lensButton(_ lens: Lens) -> some View {
        Group {
            let isActive = cameraModel.activeLens == lens
            Button {
                hapticTrigger += 1
                cameraModel.switchLens(to: lens)
            } label: {
                Text(lens.label)
                    .font(lensIconFont(isActive: isActive))
                    .foregroundStyle(lensIconForeground(isActive: isActive))
                    .frame(minWidth: 36, minHeight: 36)
                    .background(lensIconBackground(isActive: isActive))
                    .clipShape(.circle)
            }
        }
    }
}

struct LensSelectorView: View {
    @Bindable var cameraModel: CameraModel
    @State private var hapticTrigger = 0
    
    private let frontLenses: [Lens] = [.frontUltraWide, .front]
    private let backLenses: [Lens] = [.ultraWide, .wide, .tele2x, .tele4x, .tele8x]
    
    var body: some View {
        HStack(spacing: 6) {
            // MARK: - Flip camera button — always visible
            Button {
                hapticTrigger += 1
                withAnimation(.bouncy) {
                    cameraModel.toggleSelfie()
                }
            } label: {
                Image(systemName: flipLensSymbolName)
                    .font(.system(size: 16))
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(width: 36, height: 36)
            }
            
            Rectangle()
                .fill(.white.opacity(0.2))
                .frame(width: 1, height: 20)
            
            // MARK: Lens picker
            if cameraModel.activeLens.isFront {
                ForEach(frontLenses, id: \.self) { lens in lensButton(lens) }
            } else {
                ForEach(backLenses, id: \.self) { lens in lensButton(lens) }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.black.opacity(0.4))
        .clipShape(.capsule)
        .sensoryFeedback(.impact, trigger: hapticTrigger)
    }
}
