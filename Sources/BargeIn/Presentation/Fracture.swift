import SwiftUI
import BargeInCore

/// 一块玻璃碎片的静态几何与它的时间线。
/// 所有坐标都在 1600×1000 的参考空间里，绘制时按屏幕等比缩放。
struct FracturePiece: Identifiable {
    enum Edge {
        case white
        case bright
        case cyan
    }

    let id: Int
    let points: [CGPoint]
    let path: Path
    let centroid: CGPoint
    let tone: Int
    let lineWidth: CGFloat
    let edge: Edge
    let isHole: Bool

    /// 进入阶段：裂纹画到这个时刻开始出现、画多久。
    let appearAt: TimeInterval
    let drawDuration: TimeInterval
    /// 进入阶段就掉的碎片（冲击孔 + 一两块小碎片）。
    let earlyAt: TimeInterval?
    let earlyDuration: TimeInterval
    /// 确认之后整片坠落。
    let exitAt: TimeInterval
    let exitDuration: TimeInterval
    let exitDistance: CGFloat
    let exitDrift: CGFloat
    let exitRotation: Double

    /// 裂满之后、等你处理的这段时间里自己慢慢脱落（进入时间轴；nil = 不脱落）。
    /// 用和退场同一套轨迹（漂移 + 自旋 + 从原位移开），只是拉得很慢。
    var shedAt: TimeInterval?
    var shedDuration: TimeInterval = 0
}

/// 一次碎裂的全部几何：炸点、碎片与它们的时序。
struct Fracture {
    static let reference = CGSize(width: 1600, height: 1000)

    let pieces: [FracturePiece]
    let impact: CGPoint
    let exitDuration: TimeInterval
    /// 等待期最后一块小碎片落完的入场时刻；没有等待期脱落就是 0。
    let shedEnd: TimeInterval

    static let impactAt: TimeInterval = 0.36
    static let revealAt: TimeInterval = 2.25
    static let holdAt: TimeInterval = 2.45

    /// 固定种子：预览与到点完全一致；每次不同则换一套。
    static func generate(pattern: CrackPattern) -> Fracture {
        let seed: UInt64 = pattern == .fixed ? 20261113 : UInt64.random(in: 1...UInt64.max)
        return generate(seed: seed)
    }

