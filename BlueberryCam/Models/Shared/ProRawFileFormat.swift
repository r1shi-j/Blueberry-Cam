internal import AVFoundation

enum ProRawFileFormat: String, CaseIterable, Identifiable {
    case jpegLossless = "JPEG Lossless"
    case jpegXLLossless = "JPEG XL Lossless"
    case jpegXLLossy = "JPEG XL Lossy"
    
    var id: String { rawValue }
    
    var codecType: AVVideoCodecType {
        switch self {
            case .jpegLossless:
                    .jpeg
            case .jpegXLLossless, .jpegXLLossy:
                AVVideoCodecType(rawValue: "jxlc")
        }
    }
    
    var quality: Double {
        switch self {
            case .jpegLossless, .jpegXLLossless:
                1
            case .jpegXLLossy:
                0.99
        }
    }
    
    func rawFileFormat(maximumBitDepth: Int? = nil) -> [String: Any] {
        var format: [String: Any] = [
            AVVideoCodecKey: codecType,
            AVVideoQualityKey: quality
        ]
        
        if let maximumBitDepth {
            format[AVVideoAppleProRAWBitDepthKey] = maximumBitDepth
        }
        
        return format
    }
}
