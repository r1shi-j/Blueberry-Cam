import SwiftUI

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
            if isProcessing {
                ProgressView()
                    .controlSize(.large)
                    .tint(.black.opacity(0.6))
            }
        }
        .frame(maxWidth: .infinity)
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.15), value: isPressed)
        .animation(.easeInOut(duration: 0.2), value: isProcessing)
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
