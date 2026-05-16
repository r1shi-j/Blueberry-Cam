import SwiftUI

struct AppThemeSelectionView: View {
    @Binding var hasUnlockedThemes: Bool
    @Binding var selectedThemeID: String
    @State private var previewingThemeID: String
    @State private var isShowingLockedAlert = false
    @State private var isShowingUnlockedAlert = false
    @State private var unlockThemesGuess = ""
    private let unlockThemesKey = "BlueberryCam_08052026"
    
    @State private var selectionHapticTrigger = 0
    
    init(hasUnlockedThemes: Binding<Bool>, selectedThemeID: Binding<String>) {
        self._hasUnlockedThemes = hasUnlockedThemes
        self._selectedThemeID = selectedThemeID
        self._previewingThemeID = State(initialValue: selectedThemeID.wrappedValue)
    }
    
    private var themesToShow: [AppTheme] {
        var themes: [AppTheme] = [.classic]
        themes += AppTheme.standard
        if DeviceModel.isIphone17ProSeries {
            themes += AppTheme.iphone17pro
        }
        themes += [AppTheme.custom]
        return themes
    }
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
                .overlay(AppTheme.theme(for: previewingThemeID).background)
            
            ScrollView {
                VStack(spacing: 0) {
                    themeList()
                    Divider().padding(.vertical)
                    Text("Theme Preview")
                        .font(.caption)
                        .fontWidth(.expanded)
                        .fontWeight(.bold)
                    AppThemePreview(theme: AppTheme.theme(for: previewingThemeID))
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
            ToolbarItem(placement: .topBarTrailing) {
                Button("Debug", systemImage: "hammer.fill") {
                    selectedThemeID = AppTheme.defaultID
                    previewingThemeID = AppTheme.defaultID
                    hasUnlockedThemes.toggle()
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                if !hasUnlockedThemes {
                    Button("Locked", systemImage: "lock.fill") {
                        isShowingLockedAlert = true
                    }
                } else {
                    Button("Unlocked", systemImage: "lock.open.fill") {
                        isShowingUnlockedAlert = true
                    }
                }
            }
        }
        .onChange(of: unlockThemesGuess) { oldValue, newValue in
            if newValue == unlockThemesKey {
                selectedThemeID = previewingThemeID
                hasUnlockedThemes = true
            }
        }
        .alert("Requirements not met to unlock app themes.", isPresented: $isShowingLockedAlert) {
            SecureField("Unlock Themes Key", text: $unlockThemesGuess)
        } message: {
            Text("To unlock app themes, your standard shutter count must be at least 100, and burst count at least 500.\nYou can check your statistics at the bottom of settings, or below the photos link shortcut to the left of the shutter button.\nAlternatively, if you have an unlock key enter it below.")
        }
        .alert("All themes are unlocked!", isPresented: $isShowingUnlockedAlert) { }
    }
    
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
            if hasUnlockedThemes {
                selectTheme(theme)
            } else {
                if theme.id != AppTheme.defaultID {
                    isShowingLockedAlert = true
                }
            }
        } label: {
            HStack {
                if !hasUnlockedThemes && theme.id != selectedThemeID {
                    Image(systemName: "lock.fill")
                }
                Text(theme.name)
                    .foregroundStyle(.primary)
                    .padding(.vertical, 4)
                
                Spacer()
                
                if !hasUnlockedThemes && theme.id != previewingThemeID && theme.id != AppTheme.customID {
                    Button("Preview") {
                        selectTheme(theme)
                    }
                    .font(.caption)
                    .fontWidth(.expanded)
                    .bold()
                    .tint(AppTheme.theme(for: theme.id).accent)
                    .buttonStyle(.glassProminent)
                }
                
                if selectedThemeID == theme.id || !hasUnlockedThemes {
                    Image(systemName: "checkmark")
                        .foregroundStyle(AppTheme.theme(for: theme.id).accent)
                        .contentTransition(.symbolEffect(.replace))
                        .symbolEffect(.bounce, value: selectedThemeID)
                        .opacity(!hasUnlockedThemes && theme.id != AppTheme.defaultID ? 0 : 1)
                        .padding(.leading)
                }
            }
            .contentShape(.rect)
        }
        .padding(.horizontal)
        .padding(.vertical, 14)
        .buttonStyle(.plain)
        .disabled(/*!hasUnlockedThemes && */theme.id == AppTheme.customID)
    }
    
    private func selectTheme(_ theme: AppTheme) {
        guard previewingThemeID != theme.id else { return }
        selectionHapticTrigger += 1
        withAnimation(Animations.easeInOut) {
            previewingThemeID = theme.id
            if hasUnlockedThemes {
                selectedThemeID = theme.id
            }
        }
    }
}

private struct AppThemePreview: View {
    let theme: AppTheme
    
    var body: some View {
        VStack(spacing: 24) {
            if theme.id != AppTheme.defaultID {
                readoutsColor()
            }
            previewButtons()
            shutterPreview()
            lensPreview()
        }
        .padding()
        .allowsHitTesting(false)
    }
    
    private func readoutsColor() -> some View {
        Text("Readouts font color if enabled")
            .foregroundStyle(theme.readoutColor)
            .font(.system(size: 14, weight: .regular, design: .monospaced))
    }
    
    private func previewButtons() -> some View {
        HStack(spacing: 12) {
            Button("Accent Color") { }
                .font(.callout)
                .fontWidth(.expanded)
                .bold()
                .tint(theme.accent)
                .buttonStyle(.glassProminent)
            
            Button("Accent Text") { }
                .font(.callout)
                .fontWidth(.expanded)
                .bold()
                .foregroundStyle(theme.accent)
                .buttonStyle(.glass)
        }
    }
    
    private func lensPreview() -> some View {
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
            .glassEffect(.regular.interactive().tint(theme.accent.opacity(0.86)), in: .circle)
        }
    }
    
    private func shutterPreview() -> some View {
        GlassEffectContainer {
            
            
            VStack(spacing: 8) {
                HStack(spacing: 28) {
                    ThemeShutterPreviewButton(tint: theme.shutterProcessed, desc: "Standard")
                    ThemeShutterPreviewButton(tint: theme.shutterRaw, desc: "RAW")
                    ThemeShutterPreviewButton(tint: theme.shutterProRaw, desc: "ProRAW")
                }
                HStack(spacing: 28) {
                    ThemeShutterPreviewButton(tint: theme.shutterBurst, desc: "Burst")
                }
            }
        }
    }
}

private struct ThemeShutterPreviewButton: View {
    let tint: Color
    let desc: String
    
    private let height: CGFloat = 82
    
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
            
            Text(desc)
                .font(.caption)
                .fontWidth(.expanded)
        }
    }
}

#Preview {
    @Previewable @State var hasUnlockedThemes = true
    @Previewable @State var selectedThemeID = "blueberry"
    NavigationStack {
        AppThemeSelectionView(hasUnlockedThemes: $hasUnlockedThemes, selectedThemeID: $selectedThemeID)
    }
}