    static func generate(seed: UInt64) -> Fracture {
        var rng = Mulberry32(seed: UInt32(truncatingIfNeeded: seed))
        let width = reference.width
        let height = reference.height

        let cx = width * (0.40 + rng.double() * 0.22)
        let cy = height * (0.28 + rng.double() * 0.26)
        let corners = [CGPoint(x: 0, y: 0), CGPoint(x: width, y: 0),
                       CGPoint(x: width, y: height), CGPoint(x: 0, y: height)]
        let maxRadius = corners.map { hypot($0.x - cx, $0.y - cy) }.max() ?? 1
        let holeRadius = 9 + rng.double() * 15

        // 主裂：从炸点放射出去，角度不等距、折线不直
        let rayCount = 4 + Int(rng.double() * 4)
        let baseAngle = rng.double() * .pi * 2
        let step = Double.pi * 2 / Double(rayCount)
        var rays: [(angle: Double, inner: CGPoint, border: CGPoint, points: [CGPoint])] = []
        for i in 0..<rayCount {
            let angle = baseAngle + Double(i) * step + (rng.double() - 0.5) * step * 0.6
            let inner = CGPoint(x: cx + cos(angle) * holeRadius, y: cy + sin(angle) * holeRadius)
            let border = rectIntersection(from: CGPoint(x: cx, y: cy), angle: angle)
            let length = hypot(border.x - inner.x, border.y - inner.y)
            let steps = 3 + Int(rng.double() * 2)
            var points: [CGPoint] = [inner]
            for k in 1..<steps {
                let t = Double(k) / Double(steps)
                let bx = inner.x + (border.x - inner.x) * t
                let by = inner.y + (border.y - inner.y) * t
                let nx = -(border.y - inner.y)
                let ny = border.x - inner.x
                let nl = hypot(nx, ny)
                let amp = min(32, length * 0.055) * (rng.double() * 2 - 1)
                points.append(CGPoint(x: bx + nx / nl * amp, y: by + ny / nl * amp))
            }
            points.append(border)
            rays.append((angle, inner, border, points))
        }

        // 冲击孔：碎块围成的小洞，随后自己掉出去
        let hole = rays.map { ray -> CGPoint in
            let r = holeRadius * (1 + (rng.double() - 0.5) * 0.5)
            return CGPoint(x: cx + cos(ray.angle) * r, y: cy + sin(ray.angle) * r)
        }

        // 楔形碎块：主裂 + 屏幕边缘围出来的扇形
        var wedges: [[CGPoint]] = []
        for i in 0..<rays.count {
            let r1 = rays[i]
            let r2 = rays[(i + 1) % rays.count]
            let s1 = rectParameter(r1.border)
            var s2 = rectParameter(r2.border)
            if s2 <= s1 { s2 += 4 }
            var arc: [CGPoint] = []
            var corner = floor(s1) + 1
            while corner < s2 {
                arc.append(rectPoint(parameter: corner))
                corner += 1
            }
            var poly: [CGPoint] = [r1.inner]
            poly.append(contentsOf: r1.points.dropFirst())
            poly.append(contentsOf: arc)
            poly.append(contentsOf: r2.points.reversed())
            wedges.append(poly)
        }

        var pieces: [[CGPoint]] = []
        var depths: [Int] = []
        var centroids: [CGPoint] = []

        func pushPiece(_ poly: [CGPoint], depth: Int) {
            pieces.append(poly)
            depths.append(depth)
            centroids.append(centroid(of: poly))
        }

        // 从最大的一块开始劈：越靠近炸点越碎，远处是大块
        struct QueueItem { var poly: [CGPoint]; var depth: Int }
        var pool = wedges.map { QueueItem(poly: $0, depth: 0) }
        let maxPieces = 170
        while !pool.isEmpty {
            pool.sort { abs(area(of: $0.poly)) > abs(area(of: $1.poly)) }
            let item = pool.removeFirst()
            let pieceArea = abs(area(of: item.poly))
            let c = centroid(of: item.poly)
            let distance = hypot(c.x - cx, c.y - cy) / maxRadius
            let minArea = width * height * (0.0009 + 0.015 * pow(distance, 1.6))
            if item.depth >= 7 || pieceArea < minArea || pieces.count + pool.count >= maxPieces {
                pushPiece(item.poly, depth: item.depth)
                continue
            }
            guard let kids = split(item.poly, rng: &rng) else {
                pushPiece(item.poly, depth: item.depth)
                continue
            }
            pool.append(QueueItem(poly: kids.0, depth: item.depth + 1))
            pool.append(QueueItem(poly: kids.1, depth: item.depth + 1))
        }

        var result: [FracturePiece] = []
        for (index, poly) in pieces.enumerated() {
            let c = centroids[index]
            let distance = hypot(c.x - cx, c.y - cy) / maxRadius
            var nearest = Double.infinity
            for p in poly {
                nearest = min(nearest, hypot(p.x - cx, p.y - cy) / maxRadius)
            }
            let perim = perimeter(of: poly)
            let edgeRoll = rng.double()
            let edge: FracturePiece.Edge = edgeRoll > 0.9 ? .cyan : edgeRoll > 0.2 ? .white : .bright
            result.append(
                FracturePiece(
                    id: index,
                    points: poly,
                    path: makePath(poly),
                    centroid: c,
                    tone: Int(rng.double() * 5),
                    lineWidth: (rng.double() > 0.86 ? 1.9 : 1.1) + CGFloat(rng.double()) * 0.5,
                    edge: edge,
                    isHole: false,
                    appearAt: Fracture.impactAt + 1.25 * sqrt(nearest) + Double(depths[index]) * 0.05 + rng.double() * 0.09,
                    drawDuration: 0.42 + min(0.26, perim * 0.00006),
                    earlyAt: nil,
                    earlyDuration: 0,
                    exitAt: 0.06 + distance * 0.70 + rng.double() * 0.13,
                    exitDuration: 0.85 + rng.double() * 0.42,
                    exitDistance: 1300 + CGFloat(rng.double()) * 600,
                    exitDrift: CGFloat((rng.double() - 0.5) * 130),
                    exitRotation: (rng.double() - 0.5) * 18
                )
            )
        }

        // 冲击孔自己也是一块，先掉
        let holePath = makePath(hole)
        result.append(
            FracturePiece(
                id: result.count,
                points: hole,
                path: holePath,
                centroid: centroid(of: hole),
                tone: -1,
                lineWidth: 1.8,
                edge: .bright,
                isHole: true,
                appearAt: Fracture.impactAt - 0.01,
                drawDuration: 0.2,
                earlyAt: 0.86,
                earlyDuration: 0.52,
                exitAt: 0,
                exitDuration: 0.42,
                exitDistance: 1500,
                exitDrift: 30,
                exitRotation: 34
            )
        )

        // 进入阶段就掉的一两块小碎片：挑炸点附近、已经被劈得很碎的那几块
        let earlyCandidates = result
            .filter { !$0.isHole }
            .enumerated()
            .filter { index, piece in
                !piece.isHole && index < depths.count && depths[index] >= 2
                    && hypot(centroids[index].x - cx, centroids[index].y - cy) / maxRadius < 0.5
            }
            .sorted { abs(area(of: pieces[$0.offset])) < abs(area(of: pieces[$1.offset])) }

        for (order, entry) in earlyCandidates.prefix(2).enumerated() {
            let index = entry.offset
            let piece = result[index]
            result[index] = FracturePiece(
                id: piece.id,
                points: piece.points,
                path: piece.path,
                centroid: piece.centroid,
                tone: piece.tone,
                lineWidth: piece.lineWidth,
                edge: piece.edge,
                isHole: false,
                appearAt: piece.appearAt,
                drawDuration: piece.drawDuration,
                earlyAt: 1.35 + Double(order) * 0.2 + rng.double() * 0.05,
                earlyDuration: 0.7 + rng.double() * 0.14,
                exitAt: piece.exitAt,
                exitDuration: piece.exitDuration,
                exitDistance: 1500,
                exitDrift: CGFloat((rng.double() - 0.5) * 60),
                exitRotation: (rng.double() - 0.5) * 24
            )
        }

        // 等待确认时不干等：裂满之后约每半秒慢慢掉下一小块，屏面不会彻底静止。
        // 挑屏面上最方正的小块——细长条掉出去会留下一条长口子，不像"一块碎片掉了"。
        // 单独一条随机序列，不动已有花纹。
        var shedRng = Mulberry32(seed: UInt32(truncatingIfNeeded: seed) ^ 0x5EED_F00D)
        let panelHalf = CGSize(width: 300, height: 140)
        let shedCandidates = result.indices.filter { index in
            let piece = result[index]
            guard !piece.isHole, piece.earlyAt == nil else { return false }
            let c = piece.centroid
            let distance = hypot(c.x - cx, c.y - cy) / maxRadius
            let underPanel = abs(c.x - width / 2) < panelHalf.width && abs(c.y - height / 2) < panelHalf.height
            return distance < 0.6 && !underPanel && abs(area(of: piece.points)) < 8000
        }.sorted { extent(of: result[$0].points) < extent(of: result[$1].points) }

        for (order, index) in shedCandidates.prefix(10).enumerated() {
            result[index].shedAt = Fracture.holdAt + 0.6 + Double(order) * 0.45 + shedRng.double() * 0.12
            result[index].shedDuration = 2.4 + shedRng.double() * 0.6
        }

        let exitEnd = result.map { $0.exitAt + $0.exitDuration }.max() ?? 2.2
        let shedEnd = result.compactMap { piece in piece.shedAt.map { $0 + piece.shedDuration } }.max() ?? 0
        return Fracture(
            pieces: result,
            impact: CGPoint(x: cx, y: cy),
            exitDuration: exitEnd + 0.15,
            shedEnd: shedEnd
        )
    }

