internal import AVFoundation
import CoreGraphics
import Foundation

struct PhotoCaptureContext: Sendable {
    let captureMode: CaptureMode
    let photoFilter: PhotoFilter
    let saveLocation: SaveLocation
    let isBurst: Bool
    let burstSessionID: Int?
    let isDualCameraCapture: Bool
    let dualCameraPipPlacement: DualCameraPipPlacement
    let dualCameraPipRotationAngle: CGFloat
    let shouldDeferConfetti: Bool
    let onCapture: (@MainActor @Sendable () -> Void)?
}

struct ShutterHoldBurstSnapshot {
    let wasBurstModeEnabled: Bool
    let burstIntervalSeconds: Double?
    let burstFrameLimit: Int?
    let flashMode: AVCaptureDevice.FlashMode
}

struct BurstSaveStats {
    let captureMode: CaptureMode
    let frameLimit: Int?
    var isCapturing = true
    var isStopping = false
    var didReachFrameLimit = false
    var sensorCaptureCount = 0
    var expectedSaveCount = 0
    var savedCount = 0
    var captureFailureCount = 0
    var saveFailureCount = 0
    var didPrintDrainSummary = false
    var drainSummaryDate: Date?
}

final class PhotoCaptureContextStore: @unchecked Sendable {
    private let lock = NSLock()
    nonisolated(unsafe) private var contexts: [Int64: PhotoCaptureContext] = [:]
    nonisolated(unsafe) private var countedCaptureIDs: Set<Int64> = []
    nonisolated(unsafe) private var processedPhotoIDs: Set<Int64> = []
    nonisolated(unsafe) private var reportedCaptureFailureIDs: Set<Int64> = []
    
    nonisolated func set(_ context: PhotoCaptureContext, for uniqueID: Int64) {
        lock.lock()
        contexts[uniqueID] = context
        lock.unlock()
    }
    
    nonisolated func removeContext(for uniqueID: Int64) -> PhotoCaptureContext? {
        lock.lock()
        let context = contexts.removeValue(forKey: uniqueID)
        countedCaptureIDs.remove(uniqueID)
        processedPhotoIDs.remove(uniqueID)
        reportedCaptureFailureIDs.remove(uniqueID)
        lock.unlock()
        return context
    }
    
    nonisolated func context(for uniqueID: Int64) -> PhotoCaptureContext? {
        lock.lock()
        let context = contexts[uniqueID]
        lock.unlock()
        return context
    }
    
    nonisolated func markCaptureFailureIfNeeded(for uniqueID: Int64) -> Bool {
        lock.lock()
        let didInsert = reportedCaptureFailureIDs.insert(uniqueID).inserted
        lock.unlock()
        return didInsert
    }
    
    nonisolated func markCaptureCounted(for uniqueID: Int64) {
        lock.lock()
        countedCaptureIDs.insert(uniqueID)
        lock.unlock()
    }
    
    nonisolated func hasCountedCapture(for uniqueID: Int64) -> Bool {
        lock.lock()
        let hasCountedCapture = countedCaptureIDs.contains(uniqueID)
        lock.unlock()
        return hasCountedCapture
    }
    
    nonisolated func markPhotoDataProduced(for uniqueID: Int64) {
        lock.lock()
        processedPhotoIDs.insert(uniqueID)
        lock.unlock()
    }
    
    nonisolated func hasProducedPhotoData(for uniqueID: Int64) -> Bool {
        lock.lock()
        let hasProducedPhotoData = processedPhotoIDs.contains(uniqueID)
        lock.unlock()
        return hasProducedPhotoData
    }
    
    nonisolated func removeAll() {
        lock.lock()
        contexts.removeAll()
        countedCaptureIDs.removeAll()
        processedPhotoIDs.removeAll()
        reportedCaptureFailureIDs.removeAll()
        lock.unlock()
    }
}

enum BurstCaptureCompletionGate: Sendable {
    case sensorCapture
    case processing
}

final class BurstCaptureTracker: @unchecked Sendable {
    private let lock = NSLock()
    nonisolated(unsafe) private var continuations: [Int64: (gate: BurstCaptureCompletionGate, continuation: CheckedContinuation<Bool, Never>)] = [:]
    nonisolated(unsafe) private var processingIDs: Set<Int64> = []
    nonisolated(unsafe) private var capacityContinuations: [CheckedContinuation<Void, Never>] = []
    
    nonisolated var inFlightProcessingCount: Int {
        lock.lock()
        let count = processingIDs.count
        lock.unlock()
        return count
    }
    
    nonisolated func waitForProcessingCapacity(limit: Int) async {
        guard limit > 0 else { return }
        
        await withCheckedContinuation { continuation in
            lock.lock()
            if processingIDs.count < limit {
                lock.unlock()
                continuation.resume()
            } else {
                capacityContinuations.append(continuation)
                lock.unlock()
            }
        }
    }
    
    nonisolated func waitForCapture(uniqueID: Int64,
                                    gate: BurstCaptureCompletionGate,
                                    startCapture: @Sendable () -> Void) async -> Bool {
        await withCheckedContinuation { continuation in
            lock.lock()
            continuations[uniqueID] = (gate, continuation)
            processingIDs.insert(uniqueID)
            lock.unlock()
            
            startCapture()
        }
    }
    
    nonisolated func completeSensorCapture(uniqueID: Int64, success: Bool) {
        completeCapture(uniqueID: uniqueID, event: .sensorCapture, success: success)
    }
    
    nonisolated func completeProcessing(uniqueID: Int64, success: Bool) {
        lock.lock()
        let didRemoveProcessingID = processingIDs.remove(uniqueID) != nil
        let capacityContinuation = didRemoveProcessingID && !capacityContinuations.isEmpty ? capacityContinuations.removeFirst() : nil
        lock.unlock()
        
        capacityContinuation?.resume()
        completeCapture(uniqueID: uniqueID, event: .processing, success: success)
    }
    
    private nonisolated func completeCapture(uniqueID: Int64,
                                             event: BurstCaptureCompletionGate,
                                             success: Bool) {
        lock.lock()
        let pending = continuations[uniqueID]
        let shouldComplete = pending.map { captureGate($0.gate, matches: event) || !success } ?? false
        if shouldComplete {
            continuations.removeValue(forKey: uniqueID)
        }
        lock.unlock()
        
        if shouldComplete {
            pending?.continuation.resume(returning: success)
        }
    }
    
    private nonisolated func captureGate(_ gate: BurstCaptureCompletionGate,
                                         matches event: BurstCaptureCompletionGate) -> Bool {
        switch (gate, event) {
            case (.sensorCapture, .sensorCapture), (.processing, .processing):
                true
            default:
                false
        }
    }
    
    nonisolated func cancelPendingWaits() {
        cancel(clearProcessingIDs: false)
    }
    
    nonisolated func cancelAll() {
        cancel(clearProcessingIDs: true)
    }
    
    private nonisolated func cancel(clearProcessingIDs: Bool) {
        lock.lock()
        let pending = continuations
        continuations.removeAll()
        if clearProcessingIDs {
            processingIDs.removeAll()
        }
        let capacityPending = capacityContinuations
        capacityContinuations.removeAll()
        lock.unlock()
        
        for item in pending.values {
            item.continuation.resume(returning: false)
        }
        for continuation in capacityPending {
            continuation.resume()
        }
    }
}
