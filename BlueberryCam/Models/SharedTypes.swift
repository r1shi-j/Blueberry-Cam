import AVFoundation
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
final class CaptureModeBox: @unchecked Sendable {
    nonisolated(unsafe) var value: CaptureMode = .jpeg
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
    case wide
    case front
    
    var isFront: Bool { self == .front }
    
    var deviceType: AVCaptureDevice.DeviceType { .builtInWideAngleCamera }
    
    var position: AVCaptureDevice.Position { isFront ? .front : .back }
    
    var zoomFactor: CGFloat { 1.0 }
}

// MARK: - AppView
enum AppView: String, CaseIterable, Hashable {
    case clean = "Clean"
    case standard = "Standard"
    case settings = "Settings"
    
    var index: Int {
        switch self {
            case .clean: return 0
            case .standard: return 1
            case .settings: return 2
        }
    }
    
    static func fromIndex(_ x: Int) -> AppView {
        switch x {
            case 0: return .clean
            case 1: return .standard
            case 2: return .settings
            default: return .standard
        }
    }
}

// MARK: - ResolveAlbumID
nonisolated func resolveAlbumID() -> String? {
    let key = BundleIDs.photoAlbumStorageKey
    let defaults = UserDefaults.standard
    
    if let savedID = defaults.string(forKey: key) {
        let existing = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [savedID], options: nil)
        if existing.firstObject != nil {
            return savedID
        }
    }
    
    let fetch = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: nil)
    var foundID: String?
    fetch.enumerateObjects { col, _, stop in
        if col.localizedTitle == BundleIDs.appName {
            foundID = col.localIdentifier
            stop.pointee = true
        }
    }
    if let foundID = foundID {
        defaults.set(foundID, forKey: key)
        return foundID
    }
    
    var newID: String?
    try? PHPhotoLibrary.shared().performChangesAndWait {
        let createReq = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: BundleIDs.appName)
        newID = createReq.placeholderForCreatedAssetCollection.localIdentifier
    }
    
    if let placeholder = newID {
        let created = PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [placeholder], options: nil)
        let realID = created.firstObject?.localIdentifier ?? placeholder
        defaults.set(realID, forKey: key)
        return realID
    }
    return nil
}