    // MARK: - 几何

    private static let width: CGFloat = 1600
    private static let height: CGFloat = 1000

    private static func rectIntersection(from p: CGPoint, angle: Double) -> CGPoint {
        let dx = cos(angle), dy = sin(angle)
        var best = Double.infinity
        if dx > 1e-9 { best = min(best, Double((width - p.x) / CGFloat(dx))) }
        if dx < -1e-9 { best = min(best, Double((0 - p.x) / CGFloat(dx))) }
        if dy > 1e-9 { best = min(best, Double((height - p.y) / CGFloat(dy))) }
        if dy < -1e-9 { best = min(best, Double((0 - p.y) / CGFloat(dy))) }
        return CGPoint(x: p.x + CGFloat(dx) * CGFloat(best), y: p.y + CGFloat(dy) * CGFloat(best))
    }

    private static func rectParameter(_ p: CGPoint) -> Double {
        if abs(p.y) < 0.5 { return Double(p.x / width) }
        if abs(p.x - width) < 0.5 { return 1 + Double(p.y / height) }
        if abs(p.y - height) < 0.5 { return 2 + Double((width - p.x) / width) }
        return 3 + Double((height - p.y) / height)
    }

    private static func rectPoint(parameter: Double) -> CGPoint {
        var s = parameter.truncatingRemainder(dividingBy: 4)
        if s < 0 { s += 4 }
        if s < 1 { return CGPoint(x: CGFloat(s) * width, y: 0) }
        if s < 2 { return CGPoint(x: width, y: CGFloat(s - 1) * height) }
        if s < 3 { return CGPoint(x: width - CGFloat(s - 2) * width, y: height) }
        return CGPoint(x: 0, y: height - CGFloat(s - 3) * height)
    }

