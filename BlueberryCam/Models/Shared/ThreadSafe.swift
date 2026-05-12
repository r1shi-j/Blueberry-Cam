import Foundation
import CoreVideo

final class SessionURLBox: @unchecked Sendable {
    nonisolated(unsafe) var value: URL? = nil
}

// Thread-safe frame counter for skipping expensive analysis on alternate frames
final class FrameCounter: @unchecked Sendable {
    nonisolated(unsafe) private var _count: Int = 0
    nonisolated init() {}
    nonisolated func next() -> Int { _count &+= 1; return _count }
}

final class PixelBufferStore: @unchecked Sendable {
    private let lock = NSLock()
    nonisolated(unsafe) private var pixelBuffer: CVPixelBuffer?
    
    nonisolated func set(_ newValue: CVPixelBuffer?) {
        lock.lock()
        pixelBuffer = newValue
        lock.unlock()
    }
    
    nonisolated func currentPixelBuffer() -> CVPixelBuffer? {
        lock.lock()
        let value = pixelBuffer
        lock.unlock()
        return value
    }
}
