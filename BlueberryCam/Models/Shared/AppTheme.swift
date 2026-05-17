import SwiftUI

struct CustomThemePalette: Equatable {
    static let defaults = CustomThemePalette(
        backgroundHex: Color.black.toHex() ?? "000000",
        accentHex: Color.yellow.toHex() ?? "FFFF00",
        shutterRawHex: Color.blue.mix(with: .mint, by: 0.5).opacity(0.4).toHex() ?? "007FFF66",
        shutterProRawHex: Color.purple.mix(with: .pink, by: 0.35).opacity(0.4).toHex() ?? "AF40D966",
        shutterBurstHex: Color.yellow.opacity(0.8).toHex() ?? "FFFF00CC"
    )
    
    var backgroundHex: String
    var accentHex: String
    var shutterRawHex: String
    var shutterProRawHex: String
    var shutterBurstHex: String
}

struct AppTheme: Equatable, Identifiable {
    let id: String
    let name: String
    let background: Color
    let accent: Color
    let shutterProcessed: Color
    let shutterRaw: Color
    let shutterProRaw: Color
    let shutterBurst: Color
    let readoutColor: Color
    
    static let defaultID = "classic"
    static let customID = "custom"
    
    init(id: String, name: String, background: Color, accent: Color, shutterRaw: Color, shutterProRaw: Color, shutterBurst: Color) {
        self.id = id
        self.name = name
        self.background = background
        self.accent = accent
        self.shutterProcessed = .white.opacity(0.2)
        self.shutterRaw = shutterRaw
        self.shutterProRaw = shutterProRaw
        self.shutterBurst = shutterBurst
        self.readoutColor = accent.opacity(0.88)
    }
    
    static let classic: AppTheme = AppTheme(
        id: defaultID,
        name: "Classic",
        background: .black,
        accent: .yellow,
        shutterRaw: .blue.mix(with: .mint, by: 0.5).opacity(0.4),
        shutterProRaw: .purple.mix(with: .pink, by: 0.35).opacity(0.4),
        shutterBurst: .yellow.opacity(0.8),
    )
    
    static let standard: [AppTheme] = [
        AppTheme(
            id: "blueberry",
            name: "Blueberry",
            background: .blue.opacity(0.3),
            accent: .cyan,
            shutterRaw: .blue.opacity(0.5),
            shutterProRaw: .teal.mix(with: .mint, by: 0.42).opacity(0.5),
            shutterBurst: .blue.mix(with: .pink, by: 0.36).opacity(0.65)
        ),
        AppTheme(
            id: "forest",
            name: "Forest",
            background: .green.opacity(0.3),
            accent: .mint,
            shutterRaw: .green.mix(with: .mint, by: 0.68).opacity(0.5),
            shutterProRaw: .green.mix(with: .pink, by: 0.38).opacity(0.5),
            shutterBurst: .purple.mix(with: .mint, by: 0.52).opacity(0.65)
        ),
        AppTheme(
            id: "rose",
            name: "Rose",
            background: .pink.opacity(0.3),
            accent: .pink,
            shutterRaw: .pink.mix(with: .purple, by: 0.38).opacity(0.5),
            shutterProRaw: .pink.mix(with: .orange, by: 0.66).opacity(0.65),
            shutterBurst: .blue.mix(with: .pink, by: 0.36).opacity(0.5)
        ),
        AppTheme(
            id: "fall",
            name: "Fall",
            background: .orange.opacity(0.3),
            accent: .orange,
            shutterRaw: .orange.mix(with: .pink, by: 0.44).opacity(0.5),
            shutterProRaw: .orange.mix(with: .purple, by: 0.48).opacity(0.5),
            shutterBurst: .blue.mix(with: .brown, by: 0.46).opacity(0.65)
        )
    ]
    
    private enum iphone17ProColors: String {
        case cosmicOrange, deepBlue, silver
        
        var name: String {
            switch self {
                case .cosmicOrange:
                    "Cosmic Orange"
                case .deepBlue:
                    "Deep Blue"
                case .silver:
                    "Silver"
            }
        }
        
        var color: Color {
            switch self {
                case .cosmicOrange: return Color(uiColor: UIColor(red: 247/255, green: 126/255, blue: 45/255, alpha: 1)) // F77E2D
                case .deepBlue: return Color(uiColor: UIColor(red: 50/255, green: 55/255, blue: 74/255, alpha: 1)) // 32374A
                case .silver: return Color(uiColor: UIColor(red: 245/255, green: 245/255, blue: 245/255, alpha: 1)) // F5F5F5
            }
        }
    }
    
    static let iphone17pro: [AppTheme] = [
        AppTheme(
            id: iphone17ProColors.cosmicOrange.rawValue,
            name: iphone17ProColors.cosmicOrange.name,
            background: iphone17ProColors.cosmicOrange.color.opacity(0.3),
            accent: iphone17ProColors.cosmicOrange.color,
            shutterRaw: .mint.mix(with: .orange, by: 0.3).opacity(0.5),
            shutterProRaw: .yellow.mix(with: .purple, by: 0.4).opacity(0.5),
            shutterBurst: .yellow.mix(with: .blue, by: 0.2).opacity(0.65)
        ),
        AppTheme(
            id: iphone17ProColors.deepBlue.rawValue,
            name: iphone17ProColors.deepBlue.name,
            background: iphone17ProColors.deepBlue.color.opacity(0.4),
            accent: iphone17ProColors.deepBlue.color.mix(with: .blue, by: 0.14).mix(with: .white, by: 0.24),
            shutterRaw: .blue.mix(with: .black, by: 0.4).opacity(0.5),
            shutterProRaw: .blue.mix(with: .purple, by: 0.36).mix(with: .black, by: 0.2).opacity(0.5),
            shutterBurst: .red.mix(with: .black, by: 0.4).opacity(0.65)
        ),
        AppTheme(
            id: iphone17ProColors.silver.rawValue,
            name: iphone17ProColors.silver.name,
            background: iphone17ProColors.silver.color.opacity(0.2),
            accent: iphone17ProColors.silver.color,
            shutterRaw: .mint.mix(with: .blue, by: 0.2).mix(with: .black, by: 0.2).opacity(0.5),
            shutterProRaw: .purple.mix(with: .mint, by: 0.45).opacity(0.5),
            shutterBurst: .yellow.mix(with: .black, by: 0.5).opacity(0.65)
        )
    ]
    
    static func custom(from customTheme: CustomThemePalette) -> AppTheme {
        AppTheme(
            id: customID,
            name: "Custom",
            background: Color(hex: customTheme.backgroundHex),
            accent: Color(hex: customTheme.accentHex),
            shutterRaw: Color(hex: customTheme.shutterRawHex),
            shutterProRaw: Color(hex: customTheme.shutterProRawHex),
            shutterBurst: Color(hex: customTheme.shutterBurstHex)
        )
    }
    
    static private var builtInThemes: [AppTheme] { [classic] + standard + iphone17pro }
    
    static func theme(for id: String, customTheme: CustomThemePalette = .defaults) -> AppTheme {
        if id == customID {
            return custom(from: customTheme)
        }
        
        return builtInThemes.first { $0.id == id } ?? classic
    }
    
    func isThemeSpecificToDevice() -> Bool {
        return AppTheme.iphone17pro.map(\.id).contains(self.id)
    }
}