    private static func makePath(_ points: [CGPoint]) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for p in points.dropFirst() { path.addLine(to: p) }
        path.closeSubpath()
        return path
    }

    private static func area(of points: [CGPoint]) -> CGFloat {
        var sum: CGFloat = 0
        for i in 0..<points.count {
            let a = points[i]
            let b = points[(i + 1) % points.count]
            sum += a.x * b.y - b.x * a.y
        }
        return sum / 2
    }

    private static func centroid(of points: [CGPoint]) -> CGPoint {
        guard !points.isEmpty else { return .zero }
        var x: CGFloat = 0, y: CGFloat = 0
        for p in points { x += p.x; y += p.y }
        return CGPoint(x: x / CGFloat(points.count), y: y / CGFloat(points.count))
    }

    /// 最大边长：用来判断一块碎片是不是"小方正"，细长条会留长口子。
    private static func extent(of points: [CGPoint]) -> CGFloat {
        guard let first = points.first else { return 0 }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for p in points {
            minX = min(minX, p.x); maxX = max(maxX, p.x)
            minY = min(minY, p.y); maxY = max(maxY, p.y)
        }
        return max(maxX - minX, maxY - minY)
    }

    private static func perimeter(of points: [CGPoint]) -> CGFloat {
        var sum: CGFloat = 0
        for i in 0..<points.count {
            let a = points[i]
            let b = points[(i + 1) % points.count]
            sum += hypot(b.x - a.x, b.y - a.y)
        }
        return sum
    }

    private static func contains(_ point: CGPoint, in poly: [CGPoint]) -> Bool {
        var hit = false
        var j = poly.count - 1
        for i in 0..<poly.count {
            let pi = poly[i], pj = poly[j]
            if (pi.y > point.y) != (pj.y > point.y),
               point.x < (pj.x - pi.x) * (point.y - pi.y) / (pj.y - pi.y) + pi.x {
                hit.toggle()
            }
            j = i
        }
        return hit
    }

    /// 用一条带折的弦把碎片劈成两块；裂口只终止在已有裂缝上。
    private static func split(_ poly: [CGPoint], rng: inout Mulberry32) -> ([CGPoint], [CGPoint])? {
        let n = poly.count
        guard n >= 3 else { return nil }
        let parentArea = abs(area(of: poly))
        for _ in 0..<12 {
            let i = Int(rng.double() * Double(n))
            var j = (i + n / 2 + Int(rng.double() * 2)) % n
            if j == i { j = (i + 1) % n }
            let a = poly[i], b = poly[j]
            let length = hypot(b.x - a.x, b.y - a.y)
            if length < 26 { continue }
            let ampMax = min(46, length * 0.11)
            let steps = 2 + Int(rng.double() * 2)
            var mids: [CGPoint] = []
            for k in 1..<steps {
                let t = CGFloat(k) / CGFloat(steps)
                let bx = a.x + (b.x - a.x) * t
                let by = a.y + (b.y - a.y) * t
                let nx = -(b.y - a.y), ny = b.x - a.x
                let nl = hypot(nx, ny)
                let amp = ampMax * CGFloat(rng.double() * 2 - 1)
                mids.append(CGPoint(x: bx + nx / nl * amp, y: by + ny / nl * amp))
            }

            // 裂口整条都必须在碎片内部
            let pathPoints = [a] + mids + [b]
            var inside = true
            for k in 0..<pathPoints.count - 1 where inside {
                for m in 1..<4 {
                    let t = CGFloat(m) / 4
                    let p = CGPoint(
                        x: pathPoints[k].x + (pathPoints[k + 1].x - pathPoints[k].x) * t,
                        y: pathPoints[k].y + (pathPoints[k + 1].y - pathPoints[k].y) * t
                    )
                    if !contains(p, in: poly) { inside = false; break }
                }
            }
            if !inside { continue }

            var chainA: [CGPoint] = []
            var k = i
            repeat { chainA.append(poly[k]); k = (k + 1) % n } while k != j
            chainA.append(poly[j])

            var chainB: [CGPoint] = []
            k = j
            repeat { chainB.append(poly[k]); k = (k + 1) % n } while k != i
            chainB.append(poly[i])

            let p1 = chainA + mids.reversed()
            let p2 = chainB + mids
            let a1 = abs(area(of: p1)), a2 = abs(area(of: p2))
            let total = a1 + a2
            guard total > 0, a1 >= total * 0.09, a2 >= total * 0.09 else { continue }
            // 两块面积和必须等于原块，否则裂口拐出了边界，会漏空
            guard abs(total - parentArea) <= parentArea * 0.02 else { continue }
            return (p1, p2)
        }
        return nil
    }
}

