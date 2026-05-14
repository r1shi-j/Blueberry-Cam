import SwiftUI

struct ShutterButton: View {
    let tint: Color
    let height: CGFloat
    var isEnabled = true
    let onPressBegan: () -> Void
    let onPressEnded: () -> Void
    let onPressCancelled: () -> Void
    @State private var isPressed = false
    
    var body: some View {
        ZStack {
            Circle()
                .frame(width: height, height: height)
                .glassEffect(.regular.tint(tint))
            Circle()
                .fill(.white)
                .frame(width: height*0.84, height: height*0.84)
                .glassEffect(.regular.interactive())
        }
        .frame(maxWidth: .infinity)
        .transition(.opacity)
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
