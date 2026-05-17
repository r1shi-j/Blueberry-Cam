import SwiftUI

struct AppThemeSelectionView: View {
    @Bindable var appSettings: AppSettings
    
    @State private var previewingThemeID: String
    @State private var isShowingLockedAlert = false
    @State private var isShowingLockedCustomAlert = false
    @State private var isShowingUnlockedAlert = false
    @State private var isShowingIncorrectUnlockAlert = false
    @State private var isShowingIncorrectCustomUnlockAlert = false
    @State private var unlockThemesGuess = ""
    @State private var unlockThemesCustomGuess = ""
    @State private var selectedThemeBeforeUnlock: String?
    @State private var selectionHapticTrigger = 0
    
    init(appSettings: AppSettings) {
        self.appSettings = appSettings
        self._previewingThemeID = State(initialValue: appSettings.selectedThemeID)
    }
    
    private var themesToShow: [AppTheme] {
        var themes: [AppTheme] = [.classic]
        themes += AppTheme.standard
        if DeviceModel.isIphone17ProSeries {
            themes += AppTheme.iphone17pro
        }
        themes += [appSettings.theme(for: AppTheme.customID)]
        return themes
    }
    
    private var previewingTheme: AppTheme {
        appSettings.theme(for: previewingThemeID)
    }
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
                .overlay(previewingTheme.background)
            