/// 固定种子 PRNG（与原型里的 mulberry32 同一条序列）。
struct Mulberry32 {
    private var state: UInt32

    init(seed: UInt32) { state = seed }

    mutating func double() -> Double {
        state = state &+ 0x6D2B79F5
        var t = state
        t = (t ^ (t >> 15)) &* (1 | t)
        t = t ^ (t &+ ((t ^ (t >> 7)) &* (61 | t)))
        return Double(t ^ (t >> 14)) / 4294967296.0
    }
}

/// 碎裂的时间线状态：由 presenter 持有，Canvas 只读。
@MainActor
@Observable
final class ShatterAnimator {
    enum Phase {
        case entrance
        case revealed
        case hold
        case exit
        case done
    }

    let fracture: Fracture
    let reduceMotion: Bool
    let startedAt = Date()
    private(set) var phase: Phase = .entrance
    private(set) var exitStartedAt: Date?
    /// 等待期该掉的小碎片已经落完，画布可以停下。
    private(set) var shedSettled = false
    @ObservationIgnored private var revealTask: Task<Void, Never>?

    init(pattern: CrackPattern, reduceMotion: Bool) {
        self.fracture = Fracture.generate(pattern: pattern)
        self.reduceMotion = reduceMotion
        if reduceMotion {
            phase = .revealed
        } else {
            revealTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(Fracture.revealAt))
                guard let self, !Task.isCancelled else { return }
                self.phase = .revealed
                try? await Task.sleep(for: .seconds(Fracture.holdAt - Fracture.revealAt))
                guard !Task.isCancelled, self.phase == .revealed else { return }
                self.phase = .hold
                guard self.fracture.shedEnd > Fracture.holdAt else { return }
                try? await Task.sleep(for: .seconds(self.fracture.shedEnd - Fracture.holdAt + 0.2))
                guard !Task.isCancelled, self.phase == .hold else { return }
                self.shedSettled = true
            }
        }
    }

    var isRevealed: Bool {
        phase == .revealed || phase == .hold
    }

    var isInteractive: Bool {
        isRevealed
    }

    /// 等待期的小碎片还在掉时也要继续走时间轴，落完再停。
    var isAnimating: Bool {
        switch phase {
        case .entrance, .exit: true
        case .hold: !shedSettled
        case .revealed, .done: false
        }
    }

    func beginExit() {
        revealTask?.cancel()
        revealTask = nil
        exitStartedAt = Date()
        phase = .exit
    }

    /// 不做动画的降低动态版本：裂纹长成、一块没掉。
    func staticTime() -> (entrance: TimeInterval, exit: TimeInterval) {
        (Fracture.holdAt, 0)
    }
}
