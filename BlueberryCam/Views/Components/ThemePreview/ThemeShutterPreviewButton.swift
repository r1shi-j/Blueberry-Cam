import SwiftUI

extension AppThemeSelectionView {
    struct ThemeShutterPreviewButton: View {
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
}
