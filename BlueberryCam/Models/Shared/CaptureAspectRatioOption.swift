internal import AVFoundation
import CoreGraphics
import Foundation

enum CaptureAspectRatioOption: CaseIterable, Equatable, Identifiable, Sendable {
    case portrait4x3
    case landscape4x3
    
    static let defaultSelection: CaptureAspectRatioOption = .landscape4x3
    
    nonisolated var id: Self { self }
    
    nonisolated var label: String {
        switch self {
            case .portrait4x3: "3:4"
            case .landscape4x3: "4:3"
        }
    }
    
    nonisolated var widthToHeightRatio: CGFloat {
        switch self {
            case .portrait4x3: 3.0 / 4.0
            case .landscape4x3: 4.0 / 3.0
        }
    }
    
    nonisolated var dynamicAspectRatio: AVCaptureDevice.AspectRatio {
        switch self {
            case .portrait4x3: .ratio3x4
            case .landscape4x3: .ratio4x3
        }
    }
    
    nonisolated init?(dynamicAspectRatio: AVCaptureDevice.AspectRatio) {
        switch dynamicAspectRatio {
            case .ratio3x4:
                self = .portrait4x3
            case .ratio4x3:
                self = .landscape4x3
            default:
                return nil
        }
    }
}
