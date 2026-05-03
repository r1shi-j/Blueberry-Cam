internal import AVFoundation
import Foundation

enum Lens: String, CaseIterable {
    case frontUltraWide, front, ultraWide, wide, tele2x, tele4x, tele8x
    
    var label: String {
        switch self {
            case .frontUltraWide: "1"
            case .front: "1.5"
            case .ultraWide: "0.5"
            case .wide: "1"
            case .tele2x: "2"
            case .tele4x: "4"
            case .tele8x: "8"
        }
    }
    
    var isFront: Bool { self == .front || self == .frontUltraWide }
    
    var deviceType: AVCaptureDevice.DeviceType {
        switch self {
            case .front, .frontUltraWide: .builtInUltraWideCamera
            case .ultraWide: .builtInUltraWideCamera
            case .wide, .tele2x: .builtInWideAngleCamera
            case .tele4x, .tele8x: .builtInTelephotoCamera
        }
    }
    
    var position: AVCaptureDevice.Position { isFront ? .front : .back }
    
    var zoomFactor: CGFloat {
        switch self {
            case .tele2x: 2.0
            case .tele8x: 2.0
            case .front: 1.55
            default: 1.0
        }
    }
    
    var preservesRawCaptureMode: Bool {
        switch self {
            case .frontUltraWide, .ultraWide, .wide, .tele4x:
                true
            default:
                false
        }
    }
    
    var preservesHighResolutionCapture: Bool {
        switch self {
            case .ultraWide, .wide, .tele4x:
                true
            default:
                false
        }
    }
    
    var rawFallbackLens: Lens {
        switch self {
            case .front:
                    .frontUltraWide
            case .tele2x:
                    .wide
            case .tele8x:
                    .tele4x
            default:
                self
        }
    }
    
    var highResolutionFallbackLens: Lens {
        switch self {
            case .tele2x:
                    .wide
            case .tele8x:
                    .tele4x
            default:
                self
        }
    }
}
