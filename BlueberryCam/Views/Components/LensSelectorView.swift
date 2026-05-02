import SwiftUI

extension LensSelectorView {
    // MARK: - Constants
    private enum Style {
        // Diameter of an inactive lens circle
        static let lensDiameterInactive: CGFloat = 48
        
        // Diameter of an active lens circle
        static let lensDiameterActive: CGFloat = 54
        
        // Shortest distance between two lens circles
        static let distanceBetweenLensCircles: CGFloat = 8
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
        // Distance between the active lens and an inactive lens centers
        let radius: CGFloat = (Style.lensDiameterInactive/2)+(Style.lensDiameterActive/2)+Style.distanceBetweenLensCircles
        
        // Distance between two inactive lens centers
        let chord: CGFloat = 2*(Style.lensDiameterInactive/2)+Style.distanceBetweenLensCircles
        
        // Offset for the perfect diagonal with angle π/4 (45º)
        let centerDiagonal = CGSize(width: -((radius)*cos(.pi/4)), height: -((radius)*sin(.pi/4)))
        
        // Switching to return different offsets based on the number of lenses available (excluding the active lens)
        switch count {
            case 1:
                // Only one available lens, return the perfect 45º diagonal position
                return centerDiagonal
                
            case 2:
                // Two other lenses
                let sin2x = 1-((pow(chord,2))/(2*pow(radius,2)))
                let sinx = sin(0.5*asin(sin2x))
                let cosx = cos(0.5*asin(sin2x))
                
                return [
                    CGSize(width: -(radius*cosx), height: -(radius*sinx)),
                    CGSize(width: -(radius*sinx), height: -(radius*cosx)),
                ][index]
                
            case 3:
                // Three other lenses
                let sinxt = (pow(chord,2))/(2*pow(radius,2)) - 1
                let x = asin(sinxt) + .pi/4
                let sinx = sin(x)
                let cosx = cos(x)
                
                return [
                    CGSize(width: -(radius*cosx), height: (radius*sinx)),
                    centerDiagonal,
                    CGSize(width: (radius*sinx), height: -(radius*cosx)),
                ][index]
                
            default:
                // Four other lenses (any other case)
                let sin2x2 = 1-((pow(chord,2))/(2*pow(radius,2)))
                let sinx2 = sin(0.5*asin(sin2x2))
                let cosx2 = cos(0.5*asin(sin2x2))
                let x1 = .pi/2 - 3*asin(sinx2)
                let sinx1 = sin(x1)
                let cosx1 = cos(x1)
                
                return [
                    CGSize(width: -(radius*cosx1), height: (radius*sinx1)),
                    CGSize(width: -(radius*cosx2), height: -(radius*sinx2)),
                    CGSize(width: -(radius*sinx2), height: -(radius*cosx2)),
                    CGSize(width: (radius*sinx1), height: -(radius*cosx1)),
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
                    width: isActive ? Style.lensDiameterActive : Style.lensDiameterInactive,
                    height: isActive ? Style.lensDiameterActive : Style.lensDiameterInactive
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
                    .frame(width: Style.lensDiameterInactive, height: Style.lensDiameterInactive)
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
        GlassEffectContainer(spacing: 8) {
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

#Preview {
    @Previewable @State var cameraModel: CameraModel = CameraModel()
    LensSelectorView(cameraModel: cameraModel, height: 30)
}
