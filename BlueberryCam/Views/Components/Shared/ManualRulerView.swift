import SwiftUI

struct ManualRulerView: View {
    @Binding var value: Float
    
    let range: ClosedRange<Float>
    let step: Float
    let axis: RulerAxis
    let majorTickStride: Int
    let accessibilityLabel: String
    let tickColor: Color
    let centerTickColor: Color
    let centerTickShadowColor: Color
    
    init(value: Binding<Float>,
         range: ClosedRange<Float>,
         step: Float,
         axis: RulerAxis,
         majorTickStride: Int,
         accessibilityLabel: String,
         tickColor: Color = .white,
         centerTickColor: Color? = nil,
         centerTickShadowColor: Color = .black.opacity(0.35)) {
        self._value = value
        self.range = range
        self.step = step
        self.axis = axis
        self.majorTickStride = majorTickStride
        self.accessibilityLabel = accessibilityLabel
        self.tickColor = tickColor
        self.centerTickColor = centerTickColor ?? tickColor
        self.centerTickShadowColor = centerTickShadowColor
    }
    
    @State private var dragStartValue: Float?
    @State private var displayedValue: Float?
    @State private var snapBackTask: Task<Void, Never>?
    @State private var selectionFeedbackTrigger = 0
    
    private let tickSpacing: CGFloat = 14
    private let pointsPerStep: CGFloat = 20
    private let momentumMultiplier: CGFloat = 0.25
    private let largeDragMomentumMultiplier: CGFloat = 0.55
    private let intentionalFlickMultiplier: CGFloat = 0.9
    private let maximumMomentumDistance: CGFloat = 520
    private let intentionalFlickDistance: CGFloat = 320
    private let overshootSteps: Float = 1.8
    private let liveOvershootSteps: Float = 1.2
    private let edgeResistance: Float = 0.28
    
    var body: some View {
        RulerTicksView(
            value: displayedValue ?? value,
            range: range,
            step: step,
            axis: axis,
            tickSpacing: tickSpacing,
            majorTickStride: majorTickStride,
            tickColor: tickColor
        )
        .overlay(alignment: axis == .vertical ? .trailing : .top) {
            CenterTickMarker(axis: axis, color: centerTickColor, shadowColor: centerTickShadowColor)
        }
        .contentShape(.rect)
        .gesture(dragGesture)
        .onAppear {
            displayedValue = value
        }
        .onChange(of: value) { _, newValue in
            guard dragStartValue == nil else { return }
            
            withAnimation(Animations.manualControlSnap) {
                displayedValue = newValue
            }
        }
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(Text(Double(value), format: .number.precision(.fractionLength(accessibilityFractionLength))))
        .sensoryFeedback(.selection, trigger: selectionFeedbackTrigger)
    }
    
    private var accessibilityFractionLength: Int {
        step < 0.1 ? 2 : step < 1 ? 1 : 0
    }
    
    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { gestureValue in
                snapBackTask?.cancel()
                snapBackTask = nil
                
                if dragStartValue == nil {
                    dragStartValue = value
                }
                
                guard let startValue = dragStartValue else { return }
                
                let nextValue = resistedRawValue(from: gestureValue.translation, startValue: startValue)
                let clampedValue = steppedValue(for: nextValue)
                
                displayedValue = nextValue
                
                guard clampedValue != value else { return }
                
                value = clampedValue
                selectionFeedbackTrigger += 1
            }
            .onEnded { gestureValue in
                guard let startValue = dragStartValue else { return }
                
                let targetValue = targetValue(for: gestureValue, startValue: startValue, allowsOvershoot: true)
                let clampedValue = steppedValue(for: targetValue)
                let releaseValue = displayedValue ?? clampedValue
                let overshootValue = overshootValue(
                    for: targetValue,
                    clampedValue: clampedValue,
                    releaseValue: releaseValue
                )
                let shouldTriggerFeedback = clampedValue != value
                
                withAnimation(.interpolatingSpring(duration: 0.28, bounce: 0.36)) {
                    displayedValue = overshootValue
                    value = clampedValue
                }
                
                if shouldTriggerFeedback {
                    selectionFeedbackTrigger += 1
                }
                
                if overshootValue != clampedValue {
                    snapBackTask?.cancel()
                    snapBackTask = Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(110))
                        guard !Task.isCancelled else { return }
                        
                        withAnimation(.interpolatingSpring(duration: 0.36, bounce: 0.42)) {
                            displayedValue = clampedValue
                        }
                    }
                }
                
                dragStartValue = nil
            }
    }
    
    private func unclampedRawValue(from translation: CGSize, startValue: Float) -> Float {
        let distance = switch axis {
            case .horizontal: -translation.width
            case .vertical: -translation.height
        }
        let stepOffset = Float(distance / pointsPerStep)
        return startValue + stepOffset * step
    }
    
    private func resistedRawValue(from translation: CGSize, startValue: Float) -> Float {
        let rawValue = unclampedRawValue(from: translation, startValue: startValue)
        let liveOvershootLimit = step * liveOvershootSteps
        
        if rawValue < range.lowerBound {
            let resistedOvershoot = (range.lowerBound - rawValue) * edgeResistance
            return max(range.lowerBound - liveOvershootLimit, range.lowerBound - resistedOvershoot)
        }
        
        if rawValue > range.upperBound {
            let resistedOvershoot = (rawValue - range.upperBound) * edgeResistance
            return min(range.upperBound + liveOvershootLimit, range.upperBound + resistedOvershoot)
        }
        
        return rawValue
    }
    
    private func steppedValue(for rawValue: Float) -> Float {
        let steppedValue = (rawValue / step).rounded() * step
        return min(max(steppedValue, range.lowerBound), range.upperBound)
    }
    
    private func targetValue(for gestureValue: DragGesture.Value, startValue: Float, allowsOvershoot: Bool) -> Float {
        let extraWidth = limitedMomentum(
            gestureValue.predictedEndTranslation.width - gestureValue.translation.width,
            dragDistance: abs(gestureValue.translation.width)
        )
        let extraHeight = limitedMomentum(
            gestureValue.predictedEndTranslation.height - gestureValue.translation.height,
            dragDistance: abs(gestureValue.translation.height)
        )
        let targetTranslation = CGSize(
            width: gestureValue.translation.width + extraWidth,
            height: gestureValue.translation.height + extraHeight
        )
        
        let rawTargetValue = unclampedRawValue(from: targetTranslation, startValue: startValue)
        
        guard allowsOvershoot else {
            return min(max(rawTargetValue, range.lowerBound), range.upperBound)
        }
        
        let overshootLimit = step * overshootSteps
        return min(max(rawTargetValue, range.lowerBound - overshootLimit), range.upperBound + overshootLimit)
    }
    
    private func limitedMomentum(_ distance: CGFloat, dragDistance: CGFloat) -> CGFloat {
        let multiplier = if dragDistance > intentionalFlickDistance {
            intentionalFlickMultiplier
        } else if dragDistance > 220 {
            largeDragMomentumMultiplier
        } else {
            momentumMultiplier
        }
        return min(max(distance * multiplier, -maximumMomentumDistance), maximumMomentumDistance)
    }
    
    private func overshootValue(for targetValue: Float, clampedValue: Float, releaseValue: Float) -> Float {
        if clampedValue == range.lowerBound && targetValue < range.lowerBound {
            let targetOvershoot = max(range.lowerBound - step * overshootSteps, targetValue)
            guard releaseValue < range.lowerBound else { return targetOvershoot }
            return max(targetOvershoot, releaseValue)
        }
        
        if clampedValue == range.upperBound && targetValue > range.upperBound {
            let targetOvershoot = min(range.upperBound + step * overshootSteps, targetValue)
            guard releaseValue > range.upperBound else { return targetOvershoot }
            return min(targetOvershoot, releaseValue)
        }
        
        return clampedValue
    }
}

