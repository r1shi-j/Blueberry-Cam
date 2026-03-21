import Foundation

enum BundleIDs {
    static nonisolated let appID = "com.blueberrycam"
    static let fullBundleID = "com.jansari.rishi.blueberrycam"
    static let appName = "Blueberry Cam"
    static let appNameP: LocalizedStringResource = "Blueberry Cam"
    static nonisolated let photoAlbumStorageKey = "blueberryCamAlbumID"
    static let appSymbolName = "camera.blueberry"
    static let appSymbolReversedName = "camera.blueberry.reversed"
    
    static func UTI(isDNG: Bool, isHEIF: Bool) -> String {
        isDNG ? "com.adobe.raw-image" : (isHEIF ? "public.heic" : "public.jpeg")
    }
}
