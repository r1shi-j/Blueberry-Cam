import UIKit

enum DeviceModel {
    static var identifier: String {
#if targetEnvironment(simulator)
        return ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? "Simulator"
#else
        var systemInfo = utsname()
        uname(&systemInfo)
        
        return withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(cString: $0)
            }
        }
#endif
    }
    
    static var isIphone17ProSeries: Bool {
        isIPhone17Pro || isIPhone17ProMax
    }
    
    static var isIPhone17Pro: Bool {
        identifier == "iPhone18,1"
    }
    
    static var isIPhone17ProMax: Bool {
        identifier == "iPhone18,2"
    }
}
