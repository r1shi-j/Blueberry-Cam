import Foundation

enum AppIcon: String, CaseIterable {
    case classic = "Blueberry Camera"
    case blue = "Wireframe Blueberry"
    case green = "Wireframe Forest"
    case pink = "Wireframe Rose"
    case orange = "Wireframe Fall"
    case blueberry = "Blueberry"
    
    var bundleValue: String? {
        switch self {
            case .classic: nil
            case .blue: "WireframeBlue"
            case .green: "WireframeGreen"
            case .pink: "WireframePink"
            case .orange: "WireframeOrange"
            case .blueberry: "Blueberry"
        }
    }
    
    var previewImageName: String {
        switch self {
            case .classic: "BlueberryCamPreview"
            case .blue: "WireframeBluePreview"
            case .green: "WireframeGreenPreview"
            case .pink: "WireframePinkPreview"
            case .orange: "WireframeOrangePreview"
            case .blueberry: "BlueberryPreview"
        }
    }
}
