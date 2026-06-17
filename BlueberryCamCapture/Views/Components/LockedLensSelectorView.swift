import SwiftUI

extension LockedLensSelectorView {
    // MARK: - Constants
    private enum Style {
        // Diameter of an inactive lens circle
        static let lensDiameterInactive: CGFloat = 48
        
        // Diameter of an active lens circle
        static let lensDiameterActive: CGFloat = 54
        
        // Shortest distance between two lens circles
        static let distanceBetweenLensCircles: CGFloat = 8
        
        static let dragSelectionHitPadding: CGFloat = 12
        static let dragSelectionDelay: Duration = .milliseconds(250)
    }
    
    private static let lensSelectorCoordinateSpace = "LockedLensSelectorViewCoordinateSpace"
    
    // MARK: - Properties
    private var displayedLenses: [Lens] {
        cameraModel.availableLensOptions
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
        dragHighlightedLens = nil
        cameraModel.switchLens(to: lens)
        withAnimation(Animations.bouncy) {
            isExpanded = false
        }
    }
    
    private func toggleExpanded() {
        hapticTrigger += 1
        dragHighlightedLens = nil
        withAnimation(Animations.bouncy) {
            isExpanded.toggle()
        }
    }
    
    private var activeLensPressGesture: some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.lensSelectorCoordinateSpace))
            .onChanged(handleActiveLensPressChanged)
            .onEnded(handleActiveLensPressEnded)
    }
    
    private func handleActiveLensPressChanged(_ value: DragGesture.Value) {
        activeLensPressLocation = value.location
        
        if !isPressingActiveLens {
            beginActiveLensPress()
        }
        
        if isDragSelectingLens {
            updateDragHighlightedLens(at: value.location)
        }
    }
    
    private func handleActiveLensPressEnded(_ value: DragGesture.Value) {
        activeLensPressLocation = value.location
        longPressTask?.cancel()
        longPressTask = nil
        
        if isDragSelectingLens {
            updateDragHighlightedLens(at: value.location)
            let selectedLens = dragHighlightedLens
            
            isDragSelectingLens = false
            isPressingActiveLens = false
            activeLensPressLocation = nil
            dragHighlightedLens = nil
            
            guard let selectedLens else {
                hapticTrigger += 1
                withAnimation(Animations.bouncy) {
                    isExpanded = false
                }
                return
            }
            switchToLens(selectedLens)
        } else {
            isPressingActiveLens = false
            activeLensPressLocation = nil
            toggleExpanded()
        }
    }
    
    private func beginActiveLensPress() {
        isPressingActiveLens = true
        dragHighlightedLens = nil
        longPressTask?.cancel()
        longPressTask = Task { @MainActor in
            try? await Task.sleep(for: Style.dragSelectionDelay)
            guard !Task.isCancelled, isPressingActiveLens else { return }
            
            beginDragLensSelection()
            if let activeLensPressLocation {
                updateDragHighlightedLens(at: activeLensPressLocation)
            }
        }
    }
    
    private func beginDragLensSelection() {
        guard !isDragSelectingLens else { return }
        
        isDragSelectingLens = true
        hapticTrigger += 1
        withAnimation(Animations.bouncy) {
            isExpanded = true
        }
    }
    
    private func updateDragHighlightedLens(at location: CGPoint) {
        let nextLens = lens(at: location)
        guard dragHighlightedLens != nextLens else { return }
        
        let previousLens = dragHighlightedLens
        dragHighlightedLens = nextLens
        if previousLens != nil || nextLens != nil {
            selectionFeedbackTrigger += 1
        }
    }
    
    private func lens(at location: CGPoint) -> Lens? {
        let lenses = alternateLenses
        let center = CGPoint(x: height / 2, y: height / 2)
        let hitRadius = (Style.lensDiameterInactive / 2) + Style.dragSelectionHitPadding
        
        return lenses.enumerated()
            .map { index, lens in
                let offset = lensOffset(at: index, count: lenses.count)
                let lensCenter = CGPoint(x: center.x + offset.width, y: center.y + offset.height)
                let dx = location.x - lensCenter.x
                let dy = location.y - lensCenter.y
                let distance = sqrt(dx * dx + dy * dy)
                
                return (lens: lens, distance: distance)
            }
            .filter { $0.distance <= hitRadius }
            .min { $0.distance < $1.distance }?
            .lens
    }
    
    private func textStyle(for lens: Lens, isActive: Bool) -> Color {
        if dragHighlightedLens == lens {
            return theme.accent
        }
        
        return isActive ? .black : .white.opacity(0.86)
    }
    
    // MARK: - Subviews
    private func activeLensButton(_ lens: Lens) -> some View {
        Text(lens.label)
            .font(.system(.callout, design: .monospaced))
            .bold()
            .foregroundStyle(textStyle(for: lens, isActive: true))
            .frame(width: Style.lensDiameterActive, height: Style.lensDiameterActive)
            .contentShape(.circle)
            .accessibilityLabel(lensButtonTitle(for: lens))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                toggleExpanded()
            }
            .glassEffect(.regular.interactive().tint(theme.accent.opacity(0.86)), in: .circle)
            .gesture(activeLensPressGesture)
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
                .foregroundStyle(textStyle(for: lens, isActive: isActive))
                .frame(
                    width: isActive ? Style.lensDiameterActive : Style.lensDiameterInactive,
                    height: isActive ? Style.lensDiameterActive : Style.lensDiameterInactive
                )
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(lensButtonTitle(for: lens))
        .glassEffect(.regular.interactive().tint(isActive ? theme.accent.opacity(0.86) : .black.mix(with: .white, by: 0.24)), in: .circle)
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
                    .foregroundStyle(textStyle(for: lens, isActive: false))
                    .frame(width: Style.lensDiameterInactive, height: Style.lensDiameterInactive)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(lensButtonTitle(for: lens))
            .glassEffect(.regular.interactive().tint(theme.accent.opacity(0.2)), in: .circle)
            .offset(lensOffset(at: index, count: lenses.count))
            .transition(.scale(scale: 0.72).combined(with: .opacity))
        }
    }
}

// MARK: - View
struct LockedLensSelectorView: View {
    @Bindable var cameraModel: LockedCameraModel
    let theme: AppTheme
    let height: CGFloat
    
    @State private var isExpanded = false
    @State private var isPressingActiveLens = false
    @State private var isDragSelectingLens = false
    @State private var activeLensPressLocation: CGPoint?
    @State private var dragHighlightedLens: Lens?
    @State private var longPressTask: Task<Void, Never>?
    @State private var hapticTrigger = 0
    @State private var selectionFeedbackTrigger = 0
    
    var body: some View {
        GlassEffectContainer(spacing: 8) {
            ZStack {
                if isExpanded {
                    expandedLensButtons
                }
                
                activeLensButton(cameraModel.activeLens)
            }
        }
        .frame(width: height, height: height)
        .coordinateSpace(name: Self.lensSelectorCoordinateSpace)
        .animation(Animations.bouncy, value: isExpanded)
        .animation(Animations.bouncy, value: cameraModel.activeLens)
        .animation(Animations.easeInOut, value: dragHighlightedLens)
        .sensoryFeedback(.impact, trigger: hapticTrigger)
        .sensoryFeedback(.selection, trigger: selectionFeedbackTrigger)
    }
}