private struct RulerTicksView: View, Animatable {
    var value: Float
    let range: ClosedRange<Float>
    let step: Float
    let axis: RulerAxis
    let tickSpacing: CGFloat
    let majorTickStride: Int
    let tickColor: Color
    
    var animatableData: Double {
        get { Double(value) }
        set { value = Float(newValue) }
    }
    
    var body: some View {
        Canvas { context, size in
            drawTicks(in: context, size: size)
        }
    }
    
    private func drawTicks(in context: GraphicsContext, size: CGSize) {
        let centerX = size.width / 2
        let centerY = size.height / 2
        let farEdge = axis == .vertical ? size.width : size.height
        let exactStep = CGFloat((value - range.lowerBound) / step)
        let currentStep = Int(exactStep.rounded())
        let fractionalStepOffset = exactStep - CGFloat(currentStep)
        let lowerStep = 0
        let upperStep = Int(((range.upperBound - range.lowerBound) / step).rounded())
        let visibleTickCount = Int((axis == .vertical ? size.height : size.width) / tickSpacing) + 8
        
        for offset in -visibleTickCount...visibleTickCount {
            let tickIndex = currentStep + offset
            guard tickIndex >= lowerStep && tickIndex <= upperStep else { continue }
            
            let position = switch axis {
                case .horizontal: centerX + (CGFloat(offset) - fractionalStepOffset) * tickSpacing
                case .vertical: centerY + (CGFloat(offset) - fractionalStepOffset) * tickSpacing
            }
            let limit = axis == .vertical ? size.height : size.width
            guard position >= 0 && position <= limit else { continue }
            
            let isBoundaryTick = tickIndex == lowerStep || tickIndex == upperStep
            let isMajorTick = isBoundaryTick || tickIndex.isMultiple(of: majorTickStride)
            let distanceFromCenter = switch axis {
                case .horizontal: abs(position - centerX) / max(centerX, 1)
                case .vertical: abs(position - centerY) / max(centerY, 1)
            }
            let opacity = max(0.22, 1 - distanceFromCenter)
            let length: CGFloat = isMajorTick ? 44 : 28
            let lineWidth: CGFloat = isMajorTick ? 2 : 1
            
            var path = Path()
            switch axis {
                case .horizontal:
                    path.move(to: CGPoint(x: position, y: 0))
                    path.addLine(to: CGPoint(x: position, y: length))
                case .vertical:
                    path.move(to: CGPoint(x: farEdge - length, y: position))
                    path.addLine(to: CGPoint(x: farEdge, y: position))
            }
            
            context.stroke(
                path,
                with: .color(tickColor.opacity(opacity)),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
            )
        }
    }
}

private struct CenterTickMarker: View {
    let axis: RulerAxis
    let color: Color
    let shadowColor: Color
    
    var body: some View {
        Rectangle()
            .fill(color)
            .frame(width: axis == .vertical ? 66 : 3, height: axis == .vertical ? 3 : 66)
            .clipShape(.capsule)
            .shadow(color: shadowColor, radius: 4)
    }
}
