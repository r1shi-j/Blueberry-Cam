import SwiftUI

struct AppThemeSelectionView: View {
    @Binding var selectedThemeID: String
    @State private var selectionHapticTrigger = 0
    
    private var selectedTheme: AppTheme {
        AppTheme.theme(for: selectedThemeID)
    }
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
                .overlay(selectedTheme.background)
            
            VStack(spacing: 0) {
                Form {
                    ForEach(AppTheme.all) { theme in
                        Button {
                            selectTheme(theme)
                        } label: {
                            HStack {
                                Text(theme.name)
                                    .foregroundStyle(.primary)
                                
                                Spacer()
                                
                                if selectedThemeID == theme.id {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(selectedTheme.accent)
                                        .contentTransition(.symbolEffect(.replace))
                                        .symbolEffect(.bounce, value: selectedThemeID)
                                }
                            }
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .scrollContentBackground(.hidden)
                
                Divider()
                
                AppThemePreview(theme: selectedTheme)
            }
        }
        .environment(\.colorScheme, .dark)
        .navigationTitle("App Theme")
        .toolbarColorScheme(.dark, for: .navigationBar)
        .tint(.white)
        .sensoryFeedback(.selection, trigger: selectionHapticTrigger)
    }
    
    private func selectTheme(_ theme: AppTheme) {
        guard selectedThemeID != theme.id else { return }
        selectionHapticTrigger += 1
        withAnimation(Animations.easeInOut) {
            selectedThemeID = theme.id
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
            lensPreview()
            shutterPreview()
        }
        .padding(.vertical, 24)
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity)
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
        .allowsHitTesting(false)
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
            .glassEffect(
                .regular
                    .interactive()
                    .tint(theme.accent.opacity(0.86)),
                in: .circle
            )
        }
        .allowsHitTesting(false)
    }
    
    private func shutterPreview() -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 28) {
                ThemeShutterPreviewButton(tint: theme.shutterProcessed, desc: "Standard")
                ThemeShutterPreviewButton(tint: theme.shutterRaw, desc: "RAW")
                ThemeShutterPreviewButton(tint: theme.shutterProRaw, desc: "ProRAW")
            }
            HStack(spacing: 28) {
                ThemeShutterPreviewButton(tint: theme.shutterBurst, desc: "Burst")
                ThemeShutterPreviewButton(tint: theme.shutterBurstCapturing, desc: "Burst Capturing")
            }
        }
        .allowsHitTesting(false)
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
    @Previewable @State var selectedThemeID = AppTheme.defaultID
    NavigationStack {
        AppThemeSelectionView(selectedThemeID: $selectedThemeID)
    }
}
