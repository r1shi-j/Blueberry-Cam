import Foundation

enum AppIcon: String, CaseIterable {
    case classic = "Classic Blueberry"
    case blue = "Wireframe Blueberry"
    case green = "Wireframe Forest"
    case pink = "Wireframe Rose"
    case orange = "Wireframe Fall"
    
    var bundleValue: String? {
        switch self {
            case .classic: nil
            case .blue: "WireframeBlue"
            case .green: "WireframeGreen"
            case .pink: "WireframePink"
            case .orange: "WireframeOrange"
        }
    }
    
    var previewImageName: String {
        switch self {
            case .classic: "BlueberryCamIconPreview"
            case .blue: "WireframeBluePreview"
            case .green: "WireframeGreenPreview"
            case .pink: "WireframePinkPreview"
            case .orange: "WireframeOrangePreview"
        }
    }
}
