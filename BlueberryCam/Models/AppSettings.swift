import CryptoKit
import Foundation
import SwiftUI

enum ThemeUnlockMilestone {
    case standard
    case custom
}

enum ShutterCountResetTarget {
    case standard
    case burst
    
    var confirmationTitle: String {
        switch self {
            case .standard:
                "Are you sure you want to reset the shutter count, this cannot be undone."
            case .burst:
                "Are you sure you want to reset the burst shutter count, this cannot be undone."
        }
    }
}

@MainActor
@Observable
final class AppSettings {
    private enum Keys {
        static let selectedIconID = "selectedAppIconID"
        static let selectedThemeID = "selectedAppThemeID"
        static let usesAppThemeReadouts = "usesAppThemeReadouts"
        static let shutterCount = "shutterCount"
        static let shutterCountBurst = "shutterCountBurst"
        static let manuallyUnlockedThemes = "manuallyUnlockedThemes"
        static let manuallyUnlockedCustomThemes = "manuallyUnlockedCustomThemes"
        static let didShowThemeUnlockMilestone = "didShowThemeUnlockMilestone"
        static let didShowCustomThemeUnlockMilestone = "didShowCustomThemeUnlockMilestone"
        static let customBackground = "customTheme_background"
        static let customAccent = "customTheme_accent"
        static let customShutterRaw = "customTheme_shutterRaw"
        static let customShutterProRaw = "customTheme_shutterProRaw"
        static let customShutterBurst = "customTheme_shutterBurst"
    }
    
    private static let standardThemeUnlockKeyHash = "a7bcef26e0354c8fa294740eb7f635c80b37420632c5e92a75becd5e5881f33d" // BlueberryCam_08052026
    private static let customThemeUnlockKeyHash = "1572a13a94bdbea2aa697400cb531bd3300f3f60faef847c5c7fc09331f81599" // BlueberryCam_08052026+
    
    private let defaults: UserDefaults
    
    var lockedCaptureHapticTrigger = 0
    
    var selectedIcon: AppIcon {
        didSet {
            guard selectedIcon != oldValue else { return }
            
            let newVal = selectedIcon.bundleValue
            guard UIApplication.shared.alternateIconName != newVal else { return }
            
            let savedIcon = selectedIcon
            UIApplication.shared.setAlternateIconName(newVal) { [weak self] error in
                Task { @MainActor [weak self] in
                    if error != nil {
//                        print("❌", error)
                        self?.selectedIcon = oldValue
                    } else {
                        self?.defaults.set(savedIcon.rawValue, forKey: Keys.selectedIconID)
                    }
                }
            }
        }
    }
    
    var selectedThemeID: String {
        didSet {
            defaults.set(selectedThemeID, forKey: Keys.selectedThemeID)
            if selectedThemeID == AppTheme.defaultID {
                usesAppThemeReadouts = false
            }
        }
    }
    
    var usesAppThemeReadouts: Bool {
        didSet {
            defaults.set(usesAppThemeReadouts, forKey: Keys.usesAppThemeReadouts)
        }
    }
    
    var shutterCount: Int {
        didSet {
            defaults.set(shutterCount, forKey: Keys.shutterCount)
            validateSelectedThemeAvailability()
        }
    }
    
    var shutterCountBurst: Int {
        didSet {
            defaults.set(shutterCountBurst, forKey: Keys.shutterCountBurst)
            validateSelectedThemeAvailability()
        }
    }
    
    var manuallyUnlockedThemes: Bool {
        didSet {
            defaults.set(manuallyUnlockedThemes, forKey: Keys.manuallyUnlockedThemes)
            validateSelectedThemeAvailability()
        }
    }
    
    var manuallyUnlockedCustomThemes: Bool {
        didSet {
            defaults.set(manuallyUnlockedCustomThemes, forKey: Keys.manuallyUnlockedCustomThemes)
            validateSelectedThemeAvailability()
        }
    }
    
    private var didShowThemeUnlockMilestone: Bool {
        didSet {
            defaults.set(didShowThemeUnlockMilestone, forKey: Keys.didShowThemeUnlockMilestone)
        }
    }
    
    private var didShowCustomThemeUnlockMilestone: Bool {
        didSet {
            defaults.set(didShowCustomThemeUnlockMilestone, forKey: Keys.didShowCustomThemeUnlockMilestone)
        }
    }
    
    var customTheme: CustomThemePalette {
        didSet {
            defaults.set(customTheme.backgroundHex, forKey: Keys.customBackground)
            defaults.set(customTheme.accentHex, forKey: Keys.customAccent)
            defaults.set(customTheme.shutterRawHex, forKey: Keys.customShutterRaw)
            defaults.set(customTheme.shutterProRawHex, forKey: Keys.customShutterProRaw)
            defaults.set(customTheme.shutterBurstHex, forKey: Keys.customShutterBurst)
        }
    }
    
    var hasUnlockedThemes: Bool {
        manuallyUnlockedThemes || hasUnlockedCustomThemes || meetsStandardThemeRequirement
    }
    
