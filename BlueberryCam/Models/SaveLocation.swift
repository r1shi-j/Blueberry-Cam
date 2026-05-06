import Foundation

final class SaveLocationBox: @unchecked Sendable {
    nonisolated(unsafe) var value: SaveLocation = .photos
}

enum SaveLocation: String, CaseIterable, Identifiable, Sendable {
    case photos = "Photos"
    case files = "Files"
    
    var id: String { rawValue }
    
    nonisolated static let storageKey = "saveLocation"
    
    nonisolated static var stored: SaveLocation {
        guard let value = UserDefaults.standard.string(forKey: storageKey),
              let location = SaveLocation(rawValue: value) else {
            return .photos
        }
        return location
    }
}
