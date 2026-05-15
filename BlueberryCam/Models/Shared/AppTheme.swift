import SwiftUI

struct AppTheme: Identifiable {
    let id: String
    let name: String
    let background: Color
    let accent: Color
    let shutterProcessed: Color
    let shutterRaw: Color
    let shutterProRaw: Color
    let shutterBurst: Color
    let shutterBurstCapturing: Color
    let readoutColor: Color
    
    static let defaultID = "default"
    
    static let all: [AppTheme] = [
        AppTheme(
            id: defaultID,
            name: "Default",
            background: .black,
            accent: .yellow,
            shutterProcessed: .white.opacity(0.2),
            shutterRaw: .blue.mix(with: .mint, by: 0.5).opacity(0.4),
            shutterProRaw: .purple.mix(with: .pink, by: 0.35).opacity(0.4),
            shutterBurst: .yellow.opacity(0.8),
            shutterBurstCapturing: .yellow.mix(with: .orange, by: 0.2).opacity(0.6),
            readoutColor: .yellow.opacity(0.88)
        ),
        AppTheme(
            id: "blueberry",
            name: "Blueberry",
            background: .blue.opacity(0.3),
            accent: .cyan,
            shutterProcessed: .white.opacity(0.2),
            shutterRaw: .blue.mix(with: .blue, by: 0.28).opacity(0.46),
            shutterProRaw: .blue.mix(with: .pink, by: 0.36).opacity(0.5),
            shutterBurst: .teal.mix(with: .mint, by: 0.22).opacity(0.84),
            shutterBurstCapturing: .teal.mix(with: .mint, by: 0.32).opacity(0.56),
            readoutColor: .cyan.opacity(0.88)
        ),
        AppTheme(
            id: "forest",
            name: "Forest",
            background: .green.opacity(0.3),
            accent: .mint,
            shutterProcessed: .white.opacity(0.2),
            shutterRaw: .green.mix(with: .mint, by: 0.68).opacity(0.46),
            shutterProRaw: .green.mix(with: .pink, by: 0.38).opacity(0.48),
            shutterBurst: .purple.mix(with: .mint, by: 0.52).opacity(0.84),
            shutterBurstCapturing: .purple.mix(with: .mint, by: 0.34).opacity(0.66),
            readoutColor: .mint.opacity(0.88)
        ),
        AppTheme(
            id: "rose",
            name: "Rose",
            background: .pink.opacity(0.3),
            accent: .pink,
            shutterProcessed: .white.opacity(0.2),
            shutterRaw: .pink.mix(with: .purple, by: 0.38).opacity(0.52),
            shutterProRaw: .blue.mix(with: .pink, by: 0.34).opacity(0.54),
            shutterBurst: .pink.mix(with: .orange, by: 0.36).opacity(0.84),
            shutterBurstCapturing: .pink.mix(with: .yellow, by: 0.32).opacity(0.66),
            readoutColor: .pink.opacity(0.88)
        ),
        AppTheme(
            id: "sunrise",
            name: "Sunrise",
            background: .orange.opacity(0.3),
            accent: .orange,
            shutterProcessed: .white.opacity(0.2),
            shutterRaw: .orange.mix(with: .pink, by: 0.44).opacity(0.50),
            shutterProRaw: .orange.mix(with: .purple, by: 0.58).opacity(0.42),
            shutterBurst: .blue.mix(with: .brown, by: 0.46).opacity(0.74),
            shutterBurstCapturing: .blue.mix(with: .orange, by: 0.46).opacity(0.74),
            readoutColor: .orange.opacity(0.88)
        )
    ]
    
    static func theme(for id: String) -> AppTheme {
        all.first { $0.id == id } ?? all[0]
    }
}
