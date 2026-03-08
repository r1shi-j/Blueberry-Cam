//import SwiftUI
//
//struct SelfieOrientationToggle: View {
//    @ObservedObject var cameraModel: CameraModel
//    
//    var body: some View {
//        HStack(spacing: 2) {
//            ForEach(SelfieOrientation.allCases, id: \.rawValue) { orientation in
//                Button {
//                    cameraModel.setSelfieOrientation(orientation)
//                } label: {
//                    Text(orientation.rawValue)
//                        .font(.system(size: 12,
//                                      weight: cameraModel.selfieOrientation == orientation ? .bold : .regular,
//                                      design: .monospaced))
//                        .foregroundColor(cameraModel.selfieOrientation == orientation ? .black : .white.opacity(0.85))
//                        .padding(.horizontal, 12)
//                        .padding(.vertical, 5)
//                        .background(
//                            Capsule().fill(cameraModel.selfieOrientation == orientation ? Color.yellow : Color.clear)
//                        )
//                }
//            }
//        }
//        .padding(.horizontal, 12)
//        .padding(.vertical, 6)
//        .background(
//            Capsule()
//                .fill(Color.black.opacity(0.55))
//                .overlay(Capsule().stroke(Color.white.opacity(0.1), lineWidth: 1))
//        )
//        .transition(.opacity.combined(with: .scale(scale: 0.95)))
//    }
//}
