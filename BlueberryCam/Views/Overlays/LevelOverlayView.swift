import SwiftUI

struct LevelOverlayView: View {
    @Bindable var model: LevelMotionModel
    let theme: AppTheme
    
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
                    Canvas { ctx, size in
                        drawLevelMode(ctx: ctx, cx: cx, cy: cy, w: size.width)
                    }
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
    private func drawLevelMode(ctx: GraphicsContext, cx: CGFloat, cy: CGFloat, w: CGFloat) {
        let barLen: CGFloat = w * 1/3   // bar length
        let barHalfLen: CGFloat = barLen * 1/2  // half bar length
        let tickLen: CGFloat = barLen * 1/3   // tick length
        let lw: CGFloat = lineWidth   // same line width as crosshair
        
        let aligned = model.isAligned
        let barColor: Color = aligned ? theme.accent : .white
        let tickColor: Color = Colors.buttonText
        
        // Ticks rotate to the NEAREST cardinal (0°, 90°, 180°, 270°),
        // tracking the bar's axis regardless of device orientation.
        let nearestCardinal = (model.tiltAngleDeg / 90.0).rounded() * 90.0
        
        ctx.drawLayer { layerCtx in
            layerCtx.translateBy(x: cx, y: cy)
            layerCtx.rotate(by: Angle.degrees(nearestCardinal))
            layerCtx.translateBy(x: -cx, y: -cy)
            
            var lTick = Path()
            lTick.move(to: CGPoint(x: cx - barHalfLen, y: cy))
            lTick.addLine(to: CGPoint(x: cx - barHalfLen - tickLen, y: cy))
            
            var rTick = Path()
            rTick.move(to: CGPoint(x: cx + barHalfLen, y: cy))
            rTick.addLine(to: CGPoint(x: cx + barHalfLen + tickLen, y: cy))
            
            let tickStyle = StrokeStyle(lineWidth: lw, lineCap: .round)
            layerCtx.stroke(lTick, with: .color(tickColor), style: tickStyle)
            layerCtx.stroke(rTick, with: .color(tickColor), style: tickStyle)
        }
        
        // Gravity-stabilised bar: rotate by NEGATIVE tiltAngleDeg so it
        // always stays truly horizontal in the real world.
        var barPath = Path()
        barPath.move(to: CGPoint(x: cx - barHalfLen, y: cy))
        barPath.addLine(to: CGPoint(x: cx + barHalfLen, y: cy))
        
        ctx.drawLayer { layerCtx in
            layerCtx.translateBy(x: cx, y: cy)
            layerCtx.rotate(by: Angle.degrees(-model.tiltAngleDeg))
            layerCtx.translateBy(x: -cx, y: -cy)
            layerCtx.stroke(barPath, with: .color(barColor.opacity(0.92)), style: StrokeStyle(lineWidth: lw, lineCap: .round))
        }
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
