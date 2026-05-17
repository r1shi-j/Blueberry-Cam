import SwiftUI

extension AppThemeSelectionView {
    struct AppThemePreview: View {
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
                return Color(hex: appSettings.customTheme.backgroundHex)
            } set: { newColor in
                // Preserve the hue/saturation/brightness but force opacity to 0.3
                let forcedOpacityColor = newColor.opacity(0.3)
                appSettings.updateCustomThemeColor(forcedOpacityColor, for: \.backgroundHex)
            }
        }
        
        private var restrictedBurstColor: Binding<Color> {
            Binding {
                // Always display with 0.65 opacity
                return Color(hex: appSettings.customTheme.shutterBurstHex)
            } set: { newColor in
                // Preserve the hue/saturation/brightness but force opacity to 0.65
                let forcedOpacityColor = newColor.opacity(0.65)
                appSettings.updateCustomThemeColor(forcedOpacityColor, for: \.shutterBurstHex)
            }
        }
        
        private var restrictedRawColor: Binding<Color> {
            Binding {
                // Always display with 0.5 opacity
                return Color(hex: appSettings.customTheme.shutterRawHex)
            } set: { newColor in
                // Preserve the hue/saturation/brightness but force opacity to 0.5
                let forcedOpacityColor = newColor.opacity(0.5)
                appSettings.updateCustomThemeColor(forcedOpacityColor, for: \.shutterRawHex)
            }
        }
        
        private var restrictedProRawColor: Binding<Color> {
            Binding {
                // Always display with 0.5 opacity
                return Color(hex: appSettings.customTheme.shutterProRawHex)
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
