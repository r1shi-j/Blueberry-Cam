import SwiftUI

struct ShutterButton: View {
    let tint: Color
    let height: CGFloat
    var isEnabled = true
    let action: () -> ()
    
    var body: some View {
        ZStack {
            Circle()
                .frame(width: height, height: height)
                .glassEffect(.regular.tint(tint).interactive())
            Button(action: action) {
                Circle()
                    .fill(.white)
                    .frame(width: height*0.84, height: height*0.84)
            }
            .disabled(!isEnabled)
            .glassEffect(.regular.interactive())
        }
        .frame(maxWidth: .infinity)
        .transition(.opacity)
    }
}
