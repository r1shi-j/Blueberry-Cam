import SwiftUI

extension LensSelectorView {
    // MARK: - Constants
    private enum Style {
        static let lensCircleSize: CGFloat = 48
        static let activeLensCircleSize: CGFloat = 54
        static let d_centres: CGFloat = (lensCircleSize/2)+(activeLensCircleSize/2)+10
    }
    
    // MARK: - Properties
    private var displayedLenses: [Lens] {
        let lenses = cameraModel.activeLens.isFront ? frontLenses : backLenses
        
        if cameraModel.captureMode == .raw {
            return lenses.filter(\.preservesRawCaptureMode)
        }
        
        if cameraModel.isHighResolutionSelected, !cameraModel.activeLens.isFront {
            return lenses.filter(\.preservesHighResolutionCapture)
        }
        
        return lenses
    }
    
    private var alternateLenses: [Lens] {
        displayedLenses.filter { $0 != cameraModel.activeLens }
    }
    
    private func lensOffset(at index: Int, count: Int) -> CGSize {
        let d_centres = Style.d_centres
        return switch count {
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
        withAnimation(Animations.bouncy) {
            isExpanded = false
        }
    }
    
    private func toggleExpanded() {
        hapticTrigger += 1
        withAnimation(Animations.bouncy) {
            isExpanded.toggle()
        }
    }
    
    // MARK: - Subviews
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
                    width: isActive ? Style.activeLensCircleSize : Style.lensCircleSize,
                    height: isActive ? Style.activeLensCircleSize : Style.lensCircleSize
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
                    .frame(width: Style.lensCircleSize, height: Style.lensCircleSize)
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

// MARK: - View
struct LensSelectorView: View {
    @Bindable var cameraModel: CameraModel
    let height: CGFloat
    
    @State private var isExpanded = false
    @State private var hapticTrigger = 0
    
    private let frontLenses: [Lens] = [.frontUltraWide, .front]
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
        .frame(width: height, height: height)
        .animation(Animations.bouncy, value: isExpanded)
        .animation(Animations.bouncy, value: cameraModel.activeLens)
        .sensoryFeedback(.impact, trigger: hapticTrigger)
    }
}
