import Foundation

enum AppView: String, CaseIterable, Hashable {
    case hidden = "Hidden"
    case clean = "Clean"
    case standard = "Standard"
    case settings = "Settings"
    
    var index: Int {
        switch self {
            case .hidden: 0
            case .clean: 1
            case .standard: 2
            case .settings: 3
        }
    }
    
    static func fromIndex(_ x: Int) -> AppView {
        switch x {
            case 0: .hidden
            case 1: .clean
            case 2: .standard
            case 3: .settings
            default: .standard
        }
    }
}
