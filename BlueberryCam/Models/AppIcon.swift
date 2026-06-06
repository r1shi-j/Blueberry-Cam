import Foundation

enum AppIcon: String, CaseIterable {
    case classic = "Blueberry Camera"
    case blueberry = "Blueberry"
    case blue = "Wireframe Blueberry"
    case green = "Wireframe Forest"
    case pink = "Wireframe Rose"
    case orange = "Wireframe Fall"
    
    var bundleValue: String? {
        switch self {
            case .classic: nil
            case .blueberry: "Blueberry"
            case .blue: "WireframeBlue"
            case .green: "WireframeGreen"
            case .pink: "WireframePink"
            case .orange: "WireframeOrange"
        }
    }
    
    var previewImageName: String {
        switch self {
            case .classic: "BlueberryCamPreview"
            case .blueberry: "BlueberryPreview"
            case .blue: "WireframeBluePreview"
            case .green: "WireframeGreenPreview"
            case .pink: "WireframePinkPreview"
            case .orange: "WireframeOrangePreview"
        }
    }
}
