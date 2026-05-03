import Foundation

final class CaptureModeBox: @unchecked Sendable {
    nonisolated(unsafe) var value: CaptureMode = .jpeg
}

enum CaptureMode: String, CaseIterable, Identifiable {
    case heif = "HEIF"
    case jpeg = "JPEG"
    case raw = "RAW"
    var id: String { rawValue }
}
