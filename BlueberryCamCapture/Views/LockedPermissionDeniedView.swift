import SwiftUI

struct LockedPermissionDeniedView: View {
    let openMainApp: () -> ()
    var body: some View {
        ZStack {
            Color.black.opacity(0.85).ignoresSafeArea()
            
            VStack(spacing: 20) {
                Image(systemName: "photo.badge.exclamationmark")
                    .font(.system(size: 48))
                    .foregroundStyle(.white)
                
                Text("Photos Access Required")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                
                Text("Blueberry Cam needs permission to save photos.")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                
                Button(action: openMainApp) {
                    Text("Open App to Grant Access")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(.white)
                        .clipShape(.capsule)
                }
            }
        }
        .transition(.opacity)
    }
}
