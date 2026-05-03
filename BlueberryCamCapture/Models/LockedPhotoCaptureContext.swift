import Foundation

struct LockedPhotoCaptureContext: Sendable {
    let captureMode: CaptureMode
    let onCapture: (@MainActor @Sendable () -> Void)?
}

final class LockedPhotoCaptureContextStore: @unchecked Sendable {
    private let lock = NSLock()
    nonisolated(unsafe) private var contexts: [Int64: LockedPhotoCaptureContext] = [:]
    
    nonisolated func set(_ context: LockedPhotoCaptureContext, for uniqueID: Int64) {
        lock.lock()
        contexts[uniqueID] = context
        lock.unlock()
    }
    
    nonisolated func removeContext(for uniqueID: Int64) -> LockedPhotoCaptureContext? {
        lock.lock()
        let context = contexts.removeValue(forKey: uniqueID)
        lock.unlock()
        return context
    }
    
    nonisolated func context(for uniqueID: Int64) -> LockedPhotoCaptureContext? {
        lock.lock()
        let context = contexts[uniqueID]
        lock.unlock()
        return context
    }
}
