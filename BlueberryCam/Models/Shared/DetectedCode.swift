import Foundation

struct DetectedCode: Identifiable, Equatable {
    let id = UUID()
    let content: String
    let detectedAt: Date
    
    var linkURL: URL? {
        guard let url = URL(string: content), url.scheme != nil else { return nil }
        return url
    }
    
    var isLink: Bool {
        linkURL != nil
    }
}
