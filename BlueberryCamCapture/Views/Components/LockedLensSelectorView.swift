import SwiftUI

extension LockedLensSelectorView {
    private var lensCircleSize: CGFloat { 48 }
    private var activeLensCircleSize: CGFloat { 54 }
    private var d_centres: CGFloat { (lensCircleSize/2)+(activeLensCircleSize/2)+10 }
    
    private var displayedLenses: [Lens] {
        if cameraModel.captureMode == .raw {
            return backLenses.filter(\.preservesRawCaptureMode)
        }
        
        if cameraModel.isHighResolutionSelected {
            return backLenses.filter(\.preservesHighResolutionCapture)
        }
        
        return backLenses
    }
    
    private var alternateLenses: [Lens] {
        displayedLenses.filter { $0 != cameraModel.activeLens }
    }
    
    private func lensOffset(at index: Int, count: Int) -> CGSize {
        switch count {
            case 1:
                CGSize(width: -((d_centres)*cos(.pi/4)), height: -((d_centres)*sin(.pi/4)))
            case 2:
                [
                    CGSize(width: -((d_centres)*cos(.pi/12)), height: -((d_centres)*sin(.pi/12))),
                    CGSize(width: -((d_centres)*sin(.pi/12)), height: -((d_centres)*cos(.pi/12))),
                ][index]
            case 3:
                [
                    CGSize(width: -((d_centres)*cos(.pi/16)), height: ((d_centres)*sin(.pi/16))),
                    CGSize(width: -((d_centres)*cos(.pi/4)), height: -((d_centres)*sin(.pi/4))),
                    CGSize(width: ((d_centres)*sin(.pi/16)), height: -((d_centres)*cos(.pi/16))),
                ][index]
            case 4:
                [
                    CGSize(width: -((d_centres)*cos(.pi/6)), height: ((d_centres)*sin(.pi/6))),
                    CGSize(width: -((d_centres)*cos(.pi/9)), height: -((d_centres)*sin(.pi/9))),
                    CGSize(width: -((d_centres)*sin(.pi/9)), height: -((d_centres)*cos(.pi/9))),
                    CGSize(width: ((d_centres)*sin(.pi/6)), height: -((d_centres)*cos(.pi/6))),
                ][index]
            default:
                [
                    CGSize(width: -((d_centres)*cos(.pi/6)), height: ((d_centres)*sin(.pi/6))),
                    CGSize(width: -((d_centres)*cos(.pi/9)), height: -((d_centres)*sin(.pi/9))),
                    CGSize(width: -((d_centres)*sin(.pi/9)), height: -((d_centres)*cos(.pi/9))),
                    CGSize(width: ((d_centres)*sin(.pi/6)), height: -((d_centres)*cos(.pi/6))),
                ][min(index, 3)]
        }
    }
    
    private func lensButtonTitle(for lens: Lens) -> String {
        "\(lens.label)x"
    }
    
    private func switchToLens(_ lens: Lens) {
        hapticTrigger += 1
        cameraModel.switchLens(to: lens)
        withAnimation(.bouncy) {
            isExpanded = false
        }
    }
    
    private func toggleExpanded() {
        hapticTrigger += 1
        withAnimation(.bouncy) {
            isExpanded.toggle()
        }
    }
    
    private func lensButton(_ lens: Lens, isActive: Bool) -> some View {
        Button {
            if isActive {
                toggleExpanded()
            } else {
                switchToLens(lens)
            }
        } label: {
            Text(lens.label)
                .font(.system(.callout, design: .monospaced))
                .bold(isActive)
                .foregroundStyle(isActive ? .black : .white.opacity(0.86))
                .frame(
                    width: isActive ? activeLensCircleSize : lensCircleSize,
                    height: isActive ? activeLensCircleSize : lensCircleSize
                )
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(lensButtonTitle(for: lens))
        .glassEffect(
            .regular
                .interactive()
                .tint(isActive ? .yellow.opacity(0.86) : .black.mix(with: .white, by: 0.24)),
            in: .circle
        )
    }
    
    @ViewBuilder
    private var expandedLensButtons: some View {
        let lenses = alternateLenses
        ForEach(lenses.enumerated(), id: \.element) { index, lens in
            Button {
                switchToLens(lens)
            } label: {
                Text(lens.label)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.86))
                    .frame(width: lensCircleSize, height: lensCircleSize)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(lensButtonTitle(for: lens))
            .glassEffect(
                .regular
                    .interactive()
                    .tint(.black.mix(with: .white, by: 0.24)),
                in: .circle
            )
            .offset(lensOffset(at: index, count: lenses.count))
            .transition(.scale(scale: 0.72).combined(with: .opacity))
        }
    }
}

struct LockedLensSelectorView: View {
    @Bindable var cameraModel: LockedCameraModel
    @State private var isExpanded = false
    @State private var hapticTrigger = 0
    
    private let backLenses: [Lens] = [.ultraWide, .wide, .tele2x, .tele4x, .tele8x]
    
    var body: some View {
        GlassEffectContainer(spacing: 12) {
            ZStack {
                if isExpanded {
                    expandedLensButtons
                }
                
                lensButton(cameraModel.activeLens, isActive: true)
            }
        }
        .frame(width: 82, height: 82)
        .animation(.bouncy, value: isExpanded)
        .animation(.bouncy, value: cameraModel.activeLens)
        .sensoryFeedback(.impact, trigger: hapticTrigger)
    }
}