    var hasUnlockedCustomThemes: Bool {
        manuallyUnlockedCustomThemes || meetsCustomThemeRequirement
    }
    
    var selectedTheme: AppTheme {
        theme(for: selectedThemeID)
    }
    
    private var meetsStandardThemeRequirement: Bool {
        shutterCount >= 100 && shutterCountBurst >= 500
    }
    
    private var meetsCustomThemeRequirement: Bool {
        shutterCount >= 1000 && shutterCountBurst >= 1000
    }
    
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        
        let savedRaw = defaults.string(forKey: Keys.selectedIconID) ?? ""
        selectedIcon = AppIcon(rawValue: savedRaw) ?? .classic
        selectedThemeID = defaults.string(forKey: Keys.selectedThemeID) ?? AppTheme.defaultID
        usesAppThemeReadouts = defaults.object(forKey: Keys.usesAppThemeReadouts) as? Bool ?? false
        shutterCount = defaults.integer(forKey: Keys.shutterCount)
        shutterCountBurst = defaults.integer(forKey: Keys.shutterCountBurst)
        manuallyUnlockedThemes = defaults.object(forKey: Keys.manuallyUnlockedThemes) as? Bool ?? false
        manuallyUnlockedCustomThemes = defaults.object(forKey: Keys.manuallyUnlockedCustomThemes) as? Bool ?? false
        didShowThemeUnlockMilestone = defaults.object(forKey: Keys.didShowThemeUnlockMilestone) as? Bool ?? false
        didShowCustomThemeUnlockMilestone = defaults.object(forKey: Keys.didShowCustomThemeUnlockMilestone) as? Bool ?? false
        
        let defaultTheme = CustomThemePalette.defaults
        customTheme = CustomThemePalette(
            backgroundHex: defaults.string(forKey: Keys.customBackground) ?? defaultTheme.backgroundHex,
            accentHex: defaults.string(forKey: Keys.customAccent) ?? defaultTheme.accentHex,
            shutterRawHex: defaults.string(forKey: Keys.customShutterRaw) ?? defaultTheme.shutterRawHex,
            shutterProRawHex: defaults.string(forKey: Keys.customShutterProRaw) ?? defaultTheme.shutterProRawHex,
            shutterBurstHex: defaults.string(forKey: Keys.customShutterBurst) ?? defaultTheme.shutterBurstHex
        )
        
        if selectedThemeID == AppTheme.defaultID {
            usesAppThemeReadouts = false
        }
        validateSelectedThemeAvailability()
    }
    
    func theme(for id: String) -> AppTheme {
        AppTheme.theme(for: id, customTheme: customTheme)
    }
    
    func unlockThemes(with guess: String) -> Bool {
        guard Self.sha256(guess) == Self.standardThemeUnlockKeyHash else {
            return false
        }
        
        manuallyUnlockedThemes = true
        return true
    }
    
    func unlockCustomThemes(with guess: String) -> Bool {
        guard Self.sha256(guess) == Self.customThemeUnlockKeyHash else {
            return false
        }
        
        manuallyUnlockedCustomThemes = true
        return true
    }
    
    func nextThemeUnlockMilestone() -> ThemeUnlockMilestone? {
        if meetsCustomThemeRequirement, !didShowCustomThemeUnlockMilestone {
            didShowCustomThemeUnlockMilestone = true
            didShowThemeUnlockMilestone = true
            return .custom
        }
        
        if meetsStandardThemeRequirement, !didShowThemeUnlockMilestone {
            didShowThemeUnlockMilestone = true
            return .standard
        }
        return nil
    }
    
    func resetThemePreferences() {
        selectedThemeID = AppTheme.defaultID
        usesAppThemeReadouts = false
    }
    
    func canUseTheme(id: String) -> Bool {
        if id == AppTheme.defaultID { return true }
        if id == AppTheme.customID { return hasUnlockedCustomThemes }
        return hasUnlockedThemes
    }
    
    func resetShutterCount(_ target: ShutterCountResetTarget) {
        switch target {
            case .standard:
                shutterCount = 0
            case .burst:
                shutterCountBurst = 0
        }
        
        if !meetsStandardThemeRequirement {
            didShowThemeUnlockMilestone = false
        }
        if !meetsCustomThemeRequirement {
            didShowCustomThemeUnlockMilestone = false
        }
        if !hasUnlockedThemes {
            resetThemePreferences()
        }
    }
    
    func updateCustomThemeColor(_ color: Color, for keyPath: WritableKeyPath<CustomThemePalette, String>) {
        guard let hex = color.toHex() else { return }
        var updatedTheme = customTheme
        updatedTheme[keyPath: keyPath] = hex
        customTheme = updatedTheme
    }
    
    private func validateSelectedThemeAvailability() {
        guard canUseTheme(id: selectedThemeID) else {
            resetThemePreferences()
            return
        }
    }
    
    private static func sha256(_ string: String) -> String {
        let data = Data(string.utf8)
        let hash = SHA256.hash(data: data)
        
        return hash.map { byte in
            let hex = String(byte, radix: 16)
            return hex.count == 1 ? "0\(hex)" : hex
        }
        .joined()
    }
}
