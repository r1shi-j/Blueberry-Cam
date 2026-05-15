import Foundation

final class CaptureModeBox: @unchecked Sendable {
    nonisolated(unsafe) var value: CaptureMode = .raw
}

enum CaptureMode: String, CaseIterable, Identifiable {
    case heif = "HEIF"
    case jpeg = "JPEG"
    case raw = "RAW"
    case proRaw = "ProRAW"
    var id: String { rawValue }
    
    static let defaultShownFormats: [CaptureMode] = [.heif, .raw, .proRaw]
    static let processedFallbackOrder: [CaptureMode] = [.heif, .jpeg]
    
    nonisolated var isProcessed: Bool {
        self == .heif || self == .jpeg
    }
    
    nonisolated var isRawLike: Bool {
        self == .raw || self == .proRaw
    }
}
