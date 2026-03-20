internal import AVFoundation
import CoreMedia
import Photos
import SwiftUI

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
    case dither = "Dither"
    case mono = "Mono"
    case tonal = "Tonal"
    case noir = "Noir"
    case thermal = "Thermal"
    case xRay = "X-Ray"
    case comic = "Comic"
    case lineScreen = "Line Screen"
    case pixellate = "Pixellate"
    case lineOverlay = "Line Overlay"
    case kaleidoscope = "Kaleidoscope"
    case bumpDistortion = "Bump Distortion"
    case twirlDistortion = "Twirl Distortion"
    case motionBlur = "Motion Blur"
    case zoomBlur = "Zoom Blur"
    case lightTunnel = "Light Tunnel"
    case droste = "Droste"
    case glassLozenge = "Glass Lozenge"
    case fisheye = "Fisheye"
    var id: String { rawValue }
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
            case .frontUltraWide: return "0.87"
            case .front: return "0.95"
            case .ultraWide: return "0.5"
            case .wide: return "1"
            case .tele2x: return "2"
            case .tele4x: return "4"
            case .tele8x: return "8"
        }
    }
    
    var isFront: Bool { self == .front || self == .frontUltraWide }
    
    var deviceType: AVCaptureDevice.DeviceType {
        switch self {
            case .frontUltraWide: return .builtInUltraWideCamera
            case .front: return .builtInWideAngleCamera
            case .ultraWide: return .builtInUltraWideCamera
            case .wide, .tele2x: return .builtInWideAngleCamera
            case .tele4x, .tele8x: return .builtInTelephotoCamera
        }
    }
    
    var position: AVCaptureDevice.Position { isFront ? .front : .back }
    
    var zoomFactor: CGFloat {
        switch self {
            case .tele2x: return 2.0
            case .tele8x: return 2.0
            default: return 1.0
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
            case .clean:    return 0
            case .standard: return 1
            case .settings: return 2
        }
    }
    
    static func fromIndex(_ x: Int) -> AppView {
        switch x {
            case 0:  return .clean
            case 1:  return .standard
            case 2:  return .settings
            default: return .standard
        }
    }
}

// MARK: - ResolveAlbumID -
// Same resolveAlbumID logic as CameraModel — finds or creates "Blueberry Cam" album
func resolveAlbumID() -> String? {
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
