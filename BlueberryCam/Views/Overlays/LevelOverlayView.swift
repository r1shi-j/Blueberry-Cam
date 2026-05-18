import SwiftUI

struct LevelOverlayView: View {
    @Bindable var model: LevelMotionModel
    let theme: AppTheme
    let aspectRatio: CGFloat
    
    private let lineWidth: CGFloat = 1.2
    
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let cx = w / 2
            let cy = h / 2
            
            switch model.displayMode {
                case .hidden:
                    EmptyView()
                case .level:
                    levelModeView(w: w, h: h)
                        .position(x: cx, y: cy)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                case .flat:
                    Canvas { ctx, size in
                        drawFlatMode(ctx: ctx, cx: cx, cy: cy, w: size.width)
                    }
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .animation(Animations.levelShown, value: model.displayMode)
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
    
    // MARK: - Level Mode
    //
    // Layout (at 0°):
    //   [── tick ──][── rotating bar ──][── tick ──]
    //    --tickLen--|------barLen------|--tickLen--
    //
    @ViewBuilder
    private func levelModeView(w: CGFloat, h: CGFloat) -> some View {
        let nearestCardinal = (model.tiltAngleDeg / 90.0).rounded() * 90.0
        let isLandscape = abs(Int(nearestCardinal)) % 180 == 90
        
        let screenAspect = w / h
        let cropW: CGFloat = aspectRatio < screenAspect ? h * aspectRatio : w
        let cropH: CGFloat = aspectRatio < screenAspect ? h : w / aspectRatio
        
        let referenceLength = isLandscape ? cropH : cropW
        
        let barLen: CGFloat = referenceLength * 1/3   // bar length
        let tickLen: CGFloat = barLen * 1/3   // tick length
        
        let aligned = model.isAligned
        let barColor: Color = aligned ? theme.accent : .white
        let tickColor: Color = Colors.buttonText
        
        ZStack {
            // Ticks
            HStack(spacing: barLen) {
                Capsule()
                    .fill(tickColor)
                    .frame(width: tickLen, height: lineWidth)
                Capsule()
                    .fill(tickColor)
                    .frame(width: tickLen, height: lineWidth)
            }
            .rotationEffect(.degrees(-nearestCardinal))
            
            // Gravity-stabilised rotating bar
            Capsule()
                .fill(barColor.opacity(0.92))
                .frame(width: barLen, height: lineWidth)
                .rotationEffect(.degrees(-model.tiltAngleDeg))
                .animation(.easeInOut(duration: 0.15), value: aligned)
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.75), value: nearestCardinal)
    }
    
    // MARK: - Flat Mode
    // Fixed white crosshair at screen centre.
    // Floating yellow crosshair offset by gravity projection (inverted so it
    // moves in the intuitive direction — crosshair moves toward where "up" is).
    private func drawFlatMode(ctx: GraphicsContext, cx: CGFloat, cy: CGFloat, w: CGFloat) {
        let armLen: CGFloat = w * 0.07 / 2
        let lw: CGFloat = lineWidth
        
        // Fixed reference crosshair (white)
        drawCrosshair(ctx: ctx, x: cx, y: cy, color: .white.opacity(0.85), armLen: armLen, lineWidth: lw)
        
        // Floating crosshair — uses pre-rotated screen-space gravity
        // so direction is correct in both portrait and landscape.
        let maxOffset: CGFloat = 55
        let scale: CGFloat = maxOffset * 2.5
        let dx = max(-maxOffset, min(maxOffset, CGFloat(model.screenGravityX) * scale))
        let dy = max(-maxOffset, min(maxOffset, CGFloat(model.screenGravityY) * scale))
        
        drawCrosshair(ctx: ctx, x: cx + dx, y: cy + dy, color: theme.accent.opacity(model.isCrosshairAligned ? 1.0 : 0.9), armLen: armLen, lineWidth: lw)
    }
    
    // MARK: - Shared helper
    // No gap — arms go straight through the centre point.
    private func drawCrosshair(ctx: GraphicsContext, x: CGFloat, y: CGFloat, color: Color, armLen: CGFloat, lineWidth: CGFloat) {
        var h = Path()
        h.move(to: CGPoint(x: x - armLen, y: y))
        h.addLine(to: CGPoint(x: x + armLen, y: y))
        
        var v = Path()
        v.move(to: CGPoint(x: x, y: y - armLen))
        v.addLine(to: CGPoint(x: x, y: y + armLen))
        
        let style = StrokeStyle(lineWidth: lineWidth, lineCap: .round)
        ctx.stroke(h, with: .color(color), style: style)
        ctx.stroke(v, with: .color(color), style: style)
    }
}
