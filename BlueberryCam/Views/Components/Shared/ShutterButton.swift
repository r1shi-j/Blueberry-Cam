import SwiftUI

enum ShutterArcPhase {
    case hidden
    case rotating
    case collapsing
}

struct ShutterButton: View {
    let tint: Color
    let height: CGFloat
    var isEnabled = true
    var isProcessing: Bool
    let onPressBegan: () -> Void
    let onPressEnded: () -> Void
    let onPressCancelled: () -> Void
    @Binding var isForcePressed: Bool
    @State private var isPressed = false
    @State private var arcPhase: ShutterArcPhase = .hidden
    
    init(tint: Color, height: CGFloat, isEnabled: Bool = true, isProcessing: Bool, onPressBegan: @escaping () -> Void, onPressEnded: @escaping () -> Void, onPressCancelled: @escaping () -> Void, isForcePressed: Binding<Bool> = .constant(false)) {
        self.tint = tint
        self.height = height
        self.isEnabled = isEnabled
        self.isProcessing = isProcessing
        self.onPressBegan = onPressBegan
        self.onPressEnded = onPressEnded
        self.onPressCancelled = onPressCancelled
        self._isForcePressed = isForcePressed
    }
    
    var body: some View {
        ZStack {
            Circle()
                .frame(width: height, height: height)
                .glassEffect(.regular.tint(tint))
            Circle()
                .fill(.white)
                .frame(width: height*0.84, height: height*0.84)
                .glassEffect(.regular.interactive())
                .scaleEffect(!isPressed && isForcePressed ? 1.2 : 1)
            
            ShutterProgressArc(height: height, phase: $arcPhase)
                .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity)
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.15), value: isPressed)
        .animation(.bouncy(duration: 0.5, extraBounce: 0.3), value: isForcePressed)
        .contentShape(.rect)
        .gesture(pressGesture)
        .allowsHitTesting(isEnabled)
        .accessibilityElement()
        .accessibilityLabel("Shutter")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            guard isEnabled else { return }
            onPressBegan()
            onPressEnded()
        }
        .onDisappear(perform: cancelPressIfNeeded)
        .onChange(of: isProcessing) { _, new in
            switch (arcPhase, new) {
            case (.hidden, true):
                arcPhase = .rotating
            case (.rotating, false):
                arcPhase = .collapsing
            default:
                break
            }
        }
    }
    
    private var pressGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                guard isEnabled, !isPressed else { return }
                isPressed = true
                onPressBegan()
            }
            .onEnded { _ in
                guard isPressed else { return }
                isPressed = false
                onPressEnded()
            }
    }
    
    private func cancelPressIfNeeded() {
        guard isPressed else { return }
        isPressed = false
        onPressCancelled()
    }
}

private struct ShutterProgressArc: View {
    let height: CGFloat
    @Binding var phase: ShutterArcPhase
    
    @State private var rotation: Double = 0
    @State private var trimStart: CGFloat = 0
    @State private var isRotating = false
    
    private let lineWidth: CGFloat = 5
    private let arcFraction: CGFloat = 0.5
    private let duration: Double = 1.0
    
    var body: some View {
        let arcSize = height * 0.84 * 0.74
        
        Circle()
            .trim(from: trimStart, to: arcFraction)
            .stroke(
                AngularGradient(
                    gradient: Gradient(colors: [
                        Color(white: 0.80, opacity: 0.05),
                        Color(white: 0.80, opacity: 0.15),
                        Color(white: 0.80, opacity: 0.25),
                        Color(white: 0.80, opacity: 0.40),
                        Color(white: 0.80, opacity: 0.25),
                        Color(white: 0.80, opacity: 0.15),
                        Color(white: 0.80, opacity: 0.05),
                    ]),
                    center: .center
                ),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
            )
            .frame(width: arcSize, height: arcSize)
            .rotationEffect(.degrees(rotation))
            .opacity(phase == .hidden ? 0 : 1)
            .animation(.easeInOut(duration: 0.2), value: phase == .hidden)
            .onChange(of: phase) { _, new in
                switch new {
                case .rotating:
                    startRotating()
                case .collapsing:
                    startCollapsing()
                case .hidden:
                    break
                }
            }
    }
    
    private func startRotating() {
        trimStart = 0
        rotation = 0
        isRotating = true
        rotate()
    }
    
    private func startCollapsing() {
        isRotating = false
        withAnimation(.easeInOut(duration: 0.3)) {
            trimStart = arcFraction
        } completion: {
            phase = .hidden
        }
    }
    
    private func rotate() {
        withAnimation(.linear(duration: duration)) {
            rotation += 360
        } completion: {
            guard isRotating else { return }
            rotate()
        }
    }
}