            ScrollView {
                VStack(spacing: 0) {
                    themeList()
                    Divider().padding(.vertical)
                    Text("Theme Preview")
                        .font(.caption)
                        .fontWidth(.expanded)
                        .fontWeight(.bold)
                    AppThemePreview(theme: previewingTheme, appSettings: appSettings)
                }
                .padding()
            }
            .scrollIndicators(.hidden)
        }
        .sensoryFeedback(.selection, trigger: selectionHapticTrigger)
        .environment(\.colorScheme, .dark)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("App Theme")
                    .font(.system(size: 18, weight: .bold, design: .serif))
                    .foregroundStyle(.white)
            }
            //            ToolbarItem(placement: .topBarTrailing) {
            //                Button("Debug", systemImage: "hammer.fill") {
            //                    appSettings.selectedThemeID = AppTheme.defaultID
            //                    previewingThemeID = AppTheme.defaultID
            //                    appSettings.manuallyUnlockedThemes.toggle()
            //                    appSettings.manuallyUnlockedCustomThemes = appSettings.manuallyUnlockedThemes
            //                    appSettings.didShowCustomThemeUnlockMilestone = appSettings.manuallyUnlockedThemes
            //                    appSettings.didShowThemeUnlockMilestone = appSettings.didShowCustomThemeUnlockMilestone
            //                }
            //            }
            ToolbarItem(placement: .topBarTrailing) {
                if !appSettings.hasUnlockedThemes {
                    Button("Locked", systemImage: "lock.fill") {
                        isShowingLockedAlert = true
                    }
                } else {
                    if !appSettings.hasUnlockedCustomThemes {
                        Button("Locked", systemImage: "lock.fill") {
                            isShowingLockedCustomAlert = true
                        }
                    } else {
                        Button("Unlocked", systemImage: "lock.open.fill") {
                            isShowingUnlockedAlert = true
                        }
                    }
                }
            }
        }
        .alert("Requirements not met to unlock app themes.", isPresented: $isShowingLockedAlert) {
            SecureField("Unlock Themes Key", text: $unlockThemesGuess)
                .onSubmit {
                    submitThemeUnlockKey()
                }
            Button("Cancel", role: .cancel, action: resetUnlockState)
            Button("Unlock", action: submitThemeUnlockKey)
        } message: {
            Text("To unlock app themes, your standard shutter count must be at least 100, and burst count at least 500.\nYou can check your statistics at the bottom of settings, or below the photos link shortcut to the left of the shutter button.\nAlternatively, if you have an unlock key enter it below.")
        }
        .alert("Requirements not met to unlock custom app themes.", isPresented: $isShowingLockedCustomAlert) {
            SecureField("Unlock Custom Themes Key", text: $unlockThemesCustomGuess)
                .onSubmit {
                    submitCustomThemeUnlockKey()
                }
            Button("Cancel", role: .cancel, action: resetUnlockState)
            Button("Unlock", action: submitCustomThemeUnlockKey)
        } message: {
            Text("To unlock custom app themes, your standard shutter count must be at least 1000, and burst count at least 1000.\nYou can check your statistics at the bottom of settings, or below the photos link shortcut to the left of the shutter button.\nAlternatively, if you have an unlock key enter it below.")
        }
        .alert("Incorrect unlock key", isPresented: $isShowingIncorrectUnlockAlert) {
            Button("Cancel", role: .cancel, action: resetUnlockState)
            Button("Try Again") {
                isShowingLockedAlert = true
            }
        } message: {
            Text("Check the unlock key and try again.")
        }
        .alert("Incorrect custom unlock key", isPresented: $isShowingIncorrectCustomUnlockAlert) {
            Button("Cancel", role: .cancel, action: resetUnlockState)
            Button("Try Again") {
                isShowingLockedCustomAlert = true
            }
        } message: {
            Text("Check the custom unlock key and try again.")
        }
        .alert("All themes are unlocked!", isPresented: $isShowingUnlockedAlert) { }
    }
    
    // MARK: - Subviews
    private func themeList() -> some View {
        VStack(spacing: 0) {
            ForEach(themesToShow) { theme in
                themeRow(theme)
                if let last = themesToShow.last, theme != last {
                    Divider()
                }
            }
        }
        .ignoresSafeArea(.keyboard)
        .padding(.horizontal)
        .glassEffect(.regular.tint(.black.opacity(0.18)), in: .rect(cornerRadius: 24))
    }
    
    private func themeRow(_ theme: AppTheme) -> some View {
        Button {
            handleThemeClicked(theme)
        } label: {
            HStack {
                themeName(theme)
                Spacer()
                if theme.isThemeSpecificToDevice() {
                    iphone17ProBadge(theme.accent)
                        .padding(.trailing)
                }
                if theme.id == AppTheme.customID {
                    customBadge(theme.accent)
                        .padding(.trailing)
                }
                if !appSettings.hasUnlockedThemes && theme.id != AppTheme.customID {
                    previewButton(theme)
                        .opacity(theme.id == previewingThemeID ? 0 : 1)
                }
                tickOrLockIndicator(theme)
                    .padding(.leading)
            }
            .contentShape(.rect)
            .animation(Animations.easeInOut, value: appSettings.hasUnlockedThemes)
            .animation(Animations.easeInOut, value: appSettings.hasUnlockedCustomThemes)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 14)
        .buttonStyle(.plain)
        .disabled(!appSettings.hasUnlockedThemes && theme.id == AppTheme.customID)
    }
    
    private func themeName(_ theme: AppTheme) -> some View {
        Text(theme.name)
            .foregroundStyle(.primary)
            .padding(.vertical, 10)
    }
    
    private func iphone17ProBadge(_ accent: Color) -> some View {
        ZStack {
            Image(systemName: "iphone.gen3.sizes")
                .font(.system(size: 16))
                .foregroundStyle(accent)
            
            let text = "  IPHONE 17 PRO SERIES •"
            let characters = Array(text)
            let totalAngle: Double = 360
            let radius: CGFloat = 17
            
            ForEach(0..<characters.count, id: \.self) { index in
                let angle = -totalAngle/2 + (totalAngle / Double(characters.count - 1)) * Double(index)
                Text(String(characters[index]))
                    .font(.system(size: 6.5, weight: .bold, design: .rounded))
                    .offset(y: -radius)
                    .rotationEffect(.degrees(angle))
            }
        }
        .foregroundStyle(.secondary)
        .frame(width: 40, height: 40)
    }
    
    private func customBadge(_ accent: Color) -> some View {
        Image(systemName: "iphone.pattern.diagonalline.on.rectangle.portrait.dashed")
            .font(.system(size: 18))
            .foregroundStyle(accent)
            .frame(width: 40, height: 40)
    }
    
    private func previewButton(_ theme: AppTheme) -> some View {
        Button("Preview") {
            guard previewingThemeID != theme.id else { return }
            selectionHapticTrigger += 1
            withAnimation(Animations.easeInOut) {
                previewingThemeID = theme.id
            }
        }
        .font(.caption)
        .fontWidth(.expanded)
        .bold()
        .tint(theme.accent)
        .buttonStyle(.glassProminent)
        .transition(.opacity.combined(with: .scale(scale: 0.92)))
    }
    
    private func tickOrLockIndicator(_ theme: AppTheme) -> some View {
        Group {
            if appSettings.selectedThemeID == theme.id {
                Image(systemName: "checkmark")
                    .foregroundStyle(theme.accent)
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.bounce, value: appSettings.selectedThemeID)
            } else {
                if !appSettings.hasUnlockedCustomThemes && theme.id == AppTheme.customID {
                    Image(systemName: "lock")
                        .transition(.opacity.combined(with: .scale(scale: 0.85)))
                } else if !appSettings.hasUnlockedThemes {
                    Image(systemName: "lock.fill")
                        .transition(.opacity.combined(with: .scale(scale: 0.85)))
                } else {
                    Image(systemName: "checkmark")
                        .opacity(0)
                }
            }
        }
    }
    
    // MARK: - Functions
    private func hasUnlockedTheme(_ theme: AppTheme) -> Bool {
        if theme.id == AppTheme.defaultID { return true }
        guard appSettings.hasUnlockedThemes else { return false }
        if theme.id == AppTheme.customID { return appSettings.hasUnlockedCustomThemes }
        if AppTheme.iphone17pro.map(\.id).contains(theme.id) { return DeviceModel.isIphone17ProSeries }
        return true
    }
    
    private func handleThemeClicked(_ theme: AppTheme) {
        if hasUnlockedTheme(theme) {
            selectionHapticTrigger += 1
            withAnimation(Animations.easeInOut) {
                previewingThemeID = theme.id
                if appSettings.hasUnlockedThemes {
                    appSettings.selectedThemeID = theme.id
                }
            }
        } else {
            selectedThemeBeforeUnlock = theme.id
            if theme.id == AppTheme.customID {
                isShowingLockedCustomAlert = true
            } else {
                isShowingLockedAlert = true
            }
        }
    }
    
    private func submitThemeUnlockKey() {
        if appSettings.unlockThemes(with: unlockThemesGuess) {
            applyUnlockedThemeSelection()
        } else {
            unlockThemesGuess = ""
            isShowingIncorrectUnlockAlert = true
        }
    }
    
    private func submitCustomThemeUnlockKey() {
        if appSettings.unlockCustomThemes(with: unlockThemesCustomGuess) {
            applyUnlockedThemeSelection()
        } else {
            unlockThemesCustomGuess = ""
            isShowingIncorrectCustomUnlockAlert = true
        }
    }
    
    private func applyUnlockedThemeSelection() {
        withAnimation(Animations.easeInOut) {
            if let selectedThemeBeforeUnlock {
                previewingThemeID = selectedThemeBeforeUnlock
            }
            appSettings.selectedThemeID = previewingThemeID
        }
        resetUnlockState()
    }
    
    private func resetUnlockState() {
        unlockThemesGuess = ""
        unlockThemesCustomGuess = ""
        selectedThemeBeforeUnlock = nil
    }
}

