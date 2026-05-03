import Foundation

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
