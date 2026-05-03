import Foundation

final class SessionURLBox: @unchecked Sendable {
    nonisolated(unsafe) var value: URL? = nil
}

// Thread-safe frame counter for skipping expensive analysis on alternate frames
final class FrameCounter: @unchecked Sendable {
    nonisolated(unsafe) private var _count: Int = 0
    nonisolated init() {}
    nonisolated func next() -> Int { _count &+= 1; return _count }
}
