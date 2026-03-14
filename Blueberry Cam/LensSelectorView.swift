import SwiftUI

struct LensSelectorView: View {
    @Bindable var cameraModel: CameraModel
    @State private var count = 0
    @State private var count2 = 0
    
    private let frontLenses: [Lens] = [.frontUltraWide, .front]
    private let backLenses: [Lens] = [.ultraWide, .wide, .tele2x, .tele4x, .tele8x]
    
    var body: some View {
        HStack(spacing: 6) {
            // Flip camera button — always visible
            Button {
                let target: Lens = cameraModel.activeLens.isFront ? .wide : .front
                cameraModel.switchLens(to: target)
                count += 1
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath.camera")
                    .font(.system(size: 16))
                    .foregroundColor(.white.opacity(0.8))
                    .frame(width: 36, height: 36)
            }
            .sensoryFeedback(.selection, trigger: count)
            
            Rectangle()
                .fill(Color.white.opacity(0.2))
                .frame(width: 1, height: 20)
            
            if cameraModel.activeLens.isFront {
                ForEach(frontLenses, id: \.self) { lens in lensButton(lens) }
            } else {
                ForEach(backLenses, id: \.self) { lens in lensButton(lens) }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.4))
        .clipShape(.capsule)
    }
    
    @ViewBuilder
    private func lensButton(_ lens: Lens) -> some View {
        let isActive = cameraModel.activeLens == lens
        Button {
            cameraModel.switchLens(to: lens)
            count2 += 1
        } label: {
            Text(lens.label)
                .font(.system(size: 14, weight: isActive ? .bold : .regular, design: .monospaced))
                .foregroundColor(isActive ? .yellow : .white.opacity(0.7))
                .frame(minWidth: 36, minHeight: 36)
                .background(isActive ? Color.white.opacity(0.15) : Color.clear)
                .clipShape(.circle)
        }
        .sensoryFeedback(.selection, trigger: count2)
    }
}
