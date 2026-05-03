import Foundation

enum TimerMode: String, CaseIterable, Identifiable {
    case off
    case threeSeconds
    case fiveSeconds
    case tenSeconds
    
    var id: String { rawValue }
    
    var label: String {
        switch self {
            case .off: ""
            case .threeSeconds: "3s"
            case .fiveSeconds: "5s"
            case .tenSeconds: "10s"
        }
    }
    
    var duration: Duration? {
        switch self {
            case .off: nil
            case .threeSeconds: .seconds(3)
            case .fiveSeconds: .seconds(5)
            case .tenSeconds: .seconds(10)
        }
    }
    
    var seconds: Int? {
        switch self {
            case .off: nil
            case .threeSeconds: 3
            case .fiveSeconds: 5
            case .tenSeconds: 10
        }
    }
}
