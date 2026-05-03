internal import AVFoundation
import Foundation

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

enum ResolutionPreference: String, CaseIterable, Identifiable {
    case efficient = "Efficient"
    case max = "Max"
    var id: String { rawValue }
}
