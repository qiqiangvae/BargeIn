import SwiftUI

/// 把 Fracture 画成一整块碎掉的玻璃：碎片是不透明的深色玻璃（所以遮罩本身就是它），
/// 裂纹是碎片的边。进入阶段裂口从炸点慢慢爬开，确认后整片坠落、露出桌面。
struct FractureCanvas: View {
    let animator: ShatterAnimator

    var body: some View {
        if animator.reduceMotion {
            Canvas { context, size in
                draw(context: context, size: size, entrance: Fracture.holdAt, exit: 0, flash: 0)
            }
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !animator.isAnimating)) { timeline in
                let entrance = timeline.date.timeIntervalSince(animator.startedAt)
                let exit = animator.exitStartedAt.map { timeline.date.timeIntervalSince($0) } ?? 0
                Canvas { context, size in
                    draw(context: context, size: size, entrance: entrance, exit: exit, flash: flash(at: entrance))
                }
            }
        }
    }

    // MARK: - 绘制

    private func draw(context: GraphicsContext, size: CGSize, entrance: TimeInterval, exit: TimeInterval, flash: Double) {
        let reference = Fracture.reference
        let scale = max(size.width / reference.width, size.height / reference.height)
        var base = context
        base.translateBy(
            x: (size.width - reference.width * scale) / 2,
            y: (size.height - reference.height * scale) / 2
        )
        base.scaleBy(x: scale, y: scale)

        let crackTime = min(entrance, Fracture.holdAt)
        for piece in animator.fracture.pieces {
            let progress = pow(clamp((crackTime - piece.appearAt) / piece.drawDuration), 2)
            let fall = fallState(piece, entrance: entrance, exit: exit)
            var ctx = base
            if fall.dx != 0 || fall.dy != 0 || fall.rotation != 0 {
                ctx.translateBy(x: piece.centroid.x + fall.dx, y: piece.centroid.y + fall.dy)
                ctx.rotate(by: .degrees(fall.rotation))
                ctx.translateBy(x: -piece.centroid.x, y: -piece.centroid.y)
            }

            // 玻璃先铺满（遮罩就是这些碎片），裂纹再从左端慢慢爬开。
            // 脱落中的那块给一点反光，否则深色碎片在深色屏面上看不出在掉。
            let lit = fall.shed && fall.progress < 0.99
            ctx.fill(piece.path, with: .color(paneColor(piece, lit: lit)))
            if progress > 0.001 {
                let line = progress >= 0.999 ? piece.path : piece.path.trimmedPath(from: 0, to: progress)
                ctx.stroke(
                    line,
                    with: .color(edgeColor(piece, fade: fall.progress)),
                    lineWidth: piece.lineWidth
                )
            }
        }

        if flash > 0 {
            let radius: CGFloat = 150
            let impact = animator.fracture.impact
            let rect = CGRect(x: impact.x - radius, y: impact.y - radius, width: radius * 2, height: radius * 2)
            let flashContext = base
            flashContext.fill(
                Path(ellipseIn: rect),
                with: .radialGradient(
                    Gradient(colors: [
                        Color.white.opacity(0.85 * flash),
                        Color.cyan.opacity(0.35 * flash),
                        Color.clear,
                    ]),
                    center: impact,
                    startRadius: 0,
                    endRadius: radius
                )
            )
        }
    }

    private struct FallState {
        var dx: CGFloat = 0
        var dy: CGFloat = 0
        var rotation: Double = 0
        var progress: Double = 0
        /// 是等待期自己脱落的那种掉落（不是退场整片坠落），要提亮。
        var shed = false
    }

    private func fallState(_ piece: FracturePiece, entrance: TimeInterval, exit: TimeInterval) -> FallState {
        // 先掉的那块不会因为退场再掉一次：掉完就停在屏外，不再回到原位。
        // 退场前还没开始掉的那几块不再单独脱落，跟着整片玻璃一起坠落。
        if let shedAt = piece.shedAt, entrance > shedAt, exit == 0 || entrance - exit > shedAt {
            return falling(piece, q: (entrance - shedAt) / piece.shedDuration, shed: true)
        }
        if let earlyAt = piece.earlyAt, entrance > earlyAt {
            return falling(piece, q: (entrance - earlyAt) / piece.earlyDuration)
        }
        if exit > piece.exitAt {
            return falling(piece, q: (exit - piece.exitAt) / piece.exitDuration)
        }
        return FallState()
    }

    private func falling(_ piece: FracturePiece, q: Double, shed: Bool = false) -> FallState {
        let q = clamp(q)
        let g = q * q
        return FallState(
            dx: piece.exitDrift * g,
            dy: piece.exitDistance * g,
            rotation: piece.exitRotation * g,
            progress: q,
            shed: shed
        )
    }

    private func flash(at entrance: TimeInterval) -> Double {
        let peak = Fracture.impactAt + 0.06
        let distance = abs(entrance - peak)
        return clamp(1 - distance / 0.14)
    }

    private func paneColor(_ piece: FracturePiece, lit: Bool = false) -> Color {
        if piece.isHole {
            return Color(red: 0.004, green: 0.014, blue: 0.022)
        }
        if lit {
            return Color(red: 0.09, green: 0.17, blue: 0.24)
        }
        let tones: [Color] = [
            Color(red: 0.031, green: 0.078, blue: 0.126),
            Color(red: 0.016, green: 0.043, blue: 0.070),
            Color(red: 0.024, green: 0.063, blue: 0.102),
            Color(red: 0.012, green: 0.031, blue: 0.055),
            Color(red: 0.035, green: 0.086, blue: 0.133),
        ]
        return tones[min(max(piece.tone, 0), tones.count - 1)]
    }

    private func edgeColor(_ piece: FracturePiece, fade: Double) -> Color {
        let opacity = 1 - 0.35 * fade
        switch piece.edge {
        case .white:
            return Color(red: 0.87, green: 0.94, blue: 1).opacity(0.44 * opacity)
        case .bright:
            return Color(red: 0.96, green: 0.99, blue: 1).opacity(0.66 * opacity)
        case .cyan:
            return Color(red: 0.13, green: 0.83, blue: 0.93).opacity(0.38 * opacity)
        }
    }

    private func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}