private struct AppThemePreview: View {
    let theme: AppTheme
    @Bindable var appSettings: AppSettings
    
    private var isCustom: Bool {
        theme.id == AppTheme.customID
    }
    
    private var activeTheme: AppTheme {
        isCustom ? appSettings.theme(for: AppTheme.customID) : theme
    }
    
    // MARK: - Restricted Color Bindings
    private var restrictedAccentColor: Binding<Color> {
        Binding {
            var color = Color(hex: appSettings.customTheme.accentHex)
            // Ensure accent color is neither too light nor too dark for readability
            if color.isTooLight() {
                color = color.darken()
            } else if color.isTooDark() {
                color = color.lighten()
            }
            return color
        } set: { newColor in
            // Enforce color constraints for readability
            var adjustedColor = newColor
            if newColor.isTooLight() {
                adjustedColor = newColor.darken()
            } else if newColor.isTooDark() {
                adjustedColor = newColor.lighten()
            }
            appSettings.updateCustomThemeColor(adjustedColor, for: \.accentHex)
        }
    }
    
    private var restrictedBackgroundColor: Binding<Color> {
        Binding {
            // Always display with 0.3 opacity
            return Color(hex: appSettings.customTheme.backgroundHex).opacity(0.3)
        } set: { newColor in
            // Preserve the hue/saturation/brightness but force opacity to 0.3
            let forcedOpacityColor = newColor.opacity(0.3)
            appSettings.updateCustomThemeColor(forcedOpacityColor, for: \.backgroundHex)
        }
    }
    
