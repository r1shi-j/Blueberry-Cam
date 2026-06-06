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
        static let manuallyUnlockedCustomisation = "manuallyUnlockedCustomisation"
        static let manuallyUnlockedFullCustomisation = "manuallyUnlockedFullCustomisation"
        static let didShowCustomisationUnlockMilestone = "didShowCustomisationUnlockMilestone"
        static let didShowFullCustomisationUnlockMilestone = "didShowFullCustomisationUnlockMilestone"
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
            validateSelectedIconAvailability()
        }
    }
    
    var shutterCountBurst: Int {
        didSet {
            defaults.set(shutterCountBurst, forKey: Keys.shutterCountBurst)
            validateSelectedThemeAvailability()
            validateSelectedIconAvailability()
        }
    }
    
    var manuallyUnlockedCustomisation: Bool {
        didSet {
            defaults.set(manuallyUnlockedCustomisation, forKey: Keys.manuallyUnlockedCustomisation)
            validateSelectedThemeAvailability()
            validateSelectedIconAvailability()
        }
    }
    
    var manuallyUnlockedFullCustomisation: Bool {
        didSet {
            defaults.set(manuallyUnlockedFullCustomisation, forKey: Keys.manuallyUnlockedFullCustomisation)
            validateSelectedThemeAvailability()
            validateSelectedIconAvailability()
        }
    }
    
    var didShowCustomisationUnlockMilestone: Bool {
        didSet {
            defaults.set(didShowCustomisationUnlockMilestone, forKey: Keys.didShowCustomisationUnlockMilestone)
        }
    }
    
    var didShowFullCustomisationUnlockMilestone: Bool {
        didSet {
            defaults.set(didShowFullCustomisationUnlockMilestone, forKey: Keys.didShowFullCustomisationUnlockMilestone)
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
    
    var hasUnlockedCustomisation: Bool {
        manuallyUnlockedCustomisation || hasUnlockedFullCustomisation || meetsStandardCustomisationRequirement
    }
    
    var hasUnlockedFullCustomisation: Bool {
        manuallyUnlockedFullCustomisation || meetsFullCustomisationRequirement
    }
    
    
    var selectedTheme: AppTheme {
        theme(for: selectedThemeID)
    }
    
    private var meetsStandardCustomisationRequirement: Bool {
        shutterCount >= 100 && shutterCountBurst >= 500
    }
    
    private var meetsFullCustomisationRequirement: Bool {
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
        manuallyUnlockedCustomisation = defaults.object(forKey: Keys.manuallyUnlockedCustomisation) as? Bool ?? false
        manuallyUnlockedFullCustomisation = defaults.object(forKey: Keys.manuallyUnlockedFullCustomisation) as? Bool ?? false
        didShowCustomisationUnlockMilestone = defaults.object(forKey: Keys.didShowCustomisationUnlockMilestone) as? Bool ?? false
        didShowFullCustomisationUnlockMilestone = defaults.object(forKey: Keys.didShowFullCustomisationUnlockMilestone) as? Bool ?? false
        
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
        validateSelectedIconAvailability()
    }
    
    func theme(for id: String) -> AppTheme {
        AppTheme.theme(for: id, customTheme: customTheme)
    }
    
    func unlockCustomisation(with guess: String) -> Bool {
        guard Self.sha256(guess) == Self.standardThemeUnlockKeyHash else {
            return false
        }
        
        manuallyUnlockedCustomisation = true
        return true
    }
    
    func unlockFullCustomisation(with guess: String) -> Bool {
        guard Self.sha256(guess) == Self.customThemeUnlockKeyHash else {
            return false
        }
        
        manuallyUnlockedFullCustomisation = true
        return true
    }
    
    
    func nextThemeUnlockMilestone() -> ThemeUnlockMilestone? {
        if meetsFullCustomisationRequirement, !didShowFullCustomisationUnlockMilestone {
            didShowFullCustomisationUnlockMilestone = true
            didShowCustomisationUnlockMilestone = true
            return .custom
        }
        
        if meetsStandardCustomisationRequirement, !didShowCustomisationUnlockMilestone {
            didShowCustomisationUnlockMilestone = true
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
        if id == AppTheme.customID { return hasUnlockedFullCustomisation }
        return hasUnlockedCustomisation
    }
    
    func resetShutterCount(_ target: ShutterCountResetTarget) {
        switch target {
            case .standard:
                shutterCount = 0
            case .burst:
                shutterCountBurst = 0
        }
        
        if !meetsStandardCustomisationRequirement {
            didShowCustomisationUnlockMilestone = false
        }
        if !meetsFullCustomisationRequirement {
            didShowFullCustomisationUnlockMilestone = false
        }
        if !hasUnlockedCustomisation {
            resetThemePreferences()
        }
    }
    
    func updateCustomThemeColor(_ color: Color, for keyPath: WritableKeyPath<CustomThemePalette, String>) {
        guard let hex = color.toHex() else { return }
        var updatedTheme = customTheme
        updatedTheme[keyPath: keyPath] = hex
        customTheme = updatedTheme
    }
    
    func canUseIcon(_ icon: AppIcon) -> Bool {
        switch icon {
            case .classic:
                return true
            case .blueberry:
                return hasUnlockedFullCustomisation
            case .blue, .green, .pink, .orange:
                return hasUnlockedCustomisation
        }
    }
    
    private func validateSelectedIconAvailability() {
        guard canUseIcon(selectedIcon) else {
            selectedIcon = .classic
            return
        }
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
