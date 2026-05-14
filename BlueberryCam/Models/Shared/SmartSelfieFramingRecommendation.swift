import CoreGraphics
import Foundation

struct SmartSelfieFramingRecommendation: Equatable, Sendable {
    let aspectRatio: CaptureAspectRatioOption
    let zoomFactor: CGFloat
    
    func isApproximatelyEqual(to other: SmartSelfieFramingRecommendation) -> Bool {
        aspectRatio == other.aspectRatio && abs(zoomFactor - other.zoomFactor) < 0.04
    }
}
