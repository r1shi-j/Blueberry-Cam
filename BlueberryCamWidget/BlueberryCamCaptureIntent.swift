import AppIntents
#if canImport(LockedCameraCapture)
import LockedCameraCapture
#endif

struct BlueberryCamContext: Codable, Sendable {
    var captureMode: String = "raw"
    
    nonisolated func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(captureMode, forKey: .captureMode)
    }
    
    nonisolated init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        captureMode = try container.decode(String.self, forKey: .captureMode)
    }
    
    init(captureMode: String = "raw") {
        self.captureMode = captureMode
    }
    
    private enum CodingKeys: String, CodingKey {
        case captureMode
    }
}

struct BlueberryCamCaptureIntent: CameraCaptureIntent {
    static let title: LocalizedStringResource = "Blueberry Cam"
    static let description = IntentDescription("Capture RAW photos with Blueberry Cam.")
    typealias AppContext = BlueberryCamContext
    
    func perform() async throws -> some IntentResult {
        return .result()
    }
}
