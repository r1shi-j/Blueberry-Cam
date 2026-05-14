import Foundation

final class CaptureModeBox: @unchecked Sendable {
    nonisolated(unsafe) var value: CaptureMode = .raw
}

enum CaptureMode: String, CaseIterable, Identifiable {
    case heif = "HEIF"
    case jpeg = "JPEG"
    case raw = "RAW"
    var id: String { rawValue }
    
    static let defaultShownFormats: [CaptureMode] = [.heif, .raw]
    static let processedFallbackOrder: [CaptureMode] = [.heif, .jpeg]
    
    var isProcessed: Bool {
        self == .heif || self == .jpeg
    }
}
