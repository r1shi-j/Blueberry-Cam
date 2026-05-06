import Foundation

final class PhotoFilterBox: @unchecked Sendable {
    nonisolated(unsafe) var value: PhotoFilter = .off
}

enum PhotoFilter: String, CaseIterable, Identifiable {
    case off = "Off"
    case temperatureAndTint = "1980s"
    case chrome = "Chrome"
    case instant = "Instant"
    case sepia = "Sepia"
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