    private var restrictedBurstColor: Binding<Color> {
        Binding {
            // Always display with 0.65 opacity
            return Color(hex: appSettings.customTheme.shutterBurstHex).opacity(0.65)
        } set: { newColor in
            // Preserve the hue/saturation/brightness but force opacity to 0.65
            let forcedOpacityColor = newColor.opacity(0.65)
            appSettings.updateCustomThemeColor(forcedOpacityColor, for: \.shutterBurstHex)
        }
    }
    
    private var restrictedRawColor: Binding<Color> {
        Binding {
            // Always display with 0.5 opacity
            return Color(hex: appSettings.customTheme.shutterRawHex).opacity(0.5)
        } set: { newColor in
            // Preserve the hue/saturation/brightness but force opacity to 0.5
            let forcedOpacityColor = newColor.opacity(0.5)
            appSettings.updateCustomThemeColor(forcedOpacityColor, for: \.shutterRawHex)
        }
    }
    
    private var restrictedProRawColor: Binding<Color> {
        Binding {
            // Always display with 0.5 opacity
            return Color(hex: appSettings.customTheme.shutterProRawHex).opacity(0.5)
        } set: { newColor in
            // Preserve the hue/saturation/brightness but force opacity to 0.5
            let forcedOpacityColor = newColor.opacity(0.5)
            appSettings.updateCustomThemeColor(forcedOpacityColor, for: \.shutterProRawHex)
        }
    }
    
    // MARK: View
    var body: some View {
        VStack(spacing: 24) {
            if theme.id != AppTheme.defaultID {
                readoutsColor()
            }
            previewButtons()
            Text("Shutter Types")
                .font(.caption)
                .fontWidth(.expanded)
                .fontWeight(.light)
            shutterPreview()
        }
        .padding()
        .allowsHitTesting(isCustom)
    }
    
    // MARK: Subviews
    private func readoutsColor() -> some View {
        Text("Readouts font color if enabled")
            .foregroundStyle(activeTheme.readoutColor)
            .font(.system(size: 14, weight: .regular, design: .monospaced))
    }
    
    private func previewButtons() -> some View {
        VStack(spacing: 24) {
            HStack(spacing: 12) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 12, weight: .bold))
                    .frame(height: 18)
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(.white.opacity(0.15))
                    .clipShape(.capsule)
                
                Image(systemName: "camera.macro")
                    .font(.system(size: 12, weight: .bold))
                    .frame(height: 18)
                    .foregroundStyle(.black)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(activeTheme.accent)
                    .clipShape(.capsule)
                
