import Foundation

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
