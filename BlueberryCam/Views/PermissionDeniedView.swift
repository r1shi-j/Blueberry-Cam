import SwiftUI

struct PermissionDeniedView: View {
    let cameraGranted: Bool
    let photosGranted: Bool
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 24) {
                Image(BundleIDs.appSymbolName)
                    .font(.system(size: 60))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.black, .blue, .green)
                    .padding(.bottom, 8)
                
                Text("Permissions Required")
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                
                VStack(spacing: 12) {
                    PermissionRow(
                        title: "Camera",
                        description: "Required to take photos",
                        isGranted: cameraGranted
                    )
                    PermissionRow(
                        title: "Photos",
                        description: "Required to save photos",
                        isGranted: photosGranted
                    )
                }
                .padding(.horizontal)
                
                Button {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    UIApplication.shared.open(url)
                } label: {
                    Text("Open Settings")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 32)
                        .padding(.vertical, 14)
                        .background(.white)
                        .clipShape(.capsule)
                }
                .padding(.top, 8)
                
                Text("You can grant access in Settings > Privacy & Security")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
        }
    }
}

private struct PermissionRow: View {
    let title: String
    let description: String
    let isGranted: Bool
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: isGranted ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(isGranted ? .green : .red)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                Text(description)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.6))
            }
            
            Spacer()
        }
        .padding()
        .background(.white.opacity(0.08), in: .rect(cornerRadius: 12))
    }
}
