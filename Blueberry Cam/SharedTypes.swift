import Foundation
internal import AVFoundation
import CoreMedia

// Simple thread-safe box for passing CaptureMode across isolation boundaries
final class CaptureModeBox: @unchecked Sendable {
    nonisolated(unsafe) var value: CaptureMode = .jpeg
}

// Thread-safe frame counter for skipping expensive analysis on alternate frames
final class FrameCounter: @unchecked Sendable {
    nonisolated(unsafe) private var _count: Int = 0
    nonisolated init() {}
    nonisolated func next() -> Int { _count &+= 1; return _count }
}

// MARK: - ResolutionOption
struct ResolutionOption: Identifiable, Equatable {
    let width: Int32
    let height: Int32
    var id: Int { Int(width) * Int(height) }
    var dimensions: CMVideoDimensions { CMVideoDimensions(width: width, height: height) }
    var label: String {
        let mp = Int(Double(width) * Double(height) / 1_000_000.0)
        return "\(mp)MP"
    }
}

// MARK: - CaptureMode
enum CaptureMode: String, CaseIterable, Identifiable {
    case jpeg = "JPEG"
    case heif = "HEIF"
    case raw  = "RAW"
    var id: String { rawValue }
}

// MARK: - Lens
enum Lens: String, CaseIterable {
    case frontUltraWide, front, ultraWide, wide, tele2x, tele4x, tele8x
    
    var label: String {
        switch self {
            case .frontUltraWide: return "0.87"
            case .front:          return "0.95"
            case .ultraWide:      return "0.5"
            case .wide:           return "1"
            case .tele2x:         return "2"
            case .tele4x:         return "4"
            case .tele8x:         return "8"
        }
    }
    
    var isFront: Bool { self == .front || self == .frontUltraWide }
    
    var deviceType: AVCaptureDevice.DeviceType {
        switch self {
            case .frontUltraWide:      return .builtInUltraWideCamera
            case .front:               return .builtInWideAngleCamera
            case .ultraWide:           return .builtInUltraWideCamera
            case .wide, .tele2x:       return .builtInWideAngleCamera
            case .tele4x, .tele8x:     return .builtInTelephotoCamera
        }
    }
    
    var position: AVCaptureDevice.Position { isFront ? .front : .back }
    
    var zoomFactor: CGFloat {
        switch self {
            case .tele2x: return 2.0
            case .tele8x: return 2.0
            default:      return 1.0
        }
    }
}

enum HistogramMode: String, CaseIterable {
    case luminance = "LUMA"
    case color = "RGB"
    case waveform = "WAVE"
    case parade = "PARADE"
}

enum HistogramSize: String, CaseIterable {
    case small, large
}

enum ManualControl: CaseIterable {
    case ev, iso, ss, f, wb
}

enum WaveformConstants {
    nonisolated static let wfCols = 512
    nonisolated static let wfRows = 200
}
