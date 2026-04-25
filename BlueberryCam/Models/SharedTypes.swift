internal import AVFoundation
import CoreMedia
internal import Photos
import SwiftUI

extension Float {
    var signedSingleDecimalString: String {
        let magnitude = abs(Double(self)).formatted(.number.precision(.fractionLength(1)))
        return self >= 0 ? "+\(magnitude)" : "-\(magnitude)"
    }
}

// MARK: Constants
enum Colors {
    static let buttonBackground: Color = .white.opacity(0.15)
    static let buttonText: Color = .white.opacity(0.7)
    static let manualLabel: Color = .white.opacity(0.5)
}

enum Fonts {
    static let manualLabel: Font = .system(size: 10, weight: .bold, design: .monospaced)
    static let manualValue: Font = .system(size: 12, weight: .medium, design: .monospaced)
}

// MARK: Thread-safe
// Simple thread-safe box for passing CaptureMode across isolation boundaries
final class CaptureModeBox: @unchecked Sendable {
    nonisolated(unsafe) var value: CaptureMode = .jpeg
}

final class PhotoFilterBox: @unchecked Sendable {
    nonisolated(unsafe) var value: PhotoFilter = .off
}

final class BurstCaptureTracker: @unchecked Sendable {
    private let lock = NSLock()
    nonisolated(unsafe) private var continuations: [Int64: CheckedContinuation<Bool, Never>] = [:]

    nonisolated func waitForCapture(uniqueID: Int64, startCapture: @Sendable () -> Void) async -> Bool {
        await withCheckedContinuation { continuation in
            lock.lock()
            continuations[uniqueID] = continuation
            lock.unlock()

            startCapture()
        }
    }

    nonisolated func completeCapture(uniqueID: Int64, success: Bool) {
        lock.lock()
        let continuation = continuations.removeValue(forKey: uniqueID)
        lock.unlock()

        continuation?.resume(returning: success)
    }

    nonisolated func cancelAll() {
        lock.lock()
        let pending = continuations
        continuations.removeAll()
        lock.unlock()

        for continuation in pending.values {
            continuation.resume(returning: false)
        }
    }
}

final class SessionURLBox: @unchecked Sendable {
    nonisolated(unsafe) var value: URL? = nil
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
    case raw = "RAW"
    var id: String { rawValue }
}

enum PhotoFilter: String, CaseIterable, Identifiable {
    case off = "Off"
    case temperatureAndTint = "1980s"
    case chrome = "Chrome"
    case instant = "Instant"
    case mono = "Mono"
    case tonal = "Tonal"
    case noir = "Noir"
    case thermal = "Thermal"
    case xRay = "X-Ray"
    
    case comic = "Comic"
    case sketch = "Sketch"
    case lineScreen = "Line Screen"
    case pixellate = "Pixellate"
    case dither = "Dither"
    
    case twirlDistortion = "Twirl Distortion"
    case motionBlur = "Motion Blur"
    case zoomBlur = "Zoom Blur"
    
    case fisheye = "Fisheye"
    case droste = "Droste"
    case lightTunnel = "Light Tunnel"
    case glassLozenge = "Glass Lozenge"
    
    var id: String { rawValue }
}

enum TimerMode: String, CaseIterable, Identifiable {
    case off
    case threeSeconds
    case tenSeconds

    var id: String { rawValue }

    var label: String {
        switch self {
            case .off: ""
            case .threeSeconds: "3s"
            case .tenSeconds: "10s"
        }
    }

    var duration: Duration? {
        switch self {
            case .off: nil
            case .threeSeconds: .seconds(3)
            case .tenSeconds: .seconds(10)
        }
    }

    var seconds: Int? {
        switch self {
            case .off: nil
            case .threeSeconds: 3
            case .tenSeconds: 10
        }
    }
}

enum ResolutionPreference: String, CaseIterable, Identifiable {
    case efficient = "Efficient"
    case max = "Max"
    var id: String { rawValue }
}

// MARK: - Histograms
enum HistogramMode: String, CaseIterable, Identifiable {
    case luminance = "Luminance"
    case color = "RGB"
    case waveform = "Waveform"
    case parade = "Parade"
    case none = "None"
    
    var id: String { rawValue }
}

enum HistogramSize: String, CaseIterable {
    case small, large
}

enum WaveformConstants {
    nonisolated static let wfCols = 512
    nonisolated static let wfRows = 200
}

// MARK: - ManualControl
enum ManualControl: CaseIterable {
    case ev, iso, ss, f, wb
}

// MARK: - Lens
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
}

// MARK: - AppView
enum AppView: String, CaseIterable, Hashable {
    case clean = "Clean"
    case standard = "Standard"
    case settings = "Settings"
    
    var index: Int {
        switch self {
            case .clean: 0
            case .standard: 1
            case .settings: 2
        }
    }
    
    static func fromIndex(_ x: Int) -> AppView {
        switch x {
            case 0: .clean
            case 1: .standard
            case 2: .settings
            default: .standard
        }
    }
}

// MARK: - ResolveAlbumID -
// Same resolveAlbumID logic as CameraModel — finds or creates "Blueberry Cam" album
nonisolated func resolveAlbumID() -> String? {
    let key = BundleIDs.photoAlbumStorageKey
    let defaults = UserDefaults.standard
    
    // Check for a cached ID first
    if let savedID = defaults.string(forKey: key) {
        let existing = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [savedID], options: nil)
        if existing.firstObject != nil {
            return savedID  // Found it – even if the user moved it to a folder
        }
        // ID is stale (album was deleted), fall through to create a new one
    }
    
    // Try to find an existing album with our name
    let fetch = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: nil)
    var foundID: String?
    fetch.enumerateObjects { col, _, stop in
        if col.localizedTitle == BundleIDs.appName {
            foundID = col.localIdentifier
            stop.pointee = true
        }
    }
    if let foundID {
        defaults.set(foundID, forKey: key)
        return foundID
    }
    
    // Create a brand new album
    var newID: String?
    try? PHPhotoLibrary.shared().performChangesAndWait {
        let createReq = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: BundleIDs.appName)
        newID = createReq.placeholderForCreatedAssetCollection.localIdentifier
    }
    
    // Resolve placeholder → real localIdentifier
    if let placeholder = newID {
        let created = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [placeholder], options: nil)
        let realID = created.firstObject?.localIdentifier ?? placeholder
        defaults.set(realID, forKey: key)
        return realID
    }
    return nil
}