                HStack(spacing: 0) {
                    Text("HEIF")
                        .font(.system(size: 12, weight: .medium))
                        .fontWidth(.expanded)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(activeTheme.accent)
                        .foregroundStyle(.black)
                    
                    Text("RAW")
                        .font(.system(size: 12, weight: .medium))
                        .fontWidth(.expanded)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(.white.opacity(0.15))
                        .foregroundStyle(.white)
                }
                .clipShape(.rect(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.white.opacity(0.2), lineWidth: 1))
            }
            
            HStack(spacing: 12) {
                VStack(spacing: 10) {
                    Button("Accent Color") { }
                        .font(.callout)
                        .fontWidth(.expanded)
                        .bold()
                        .tint(activeTheme.accent)
                        .buttonStyle(.glassProminent)
                    
                    if isCustom {
                        ColorPicker("", selection: restrictedAccentColor, supportsOpacity: false)
                            .labelsHidden()
                    }
                }
                
                VStack(spacing: 10) {
                    Button("Background") { }
                        .font(.callout)
                        .fontWidth(.expanded)
                        .bold()
                        .foregroundStyle(activeTheme.accent)
                        .buttonStyle(.glass)
                    
                    if isCustom {
                        ColorPicker("", selection: restrictedBackgroundColor, supportsOpacity: false)
                            .labelsHidden()
                    }
                }
            }
        }
    }
    
    private func lensPreview() -> some View {
        VStack(spacing: 12) {
            GlassEffectContainer(spacing: 8) {
                Button { } label: {
                    Text("1")
                        .font(.system(.callout, design: .monospaced))
                        .bold()
                        .foregroundStyle(.black)
                        .frame(width: 54, height: 54)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive().tint(activeTheme.accent.opacity(0.86)), in: .circle)
            }
            Text("Lens Picker")
                .font(.caption)
                .fontWidth(.expanded)
        }
    }
    
    private func shutterPreview() -> some View {
        GlassEffectContainer {
            VStack(spacing: 24) {
                HStack(spacing: 28) {
                    ThemeShutterPreviewButton(isCustom: isCustom, tint: isCustom ? restrictedRawColor : .constant(activeTheme.shutterRaw), desc: "RAW")
                    ThemeShutterPreviewButton(isCustom: isCustom, tint: isCustom ? restrictedProRawColor : .constant(activeTheme.shutterProRaw), desc: "ProRAW")
                    ThemeShutterPreviewButton(isCustom: isCustom, tint: isCustom ? restrictedBurstColor : .constant(activeTheme.shutterBurst), desc: "Burst")
                }
                HStack(alignment: .bottom, spacing: 28) {
                    ThemeShutterPreviewButton(isCustom: false, tint: activeTheme.shutterProcessed, desc: "Standard")
                    lensPreview()
                }
            }
        }
    }
}

private struct ThemeShutterPreviewButton: View {
    let isCustom: Bool
    @Binding var tint: Color
    let desc: String
    
    private let height: CGFloat = 82
    
    init(isCustom: Bool, tint: Color, desc: String) {
        self.isCustom = isCustom
        self._tint = .constant(tint)
        self.desc = desc
    }
    
    init(isCustom: Bool, tint: Binding<Color>, desc: String) {
        self.isCustom = isCustom
        self._tint = tint
        self.desc = desc
    }
    
    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .frame(width: height, height: height)
                    .glassEffect(.regular.tint(tint))
                Circle()
                    .fill(.white)
                    .frame(width: height*0.84, height: height*0.84)
                    .glassEffect(.regular.interactive())
            }
            .frame(width: height, height: height)
            
            HStack {
                Text(desc)
                    .font(.caption)
                    .fontWidth(.expanded)
                if isCustom {
                    ColorPicker("", selection: $tint, supportsOpacity: false)
                        .font(.caption)
                        .fontWidth(.expanded)
                        .labelsHidden()
                }
            }
        }
    }
}

#Preview {
    @Previewable @State var appSettings = AppSettings()
    NavigationStack {
        AppThemeSelectionView(appSettings: appSettings)
    }
}
