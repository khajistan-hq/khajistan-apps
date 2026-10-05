import SwiftUI

// How the dancer looks, ported from archive/scripts/kj-scope.js: pose(), stripe(), dancerRig(),
// puppet() and the ENTER, EXIT and SMOKE pieces, line for line, with the same proportions and
// angles. `Pen` speaks the slice of the canvas 2D API those functions use, so the port reads
// like its source. The colours are the skin's: C.green is the band token (the site's --green)
// and C.ink the ink, exactly as kj-scope.js reads them off the page.

// MARK: - A canvas 2D context over GraphicsContext

struct Pen {
    struct Colours {
        let green: Color
        let ink: Color
        /// The floor shadow, rgba(5,5,5,.15) on the site in every skin.
        let shadow = Color(.sRGB, red: 5 / 255, green: 5 / 255, blue: 5 / 255, opacity: 0.15)
    }

    private var ctx: GraphicsContext
    private var t = CGAffineTransform.identity
    private var stack: [(GraphicsContext, CGAffineTransform, Color, Color, Double)] = []
    private var path = Path()
    var fillStyle: Color
    var strokeStyle: Color
    var lineWidth = 1.0
    let C: Colours

    init(_ ctx: GraphicsContext, colours: Colours) {
        self.ctx = ctx
        C = colours
        fillStyle = colours.green
        strokeStyle = colours.ink
    }

    var globalAlpha: Double {
        get { ctx.opacity }
        set { ctx.opacity = newValue }
    }

    mutating func save() { stack.append((ctx, t, fillStyle, strokeStyle, lineWidth)) }
    mutating func restore() {
        guard let top = stack.popLast() else { return }
        (ctx, t, fillStyle, strokeStyle, lineWidth) = top
    }
    mutating func translate(_ x: Double, _ y: Double) { t = CGAffineTransform(translationX: x, y: y).concatenating(t) }
    mutating func rotate(_ a: Double) { t = CGAffineTransform(rotationAngle: a).concatenating(t) }
    mutating func scale(_ x: Double, _ y: Double) { t = CGAffineTransform(scaleX: x, y: y).concatenating(t) }

    func fillRect(_ x: Double, _ y: Double, _ w: Double, _ h: Double) {
        ctx.fill(Path(CGRect(x: x, y: y, width: w, height: h)).applying(t), with: .color(fillStyle))
    }
    mutating func beginPath() { path = Path() }
    mutating func moveTo(_ x: Double, _ y: Double) { path.move(to: CGPoint(x: x, y: y).applying(t)) }
    mutating func lineTo(_ x: Double, _ y: Double) { path.addLine(to: CGPoint(x: x, y: y).applying(t)) }
    mutating func closePath() { path.closeSubpath() }
    /// canvas arc(): `anticlockwise` in the canvas's y-down sense, which is CoreGraphics' `clockwise`.
    mutating func arc(_ x: Double, _ y: Double, _ r: Double, _ a0: Double, _ a1: Double, _ anticlockwise: Bool) {
        var local = Path()
        local.addArc(center: CGPoint(x: x, y: y), radius: r, startAngle: .radians(a0), endAngle: .radians(a1),
                     clockwise: anticlockwise)
        path.addPath(local.applying(t))
    }
    func fill() { ctx.fill(path, with: .color(fillStyle)) }
    func stroke() {
        let scale = (abs(t.a * t.d - t.b * t.c)).squareRoot()
        ctx.stroke(path, with: .color(strokeStyle), lineWidth: lineWidth * scale)
    }
    /// rect() then clip(): the clip lasts until the next restore().
    mutating func clipRect(_ x: Double, _ y: Double, _ w: Double, _ h: Double) {
        ctx.clip(to: Path(CGRect(x: x, y: y, width: w, height: h)).applying(t))
    }
}

// MARK: - The figure

private let DOWN = Double.pi / 2, UP = -Double.pi / 2

private func clamp01(_ v: Double) -> Double { v < 0 ? 0 : v > 1 ? 1 : v }
private func seg(_ u: Double, _ a: Double, _ b: Double) -> Double { clamp01((u - a) / (b - a)) }
private func easeOut(_ u: Double) -> Double { 1 - (1 - u) * (1 - u) }
private func easeIn(_ u: Double) -> Double { u * u }
private func mix(_ a: Double, _ b: Double, _ u: Double) -> Double { a + (b - a) * u }

struct Leg { var thigh: Double, shin: Double }
struct Arm { var arm: Double, fore: Double }
struct Pose { var legs: [Leg], arms: [Arm] }

private let STAND = Pose(legs: [Leg(thigh: DOWN, shin: DOWN), Leg(thigh: DOWN, shin: DOWN)],
                         arms: [Arm(arm: DOWN, fore: 0), Arm(arm: DOWN, fore: 0)])
private let ARMS_UP = [Arm(arm: UP - 0.25, fore: 0), Arm(arm: UP + 0.25, fore: 0)]
private let ARMS_OUT = [Arm(arm: .pi - 0.15, fore: 0), Arm(arm: 0.15, fore: 0)]
private let HANDS_ON_HIPS = [Arm(arm: DOWN - 0.55, fore: -2.1), Arm(arm: DOWN + 0.55, fore: 2.1)]

@discardableResult
private func limb(_ g: inout Pen, _ x: Double, _ y: Double, _ len: Double, _ thick: Double, _ ang: Double) -> CGPoint {
    g.save()
    g.translate(x, y)
    g.rotate(ang)
    g.fillRect(0, -thick / 2, len, thick)
    g.restore()
    return CGPoint(x: x + cos(ang) * len, y: y + sin(ang) * len)
}

private func stripe(_ g: inout Pen, _ x: Double, _ y: Double, _ len: Double, _ thick: Double, _ ang: Double) {
    g.save(); g.translate(x, y); g.rotate(ang)
    g.fillStyle = g.C.ink
    g.fillRect(0, thick * 0.14, len, max(1, thick * 0.22))
    g.restore()
    g.fillStyle = g.C.green
}

private struct LimbPose { var thigh = 0.0, shin = 0.0, arm = 0.0, fore = 0.0, shDy = 0.0 }

private func pose(_ name: String, _ p: Double, _ side: Double, _ bass: Double, _ mid: Double, _ spin: Double, _ sub: Double) -> LimbPose {
    let alt = sin(p + (side > 0 ? .pi : 0))
    let lift = max(0, alt)
    let fast = sin(p * 4 + (side > 0 ? .pi : 0))
    let OUT = side > 0 ? 0 : Double.pi
    var o = LimbPose()
    switch name {
    case "Dabke":                    // Levant line dance: arms linked out, sharp stomps
        o.thigh = DOWN - lift * 0.78 + side * 0.10
        o.shin = DOWN + lift * 0.52 + side * 0.05
        o.arm = OUT; o.fore = 0
    case "Bhangra":                  // Indus: hands high, bounce off the shoulders
        o.thigh = DOWN - lift * 0.80 + side * 0.14
        o.shin = DOWN + lift * 0.55 + side * 0.06
        o.arm = OUT - side * (1.15 + lift * 0.14); o.fore = -side * 0.25
        o.shDy = -lift * 0.012
    case "Attan":                    // Khorasan/Afghan circle dance: arms wide, turning
        o.thigh = DOWN + side * (0.20 + lift * 0.34)
        o.shin = DOWN + side * 0.08
        o.arm = OUT - side * (0.55 + lift * 0.20); o.fore = -side * 0.35
    case "Bandari":                  // Gulf / southern Iran: hands alternate high and low
        o.thigh = DOWN + side * (0.16 + lift * 0.22)
        o.shin = DOWN + side * 0.06
        o.arm = alt > 0 ? OUT - side * 1.05 : DOWN - side * 0.55
        o.fore = alt > 0 ? -side * 0.30 : side * 0.38
        o.shDy = alt * 0.008
    case "Halay":                    // Anatolian line dance: arms low and linked
        o.thigh = DOWN + side * (0.12 + lift * 0.16)
        o.shin = DOWN + side * 0.05
        o.arm = DOWN - side * 0.22; o.fore = -side * 0.06
        o.shDy = fast * 0.006
    case "Shimmy":                   // shoulder isolation, feet planted
        o.thigh = DOWN + side * 0.13
        o.shin = DOWN + side * 0.05
        o.arm = OUT + side * (0.55 + fast * 0.10); o.fore = -side * 0.35
        o.shDy = fast * 0.014
    case "Twerk":                    // feet wide, knees out, hands braced; the hips are in the rig
        o.thigh = DOWN - side * (0.60 + lift * 0.05)
        o.shin = DOWN + side * 0.25
        o.arm = DOWN - side * 0.72
        o.fore = side * 0.40
    case "Kolo":                     // Balkan line dance: hands linked low, springy side-steps
        o.thigh = DOWN - lift * 0.42 + side * 0.22
        o.shin = DOWN + lift * 0.34 + side * 0.07
        o.arm = DOWN - side * 0.30; o.fore = -side * 0.10
        o.shDy = fast * 0.004
    case "Cocek":                    // Romani Balkan: arms up and turning, the hips leading
        o.thigh = DOWN + side * (0.18 + lift * 0.14)
        o.shin = DOWN + side * 0.05
        o.arm = UP + side * (0.55 + alt * 0.18); o.fore = side * (0.45 + fast * 0.25)
        o.shDy = alt * 0.011
    case "Rachenitsa":               // Bulgarian 7/8: arms high, fast crossing hop-kicks
        o.thigh = DOWN - lift * 0.95 - side * 0.22
        o.shin = DOWN + lift * 0.30 - side * 0.10
        o.arm = UP - side * (0.20 + alt * 0.30); o.fore = -side * 0.15
    case "Eskista":                  // Ethiopian: the shoulders do all of it, feet planted
        o.thigh = DOWN + side * 0.12
        o.shin = DOWN + side * 0.05
        o.arm = DOWN - side * 0.38; o.fore = -side * (0.95 + fast * 0.18)
        o.shDy = fast * 0.026
    case "Kawliya":                  // Iraqi hair dance: head and hair thrown, arms loose and low
        o.thigh = DOWN + side * (0.14 + lift * 0.12)
        o.shin = DOWN + side * 0.05
        o.arm = DOWN - side * (0.85 + alt * 0.25); o.fore = -side * 0.55
        o.shDy = alt * 0.010
    case "Kambala":                  // Sudanese Nuba dance: driving knees, arms out and up
        o.thigh = DOWN - lift * 1.10 + side * 0.10
        o.shin = DOWN + lift * 0.50 + side * 0.06
        o.arm = OUT - side * (0.85 + lift * 0.30); o.fore = -side * 0.20
    case "Krumping":                 // low and hard: stomps, chest pops, arms thrown open
        o.thigh = DOWN - lift * 0.85 + side * 0.26
        o.shin = DOWN + lift * 0.55 + side * 0.10
        o.arm = DOWN - side * (1.35 + alt * 0.55); o.fore = side * (0.85 - alt * 0.70)
        o.shDy = -abs(fast) * 0.016
    case "Voguing":                  // hands, the duckwalk, the death drop, and back up
        if sub >= 2 && sub < 5 {
            o.thigh = DOWN - side * (0.95 + lift * 0.35)
            o.shin = DOWN + side * (1.15 - lift * 0.30)
            o.arm = OUT - side * 0.25; o.fore = -side * 1.55
        } else if sub >= 5 && sub < 6 {
            o.thigh = side > 0 ? DOWN - 1.45 : DOWN + 0.35
            o.shin = side > 0 ? DOWN - 1.35 : DOWN + 0.95
            o.arm = side > 0 ? UP + 0.55 : .pi - 0.05
            o.fore = side > 0 ? 0.35 : -0.25
        } else {
            o.thigh = DOWN + side * (0.10 + lift * 0.10)
            o.shin = DOWN + side * 0.04
            o.arm = alt > 0 ? UP + side * 0.30 : OUT - side * 0.15
            o.fore = alt > 0 ? side * 1.75 : -side * 1.70
            o.shDy = alt * 0.006
        }
    case "Horse trot":
        o.thigh = DOWN - lift * 0.70 + side * 0.16
        o.shin = DOWN + lift * 0.60 + side * 0.06
        o.arm = DOWN - side * 0.48; o.fore = -side * (0.62 + lift * 0.14)
    case "Lasso":
        o.thigh = DOWN + side * (0.14 + lift * 0.30)
        o.shin = DOWN + side * 0.06
        o.arm = side > 0 ? spin : DOWN - 0.95
        o.fore = side > 0 ? 0.55 : -0.45
    case "Pole spin":                // inside arm on the pole overhead, the inside leg hooked
        o.thigh = side > 0 ? DOWN - 0.95 - lift * 0.25 : DOWN + 0.16
        o.shin = side > 0 ? DOWN - 0.30 : DOWN + 0.06
        o.arm = side > 0 ? UP + 0.18 : DOWN + 0.95 + lift * 0.18
        o.fore = side > 0 ? 0.05 : -0.30
    case "Side shuffle":
        o.thigh = DOWN - side * (0.34 + lift * 0.18)
        o.shin = DOWN - side * 0.14
        o.arm = DOWN - side * (0.72 + alt * 0.28); o.fore = side * 0.55
    case "Fist pumps":
        o.thigh = DOWN + side * (0.11 + bass * 0.12)
        o.shin = DOWN + side * 0.05
        o.arm = UP + side * (0.28 + alt * 0.24); o.fore = -side * (0.50 + mid * 0.40)
    case "High kicks":
        o.thigh = DOWN - lift * 1.25 + side * 0.05
        o.shin = DOWN - lift * 0.45 + side * 0.05
        o.arm = DOWN - side * (0.55 + alt * 0.35); o.fore = -side * 0.30
    case "Spin out":
        o.thigh = DOWN - side * (0.20 + lift * 0.25)
        o.shin = DOWN - side * 0.08
        o.arm = DOWN - side * (1.15 + alt * 0.20); o.fore = -side * 0.25
    default:                         // running man
        o.thigh = DOWN - lift * 1.05 + side * 0.06
        o.shin = DOWN + lift * 0.75 + side * 0.04
        o.arm = DOWN + side * 0.34 - alt * 0.80
        o.fore = side * 0.40 - alt * 0.20
    }
    if name != "Lasso" && name != "Pole spin" { o.arm -= side * mid * 0.18 }
    return o
}

/// What the rig reads from the signal this frame.
struct DancerSignal {
    var phase = 0.0      // the beat clock, 0..1
    var count = 0
    var bass = 0.0, mid = 0.0, treble = 0.0
    var level = 0.0
}

/// dancerRig(): one parametric body, posed by the move on the beat.
func drawDancer(_ g: inout Pen, w: Double, h: Double, cast ch: DancerCast, move name: String, signal b: DancerSignal) {
    let phase = b.phase * .pi * 2
    let spin = (Double(b.count % 2) + b.phase) * .pi
    let bass = b.bass, mid = b.mid, treble = b.treble
    let cx = w * 0.5, footY = h * 0.92
    var H = min(h * 0.80, w * 0.55) * ch.scale
    // Tall or scaled figures never poke above the frame, peak bounce included.
    H = min(H, (footY - h * 0.04) / (ch.torso + 0.41 + ch.headR * 2 + 0.20))
    let sw = sin(phase), lag = sin(phase - 0.9)
    let drop = pow(1 - b.phase, 2)
    let fast2 = sin(phase * 2)
    // Voguing's own running order, in beats of the move's run: 0–1 hands, 2–4 duckwalk, 5 the dip.
    let sub = name == "Voguing" ? Double(b.count % ch.cycle) + b.phase : 0
    let duckwalk: Double = name == "Voguing" && sub >= 2 && sub < 5 ? 1 : 0
    var dip = 0.0
    if name == "Voguing" && sub >= 5 && sub < 6 {
        let d = sub - 5                                // fall fast, hold the floor, get up
        dip = d < 0.18 ? easeIn(d / 0.18) : d < 0.75 ? 1 : 1 - easeOut((d - 0.75) / 0.25)
    }
    let squat = name == "Twerk" ? H * 0.05 : duckwalk * H * 0.17 + dip * H * 0.30
    let bounce = bass * H * 0.04 * ch.bassGain +
        (drop * H * 0.05 +
         (DancerMoves.hop.contains(name) ? abs(sw) * H * 0.05 : 0) +
         (name == "Fist pumps" ? max(0, sw) * H * 0.09 : 0) +
         (name == "Twerk" ? fast2 * H * 0.042 : 0)) * ch.bounce * (1 - dip)
    let leanBase: Double
    switch name {
    case "Side shuffle": leanBase = sw * 0.8
    case "Spin out": leanBase = sw * 1.1
    case "Attan": leanBase = sw * 0.7
    case "Pole spin": leanBase = 0.35
    case "Twerk": leanBase = fast2 * 0.10
    case "Cocek": leanBase = sw * 0.9
    case "Kawliya": leanBase = sw * 1.5
    case "Krumping": leanBase = sw * 0.9
    case "Voguing": leanBase = duckwalk * sw * 0.45 - dip * 1.4
    case "Shimmy": leanBase = sw * 0.05
    default: leanBase = sw * 0.2
    }
    let lean = leanBase * ch.lean
    // The two dances that ARE the head and neck move it on its own.
    let headSnap = name == "Kawliya" ? sw * 0.045 : name == "Eskista" ? -fast2 * 0.025 : 0
    let thick = max(3, H * 0.038) * ch.limbW
    let hipY = footY - H * 0.41 - bounce + squat
    let hipX = cx + (name == "Pole spin" ? -H * 0.10 : sw * H * 0.045)
    let shY = hipY - H * ch.torso
    let shX = hipX + lean * H * 0.06
    let HIP = H * ch.hipW, SHOULDER = H * ch.shoulderW

    if name == "Pole spin" {                       // the prop, behind the figure
        g.fillStyle = g.C.ink
        g.fillRect(hipX + H * 0.26 - thick * 0.35, shY - H * 0.34, thick * 0.7, footY - shY + H * 0.34)
    }

    g.fillStyle = g.C.shadow
    let shw = H * 0.30 * (1 + b.level * (dip > 0 ? 0.9 : 0.35))   // the floor takes his width
    g.fillRect(hipX - shw / 2, footY + thick * 0.6, shw, max(2, thick * 0.5))

    // The death drop turns the whole body about the hips.
    if dip > 0 { g.save(); g.translate(hipX, hipY); g.rotate(dip * 1.15); g.translate(-hipX, -hipY) }

    g.fillStyle = g.C.green
    for side in [-1.0, 1.0] {
        let pv = pose(name, phase, side, bass, mid, spin, sub)
        let hx = hipX + side * HIP
        let knee = limb(&g, hx, hipY, H * ch.thigh, thick, pv.thigh)
        stripe(&g, hx, hipY, H * ch.thigh, thick, pv.thigh)
        // The shin is posed independently: chaining it to the thigh bent the knees backwards.
        let foot = limb(&g, knee.x, knee.y, H * ch.shin, thick * 0.9, pv.shin)
        stripe(&g, knee.x, knee.y, H * ch.shin, thick * 0.9, pv.shin)
        g.fillRect(foot.x - thick * 1.1, foot.y - thick * 0.4, thick * 2.2, thick * 0.9)
    }

    limb(&g, hipX, hipY, hypot(shX - hipX, shY - hipY), thick * 1.6, atan2(shY - hipY, shX - hipX))

    for side in [-1.0, 1.0] {
        let pv = pose(name, phase, side, bass, mid, spin, sub)
        let sx = shX + side * SHOULDER, sy = shY + thick * 0.4 + pv.shDy * H
        let elbow = limb(&g, sx, sy, H * ch.armLen, thick * 0.85, pv.arm)
        stripe(&g, sx, sy, H * ch.armLen, thick * 0.85, pv.arm)
        limb(&g, elbow.x, elbow.y, H * ch.foreLen, thick * 0.75, pv.arm + pv.fore)
    }

    let hr = H * ch.headR
    let headY = shY - H * 0.05 - hr - treble * H * 0.03
    let headX = shX + lean * H * 0.02 + headSnap * H
    g.fillStyle = g.C.green
    g.fillRect(headX - thick * 0.5, headY + hr, thick, shY - headY - hr + thick)
    g.fillStyle = g.C.ink
    if ch.hair {
        // A crown a little wider than the head and a fall past the shoulders; the hair dance whips it.
        let hw = hr * 1.06, sway = lag * hr * (name == "Kawliya" ? 0.55 : 0.28), top = headY - hr * 1.14
        g.fillRect(headX - hw, top, hw * 2, hr * 0.8)
        g.fillRect(headX - hr * 1.22 + sway, top + hr * 0.5, hr * 2.44, (shY + H * 0.03) - (top + hr * 0.5))
    }
    g.fillRect(headX - hr, headY - hr, hr * 2, hr * 2)
    g.fillStyle = g.C.green
    g.fillRect(headX - hr * 1.12, headY - hr * 0.62, hr * 2.24, hr * 0.3)
    if dip > 0 { g.restore() }
}

// MARK: - The puppet: the same body, posed by hand, for the entrances, exits and breaks

/// Where the body's parts ended up, for a prop drawn in body space.
struct Body {
    let hipY: Double, shY: Double, headY: Double, hr: Double, thick: Double, H: Double
}

private struct Puppet {
    var x: Double, footY: Double, H: Double
    var legs: [Leg]? = nil
    var arms: [Arm]? = nil
    var lift = 0.0, lean = 0.0, tilt = 0.0, rot = 0.0, pivot = 0.0
    var alpha: Double? = nil
    var hair: Bool? = nil
    var skirt = false
    var props: ((inout Pen, Body) -> Void)? = nil
}

private func puppet(_ g: inout Pen, _ P: Puppet, cast ch: DancerCast) {
    // The figure's own build, so the body that walks on is the body that dances.
    let H = P.H * ch.scale, thick = max(3, H * 0.038) * ch.limbW
    let hair = P.hair ?? ch.hair
    let legs = P.legs ?? STAND.legs
    let arms = P.arms ?? STAND.arms
    g.save()
    g.translate(P.x, P.footY - P.pivot)
    g.rotate(P.rot)
    g.translate(0, P.pivot)
    if let alpha = P.alpha { g.globalAlpha = alpha }
    let hipY = -H * 0.41 - P.lift, hipX = 0.0
    let shY = hipY - H * ch.torso, shX = P.lean * H * 0.06
    let HIP = H * ch.hipW, SH = H * ch.shoulderW
    g.fillStyle = g.C.green
    for (i, side) in [-1.0, 1.0].enumerated() {
        let L = legs[i], hx = hipX + side * HIP
        let knee = limb(&g, hx, hipY, H * ch.thigh, thick, L.thigh)
        stripe(&g, hx, hipY, H * ch.thigh, thick, L.thigh)
        let foot = limb(&g, knee.x, knee.y, H * ch.shin, thick * 0.9, L.shin)
        stripe(&g, knee.x, knee.y, H * ch.shin, thick * 0.9, L.shin)
        g.fillRect(foot.x - thick * 1.1, foot.y - thick * 0.4, thick * 2.2, thick * 0.9)
    }
    if P.skirt {
        let hem = H * 0.19, hemY = hipY + H * 0.17
        g.beginPath()
        g.moveTo(hipX - HIP * 1.05, hipY - H * 0.02); g.lineTo(hipX + HIP * 1.05, hipY - H * 0.02)
        g.lineTo(hipX + hem, hemY); g.lineTo(hipX - hem, hemY); g.closePath(); g.fill()
    }
    limb(&g, hipX, hipY, hypot(shX - hipX, shY - hipY), thick * 1.6, atan2(shY - hipY, shX - hipX))
    for (i, side) in [-1.0, 1.0].enumerated() {
        let A = arms[i], sx = shX + side * SH, sy = shY + thick * 0.4
        let elbow = limb(&g, sx, sy, H * ch.armLen, thick * 0.85, A.arm)
        stripe(&g, sx, sy, H * ch.armLen, thick * 0.85, A.arm)
        limb(&g, elbow.x, elbow.y, H * ch.foreLen, thick * 0.75, A.arm + A.fore)
    }
    let hr = H * ch.headR, headY = shY - H * 0.05 - hr, headX = shX + P.tilt * hr
    g.fillStyle = g.C.green
    g.fillRect(headX - thick * 0.5, headY + hr, thick, shY - headY - hr + thick)
    g.fillStyle = g.C.ink
    if hair {
        let hw = hr * 1.06, top = headY - hr * 1.14
        g.fillRect(headX - hw, top, hw * 2, hr * 0.8)
        g.fillRect(headX - hr * 1.22, top + hr * 0.5, hr * 2.44, (shY + H * 0.03) - (top + hr * 0.5))
    }
    g.fillRect(headX - hr, headY - hr, hr * 2, hr * 2)
    g.fillStyle = g.C.green
    g.fillRect(headX - hr * 1.12, headY - hr * 0.62, hr * 2.24, hr * 0.3)
    P.props?(&g, Body(hipY: hipY, shY: shY, headY: headY, hr: hr, thick: thick, H: H))
    g.restore()
}

/// A walking cycle at phase w; stride 0 is standing still.
private func gait(_ w: Double, _ stride: Double, _ H: Double) -> (legs: [Leg], arms: [Arm], lift: Double) {
    let sw = sin(w) * 0.36 * stride
    return ([Leg(thigh: DOWN + sw, shin: DOWN + sw * 0.6), Leg(thigh: DOWN - sw, shin: DOWN - sw * 0.6)],
            [Arm(arm: DOWN - sw * 0.9, fore: -0.5 * stride), Arm(arm: DOWN + sw * 0.9, fore: 0.5 * stride)],
            abs(cos(w)) * H * 0.02 * stride)
}
/// A knee bend seen from the front: knees out, feet back under the hips.
private func squat(_ k: Double) -> [Leg] {
    [Leg(thigh: DOWN + 0.55 * k, shin: DOWN - 0.95 * k), Leg(thigh: DOWN - 0.55 * k, shin: DOWN + 0.95 * k)]
}
/// How far the hips must fall for the feet to stay on the floor at that depth.
private func squatDrop(_ k: Double, _ H: Double) -> Double { H * (0.41 - (0.21 * cos(0.55 * k) + 0.20 * cos(0.95 * k))) }
private func blendPose(_ A: Pose, _ B: Pose, _ u: Double) -> Pose {
    Pose(legs: (0..<2).map { Leg(thigh: mix(A.legs[$0].thigh, B.legs[$0].thigh, u), shin: mix(A.legs[$0].shin, B.legs[$0].shin, u)) },
         arms: (0..<2).map { Arm(arm: mix(A.arms[$0].arm, B.arms[$0].arm, u), fore: mix(A.arms[$0].fore, B.arms[$0].fore, u)) })
}
private func burst(_ g: inout Pen, _ x: Double, _ y: Double, _ r: Double, _ th: Double) {   // the sting of a slap
    g.save(); g.strokeStyle = g.C.ink; g.lineWidth = th; g.beginPath()
    for i in 0..<6 {
        let a = Double(i) * .pi / 3 + 0.35
        g.moveTo(x + cos(a) * r * 0.7, y + sin(a) * r * 0.7)
        g.lineTo(x + cos(a) * r * 1.3, y + sin(a) * r * 1.3)
    }
    g.stroke(); g.restore()
}
private func arrowGlyph(_ g: inout Pen, _ x: Double, _ y: Double, _ len: Double, _ th: Double) {   // tip at (x, y), flying right
    g.fillStyle = g.C.ink
    g.fillRect(x - len, y - th * 0.28, len, th * 0.56)
    g.beginPath(); g.moveTo(x, y - th * 1.1); g.lineTo(x + th * 3, y); g.lineTo(x, y + th * 1.1); g.closePath(); g.fill()
    g.fillStyle = g.C.green
    g.fillRect(x - len, y - th * 1.4, th * 3, th * 1.1)
    g.fillRect(x - len, y + th * 0.3, th * 3, th * 1.1)
}

/// The stage a piece plays on.
struct Stage {
    let w: Double, h: Double
    var H: Double { min(h * 0.80, w * 0.55) }
    var cx: Double { w * 0.5 }
    var footY: Double { h * 0.92 }
    func fromEdge(_ side: Double) -> Double { cx + side * (w * 0.5 + H * 0.35) }
}

private func trapdoor(_ g: inout Pen, _ k: Stage, _ open: Double) {     // two flaps hinged at the ends
    let th = max(3, k.H * 0.038), w = k.H * 0.26, y = k.footY + th * 0.5
    g.fillStyle = g.C.ink
    g.fillRect(k.cx - w - th * 0.6, y, th * 0.6, th * 1.6)
    g.fillRect(k.cx + w, y, th * 0.6, th * 1.6)
    for side in [-1.0, 1.0] {
        g.save(); g.translate(k.cx + side * w, y); g.rotate(-side * open * .pi / 2)
        g.fillRect(side > 0 ? -w : 0, 0, w, th * 0.8)
        g.restore()
    }
}
private func clipAboveFloor(_ g: inout Pen, _ k: Stage, _ fn: (inout Pen) -> Void) {
    let th = max(3, k.H * 0.038)
    g.save(); g.clipRect(0, 0, k.w, k.footY + th * 0.5); fn(&g); g.restore()
}

// MARK: - The pieces

/// One frame of an entrance, exit or break. `u` runs 0 to 1 across the piece; `side` is the
/// wing it plays from; `beatPhase` keeps a smoker swaying to what he can still hear.
func drawPiece(_ g: inout Pen, stage: DancerStage.Name, kind: String, u: Double, side: Double,
               cast ch: DancerCast, beatPhase: Double, on k: Stage) {
    func pup(_ P: Puppet) { puppet(&g, P, cast: ch) }
    let H = k.H, th = max(3, H * 0.038)
    switch (stage, kind) {

    // ── ENTER ──
    case (.enter, "walk"):                    // walks on from one side and stops centre stage
        let x = mix(k.fromEdge(side), k.cx, easeOut(u)), stride = 1 - seg(u, 0.82, 1)
        let G = gait(u * 11, stride, H)
        pup(Puppet(x: x, footY: k.footY, H: H, legs: G.legs, arms: G.arms, lift: G.lift, lean: -side * 0.6 * stride))
    case (.enter, "rope"):                    // down a rope, knees give on landing, the rope hauled away
        let foot = mix(-H * 0.2, k.footY, easeOut(seg(u, 0, 0.6)))
        let give = sin(seg(u, 0.58, 0.9) * .pi) * 0.8, hold = 1 - seg(u, 0.65, 0.9)
        let arms = [Arm(arm: mix(DOWN, UP - 0.12, hold), fore: 0), Arm(arm: mix(DOWN, UP + 0.12, hold), fore: 0)]
        if hold > 0 {
            let handY = foot - H * 1.08
            g.globalAlpha = hold; g.fillStyle = g.C.ink; g.fillRect(k.cx - th * 0.3, 0, th * 0.6, max(0, handY)); g.globalAlpha = 1
        }
        pup(Puppet(x: k.cx, footY: foot, H: H, legs: squat(give), arms: arms, lift: -H * 0.09 * give))
    case (.enter, "slide"):                   // slides in on his knees, arms wide, and pops up
        let x = mix(k.fromEdge(side), k.cx, easeOut(seg(u, 0, 0.7))), up = seg(u, 0.72, 1)
        let back = side > 0 ? 0 : Double.pi
        let knees = Pose(legs: [Leg(thigh: DOWN, shin: back), Leg(thigh: DOWN, shin: back)], arms: ARMS_OUT)
        let P = blendPose(knees, STAND, up)
        pup(Puppet(x: x, footY: k.footY, H: H, legs: P.legs, arms: P.arms, lift: -H * 0.20 * (1 - up), lean: -side * 0.5 * (1 - up)))
    case (.enter, "kicked"):                  // a boot from the wings; he tumbles in, gets up, dusts off
        let edge = k.fromEdge(side)
        let swing = sin(seg(u, 0, 0.3) * .pi)
        let bx = edge + side * H * 0.35 - side * swing * H * 1.05, by = k.footY - H * 0.25
        let toeX = side > 0 ? bx - th * 1.6 - H * 0.22 : bx - th * 1.6
        g.fillStyle = g.C.ink
        g.fillRect(bx - th * 1.6, by - H * 0.6, th * 3.2, H * 0.45)
        g.fillRect(toeX, by - H * 0.15, th * 3.2 + H * 0.22, H * 0.15)
        g.fillStyle = g.C.green; g.fillRect(toeX, by - th * 0.6, th * 3.2 + H * 0.22, th * 0.6)
        let fly = seg(u, 0.15, 0.55), land = seg(u, 0.55, 0.7), rise = seg(u, 0.7, 1)
        let x = mix(edge, k.cx, easeOut(fly)), arc = sin(fly * .pi) * H * 0.45
        let heap = Pose(legs: [Leg(thigh: DOWN + 1.0, shin: DOWN + 0.3), Leg(thigh: DOWN - 1.0, shin: DOWN - 0.3)], arms: ARMS_OUT)
        let brush = sin(rise * .pi * 4) * 0.5
        let dust = Pose(legs: STAND.legs, arms: [Arm(arm: DOWN - 0.5 + brush, fore: -1.8), Arm(arm: DOWN + 0.5 - brush, fore: 1.8)])
        let P = rise < 1 ? blendPose(fly < 1 ? STAND : heap, rise > 0 ? dust : heap, rise) : STAND
        pup(Puppet(x: x, footY: k.footY, H: H, legs: P.legs, arms: P.arms,
                   lift: arc - H * 0.28 * (land - rise > 0 ? 1 : land) * (1 - rise),
                   rot: -side * 1.4 * sin(fly * .pi) * (1 - land), pivot: H * 0.5))
    case (.enter, "trapdoor"):                // up through the floor
        let open = sin(seg(u, 0, 1) * .pi) > 0 ? min(1, seg(u, 0, 0.18), 1 - seg(u, 0.82, 1)) : 0
        let foot = mix(k.footY + H * 1.25, k.footY, easeOut(seg(u, 0.15, 0.78)))
        let up = 1 - seg(u, 0.7, 0.95)
        let P = blendPose(STAND, Pose(legs: STAND.legs, arms: ARMS_UP), up)
        trapdoor(&g, k, open)
        clipAboveFloor(&g, k) { g2 in puppet(&g2, Puppet(x: k.cx, footY: foot, H: H, legs: P.legs, arms: P.arms), cast: ch) }
    case (.enter, "cartwheel"):               // two cartwheels from the wings, landing centre
        let roll = seg(u, 0, 0.85), x = mix(k.fromEdge(side), k.cx, easeOut(roll)), settle = seg(u, 0.85, 1)
        let star = Pose(legs: [Leg(thigh: DOWN + 0.6, shin: DOWN + 0.6), Leg(thigh: DOWN - 0.6, shin: DOWN - 0.6)], arms: ARMS_UP)
        let P = blendPose(star, STAND, settle)
        pup(Puppet(x: x, footY: k.footY, H: H, legs: P.legs, arms: P.arms, lift: H * 0.08 * (1 - settle),
                   rot: -side * .pi * 4 * roll, pivot: H * 0.55 * (1 - settle)))

    // ── EXIT ──
    case (.leave, "arrow"):                   // an arrow; he clutches it, sways, goes over and is slid off
        let chestY = k.footY - H * 0.62, hit = seg(u, 0, 0.26), len = H * 0.42
        if hit < 1 {
            let tip = mix(k.fromEdge(-side), k.cx - side * H * 0.02, hit)
            g.save(); if side < 0 { g.translate(tip, chestY); g.scale(-1, 1); g.translate(-tip, -chestY) }
            arrowGlyph(&g, tip, chestY, len, th); g.restore()
        }
        let clutch = seg(u, 0.26, 0.4), sway = seg(u, 0.4, 0.62), fall = easeIn(seg(u, 0.62, 0.84)), slide = easeIn(seg(u, 0.84, 1))
        let hands = Pose(legs: squat(0.5 * sway), arms: [Arm(arm: DOWN - 0.9, fore: -1.9), Arm(arm: DOWN + 0.9, fore: 1.9)])
        let P = blendPose(STAND, hands, clutch)
        let wobble = sin(sway * .pi * 5) * 0.07 * (1 - fall)
        pup(Puppet(x: k.cx + side * slide * (k.w * 0.6 + H), footY: k.footY, H: H, legs: P.legs, arms: P.arms,
                   lift: -H * 0.06 * sway, lean: -side * 1.3 * clutch * (1 - fall), tilt: -side * 1.2 * clutch,
                   rot: side * (.pi / 2 + 0.04) * fall + wobble,
                   props: hit < 1 ? nil : { g2, b in
                       g2.save(); if side < 0 { g2.scale(-1, 1) }
                       arrowGlyph(&g2, -b.H * 0.02, b.shY + b.H * 0.1, len, b.thick); g2.restore()
                   }))
    case (.leave, "slap"):                    // a girl marches in and slaps him off, one step at a time
        let slaps = [0.30, 0.48, 0.66], gap = H * 0.42
        var hits = 0.0, sting = 0.0, wind = 0.0
        for at in slaps {
            if u >= at { hits += 1; sting = max(sting, 1 - seg(u, at, at + 0.07)) }
            wind = max(wind, sin(seg(u, at - 0.07, at) * .pi / 2) * (u < at ? 1 : 0))
        }
        let shove = H * 0.24 * hits, spin = seg(u, 0.70, 0.86), off = seg(u, 0.86, 1)
        let hx = k.cx - side * (shove * (1 - spin) + spin * (k.w * 0.6 + H))
        // him: flinches with each slap, staggers, and after the third spins off the stage
        let flinch = Pose(legs: squat(0.5), arms: [Arm(arm: DOWN - 1.1, fore: -1.4), Arm(arm: DOWN + 1.1, fore: 1.4)])
        let flail = Pose(legs: [Leg(thigh: DOWN + 0.7, shin: DOWN + 0.5), Leg(thigh: DOWN - 0.7, shin: DOWN - 0.5)], arms: ARMS_UP)
        let Pm = spin > 0 ? blendPose(flinch, flail, min(1, spin * 3)) : blendPose(STAND, flinch, sting)
        pup(Puppet(x: hx, footY: k.footY, H: H, legs: Pm.legs, arms: Pm.arms,
                   lift: abs(sin(sting * .pi)) * H * 0.04, lean: -side * 1.6 * sting * (1 - spin),
                   tilt: -side * 1.4 * sting * (1 - spin), rot: -side * spin * 9, pivot: H * 0.5 * spin, alpha: 1 - off * off))
        if sting > 0.55 && spin == 0 { burst(&g, hx - side * H * 0.12, k.footY - H * 1.0, H * 0.11, th * 0.4) }
        // her: in from the other side, keeps pace with each stagger, hands on hips, then off
        let arrive = easeOut(seg(u, 0, 0.22)), leave = easeIn(seg(u, 0.86, 1))
        var gx = mix(k.fromEdge(side), k.cx + side * gap - side * shove * (1 - spin) + side * (k.w * 0.6 + H) * leave, arrive < 1 ? arrive : 1)
        if arrive == 1 && leave == 0 { gx = k.cx + side * gap - side * shove * (1 - spin) }
        let walking: Double = arrive < 1 || leave > 0 ? 1 : 0
        let G = gait(u * 26, walking, H)
        let swing = wind > 0 ? mix(DOWN, UP + side * 0.3, wind)
            : (sting > 0 && spin == 0 ? mix(side > 0 ? .pi + 0.15 : -0.15, DOWN, 1 - sting)
               : (spin > 0 || u > 0.7 ? HANDS_ON_HIPS[side > 0 ? 0 : 1].arm : DOWN))
        let slapArm = side > 0 ? 0 : 1                                   // the arm nearer to him
        let hipsFore = spin > 0 || u > 0.7
        let arms: [Arm] = walking > 0 ? G.arms : [
            slapArm == 0 ? Arm(arm: swing, fore: hipsFore ? HANDS_ON_HIPS[0].fore : 0) : (u > 0.7 ? HANDS_ON_HIPS[0] : Arm(arm: DOWN, fore: 0)),
            slapArm == 1 ? Arm(arm: swing, fore: hipsFore ? HANDS_ON_HIPS[1].fore : 0) : (u > 0.7 ? HANDS_ON_HIPS[1] : Arm(arm: DOWN, fore: 0))]
        pup(Puppet(x: gx, footY: k.footY, H: H * 0.96, legs: walking > 0 ? G.legs : STAND.legs, arms: arms, lift: G.lift,
                   lean: side * (wind * 0.6 - sting * 0.9), hair: true, skirt: true))
    case (.leave, "hook"):                    // a crook at neck height, and he is hauled off, legs going
        let reach = easeOut(seg(u, 0, 0.32)), yank = easeIn(seg(u, 0.4, 1))
        let x = k.cx + side * yank * (k.w * 0.6 + H), neckY = k.footY - H * 0.78 - (yank > 0 ? H * 0.06 : 0)
        let hookX = mix(k.fromEdge(side), k.cx, reach) + side * yank * (k.w * 0.6 + H), r = H * 0.085
        g.save(); g.strokeStyle = g.C.ink; g.lineWidth = th * 0.7; g.beginPath()
        g.arc(hookX, neckY, r, -.pi / 2, .pi / 2, side > 0)
        g.moveTo(hookX, neckY - r); g.lineTo(k.fromEdge(side) + side * H, neckY - r); g.stroke(); g.restore()
        let kick = sin(u * 70) * 0.55 * (yank > 0 ? 1 : 0), startle = seg(u, 0.3, 0.4)
        let legs = [Leg(thigh: DOWN + kick, shin: DOWN + kick * 0.5), Leg(thigh: DOWN - kick, shin: DOWN - kick * 0.5)]
        let arms = blendPose(STAND, Pose(legs: STAND.legs, arms: ARMS_UP), startle).arms
        pup(Puppet(x: x, footY: k.footY, H: H, legs: legs, arms: arms, lift: H * 0.06 * startle, rot: -side * 0.4 * yank, pivot: H * 0.78))
    case (.leave, "trapdoor"):                // down through the floor; the flaps shut on a puff of dust
        let open = min(seg(u, 0, 0.18), 1 - seg(u, 0.68, 0.86))
        let foot = mix(k.footY, k.footY + H * 1.3, easeIn(seg(u, 0.2, 0.66)))
        let P = blendPose(STAND, Pose(legs: STAND.legs, arms: ARMS_UP), seg(u, 0.15, 0.3))
        trapdoor(&g, k, open)
        clipAboveFloor(&g, k) { g2 in puppet(&g2, Puppet(x: k.cx, footY: foot, H: H, legs: P.legs, arms: P.arms), cast: ch) }
        let puff = seg(u, 0.7, 1)
        if puff > 0 && puff < 1 {
            g.globalAlpha = 1 - puff; g.fillStyle = g.C.ink
            for s in [-1.0, 1.0] {
                let d = th * (1.5 - puff)
                g.fillRect(k.cx + s * H * 0.2 * (1 + puff) - d / 2, k.footY - th * 2 - puff * H * 0.12 - d / 2, d, d)
            }
            g.globalAlpha = 1
        }
    case (.leave, "broom"):                   // swept off with a broom, hopping and protesting
        let bx = mix(k.fromEdge(-side), k.fromEdge(side) + side * H * 0.3, easeIn(seg(u, 0, 1))) + sin(u * 28) * H * 0.05 * side
        let x = side > 0 ? max(k.cx, bx + H * 0.24) : min(k.cx, bx - H * 0.24)
        let pushed = side > 0 ? (bx + H * 0.24 > k.cx) : (bx - H * 0.24 < k.cx)
        let hop = pushed ? abs(sin(u * 40)) * H * 0.035 : 0
        let protest = blendPose(STAND, Pose(legs: [Leg(thigh: DOWN + 0.12, shin: DOWN), Leg(thigh: DOWN - 0.12, shin: DOWN)], arms: ARMS_UP),
                                pushed ? 1 : seg(u, 0.1, 0.25))
        pup(Puppet(x: x, footY: k.footY, H: H, legs: protest.legs, arms: protest.arms, lift: hop, lean: side * (pushed ? 0.9 : 0)))
        g.save(); g.translate(bx, k.footY)                          // handle, then bristles
        g.fillStyle = g.C.ink; g.rotate(-side * 0.55); g.fillRect(-th * 0.35, -H * 1.1, th * 0.7, H * 1.1); g.rotate(side * 0.55)
        g.fillStyle = g.C.green; g.fillRect(-H * 0.07, -H * 0.17, H * 0.14, H * 0.17)
        g.fillStyle = g.C.ink; g.fillRect(-H * 0.07, -H * 0.17, H * 0.14, th * 0.5)
        g.restore()
    case (.leave, "bow"):                     // he bows, and the frame fades him out
        let bend = sin(seg(u, 0.05, 0.75) * .pi) * 1.0, out = easeIn(seg(u, 0.6, 1))
        let arms = [Arm(arm: DOWN - 0.3 + bend * 0.9, fore: 0), Arm(arm: .pi - 0.2 - bend * 0.4, fore: -0.6)]
        pup(Puppet(x: k.cx, footY: k.footY, H: H, arms: arms, lean: -bend * 2.2, tilt: -bend * 0.6, alpha: 1 - out))

    // ── THE BREAK ──
    case (.smoke, "cigarette"):               // lights one, three drags, flicks it away
        let lit = seg(u, 0.18, 0.20), gone = seg(u, 0.90, 1)
        let reach = sin(seg(u, 0.02, 0.24) * .pi)
        var drag = 0.0
        for at in [0.34, 0.54, 0.74] { drag = max(drag, sin(seg(u, at, at + 0.10) * .pi)) }
        let flick = sin(seg(u, 0.84, 0.96) * .pi)
        let sway = sin(beatPhase * .pi * 2) * 0.25                 // he is still hearing it
        pup(Puppet(x: k.cx, footY: k.footY, H: H,
                   legs: [Leg(thigh: DOWN + 0.10, shin: DOWN - 0.04), Leg(thigh: DOWN - 0.16, shin: DOWN + 0.06)],
                   arms: smokingArms(max(reach, drag, flick)), lean: sway, tilt: sway * 0.3,
                   props: { g2, b in cigarette(&g2, b, u: u, t0: 0.20, lit: lit, gone: gone, side: side, H: H) }))
    case (.smoke, "yoga"):                    // seven poses held, the cigarette in the whole way through
        let LIE = -1.36, DOG = -1.18
        func toFloor(_ rot: Double) -> Double { atan2(cos(rot), sin(rot)) }
        struct Hold { var p: Pose; var lean = 0.0, lift = 0.0, rot = 0.0, tilt = 0.0 }
        let poses: [Hold] = [
            Hold(p: Pose(legs: [Leg(thigh: DOWN, shin: DOWN), Leg(thigh: 0.55, shin: 2.45)],              // tree
                         arms: [Arm(arm: UP + 0.12, fore: -0.12), Arm(arm: UP - 0.12, fore: 0.12)])),
            Hold(p: Pose(legs: [Leg(thigh: DOWN + 0.55, shin: DOWN - 0.30), Leg(thigh: DOWN - 0.55, shin: DOWN - 0.55)],
                         arms: ARMS_OUT)),                                                               // warrior
            Hold(p: Pose(legs: [Leg(thigh: DOWN + 0.80, shin: DOWN + 0.80), Leg(thigh: DOWN - 0.90, shin: DOWN + 0.08)],
                         arms: ARMS_UP), lean: 0.5, lift: -H * 0.08),                                    // lunge
            Hold(p: Pose(legs: STAND.legs, arms: [Arm(arm: toFloor(LIE) - 0.70, fore: 0.70), Arm(arm: toFloor(LIE) - 0.70, fore: 0.70)]),
                 rot: LIE),                                                                              // chaturanga
            Hold(p: Pose(legs: STAND.legs, arms: [Arm(arm: toFloor(DOG), fore: 0), Arm(arm: toFloor(DOG), fore: 0)]),
                 lean: -0.9, rot: DOG, tilt: -0.5),                                                      // upward dog
            Hold(p: Pose(legs: squat(0.85), arms: ARMS_UP), lift: -squatDrop(0.85, H)),                  // chair
            Hold(p: Pose(legs: [Leg(thigh: DOWN + 0.18, shin: DOWN), Leg(thigh: DOWN - 0.18, shin: DOWN)],
                         arms: [Arm(arm: UP + 0.55, fore: 0.18), Arm(arm: DOWN + 0.35, fore: 0.95)]), lean: 1.7)
        ]
        let lit = seg(u, 0.05, 0.07)
        let span = 1 / Double(poses.count), idx = min(poses.count - 1, Int(u / span))
        let local = (u - Double(idx) * span) / span
        let prev = idx > 0 ? poses[idx - 1] : Hold(p: STAND)
        let into = easeOut(seg(local, 0, 0.30))
        let out = idx == poses.count - 1 ? easeIn(seg(local, 0.78, 1)) : 0
        var P = blendPose(prev.p, poses[idx].p, into)
        if out > 0 { P = blendPose(P, STAND, out) }
        let lean = mix(prev.lean, poses[idx].lean, into) * (1 - out)
        let lift = mix(prev.lift, poses[idx].lift, into) * (1 - out)
        let rot = mix(prev.rot, poses[idx].rot, into) * (1 - out)
        let tilt = mix(prev.tilt, poses[idx].tilt, into) * (1 - out)
        pup(Puppet(x: k.cx, footY: k.footY, H: H, legs: P.legs, arms: P.arms, lift: lift, lean: lean,
                   tilt: tilt != 0 ? tilt : lean * 0.3, rot: rot,
                   props: { g2, b in cigarette(&g2, b, u: u, t0: 0.07, lit: lit, gone: 0, side: side, H: H, rot: rot) }))
    case (.smoke, "tea"):                     // blows across the top, three sips, sets it down
        let got = seg(u, 0.10, 0.13)
        let blow = sin(seg(u, 0.16, 0.30) * .pi)
        var sip = 0.0
        for at in [0.38, 0.56, 0.74] { sip = max(sip, sin(seg(u, at, at + 0.09) * .pi)) }
        let away = seg(u, 0.90, 1)
        let toMouth = max(sip, blow * 0.55) * (1 - away)
        let sway = sin(beatPhase * .pi * 2) * 0.20
        pup(Puppet(x: k.cx, footY: k.footY, H: H,
                   legs: [Leg(thigh: DOWN + 0.13, shin: DOWN - 0.05), Leg(thigh: DOWN - 0.13, shin: DOWN + 0.05)],
                   arms: smokingArms(toMouth * 0.82), lean: sway, tilt: sway * 0.3 - sip * 0.35,
                   props: { g2, b in
                       if got == 0 || away >= 1 { return }
                       let cx2 = mix(b.hr * 1.5, b.hr * 1.05, toMouth)
                       let cy = mix(b.shY + b.H * 0.085, b.headY + b.hr * 1.15, toMouth)
                       let w = b.hr * 0.95, h = b.hr * 0.85, t = max(2, b.thick * 0.30)
                       g2.fillStyle = g2.C.ink
                       g2.fillRect(cx2 - w / 2, cy - h / 2, w, h)
                       g2.fillRect(cx2 + w / 2, cy - h * 0.22, t * 1.6, t)       // the handle
                       g2.fillStyle = g2.C.green                                 // rim, so it is not a blob
                       g2.fillRect(cx2 - w / 2, cy - h / 2, w, max(1, h * 0.22))
                       plume(&g2, b, x: cx2, y: cy - h / 2, u: u, t0: 0.13, H: H, rate: 2.1, spread: b.hr * 0.40 + blow * b.hr * 0.9)
                   }))
    case (.smoke, "phone"):                   // paces the stage with it at his ear, the free hand talking
        let up = seg(u, 0.04, 0.12), down = 1 - seg(u, 0.88, 0.96)
        let hold = min(up, down)
        let walk = sin(u * .pi * 4.5)
        let G = gait(u * 30, abs(cos(u * .pi * 4.5)) * hold, H)
        let talk = sin(u * 21), nod = sin(u * 9)
        let arms = [Arm(arm: mix(G.arms[0].arm, UP + 1.0, hold), fore: mix(G.arms[0].fore, -2.5, hold)),
                    Arm(arm: mix(G.arms[1].arm, DOWN - 0.70 + talk * 0.40, hold), fore: mix(G.arms[1].fore, -1.15 + talk * 0.55, hold))]
        pup(Puppet(x: k.cx + walk * H * 0.26, footY: k.footY, H: H, legs: G.legs, arms: arms,
                   lift: G.lift, lean: nod * 0.30, tilt: nod * 0.55,
                   props: { g2, b in
                       if hold == 0 { return }
                       let px = b.hr * 1.12, pw = b.hr * 0.55, ph = b.hr * 1.25
                       g2.fillStyle = g2.C.ink
                       g2.fillRect(px, b.headY - b.hr * 0.55, pw, ph)
                       g2.fillStyle = g2.C.green
                       g2.fillRect(px + pw * 0.22, b.headY - b.hr * 0.30, pw * 0.56, ph * 0.45)
                   }))
    case (.smoke, "rolling"):                 // down on his haunches to roll one, licks it, lights it
        let down = easeOut(seg(u, 0, 0.12)), rise = easeIn(seg(u, 0.70, 0.84))
        let deep = down * (1 - rise)
        let roll = u > 0.14 && u < 0.56 ? sin(u * 130) * 0.13 : 0
        let lick = sin(seg(u, 0.56, 0.66) * .pi)
        let lit = seg(u, 0.86, 0.88)
        let drag = sin(seg(u, 0.90, 1) * .pi)
        let toMouth = max(lick, drag)
        let hands = [Arm(arm: mix(DOWN - 0.95, UP + 1.0, toMouth), fore: mix(-0.90 + roll, -2.5, toMouth)),
                     Arm(arm: DOWN + 0.95, fore: 0.90 - roll)]
        let P = blendPose(STAND, Pose(legs: squat(1.15), arms: hands), deep)
        pup(Puppet(x: k.cx, footY: k.footY, H: H, legs: P.legs, arms: hands, lift: -squatDrop(1.15, H) * deep,
                   props: { g2, b in
                       if lit == 0 {                                   // the paper, between the hands
                           g2.fillStyle = g2.C.ink
                           g2.fillRect(-H * 0.045, b.hipY - H * 0.07, H * 0.09, max(2, b.thick * 0.30))
                           return
                       }
                       cigarette(&g2, b, u: u, t0: 0.88, lit: lit, gone: 0, side: side, H: H)
                   }))
    default:
        break
    }
}

/// The hand that goes up to the mouth, and the one that does not.
private func smokingArms(_ toMouth: Double) -> [Arm] {
    [Arm(arm: mix(DOWN, UP + 1.0, toMouth), fore: mix(0, -2.5, toMouth)), Arm(arm: DOWN + 0.18, fore: 0.25)]
}

private func cigarette(_ g: inout Pen, _ b: Body, u: Double, t0: Double, lit: Double, gone: Double, side: Double, H: Double, rot: Double = 0) {
    let mx = b.hr * 0.9, my = b.headY + b.hr * 0.25, len = b.hr * 1.5
    let t = max(2, b.thick * 0.34)
    g.fillStyle = g.C.ink
    if gone < 1 {                                          // in the mouth, tip lit
        g.fillRect(mx, my - t / 2, len, t)
        if lit > 0 { g.fillStyle = g.C.green; g.fillRect(mx + len - t, my - t * 0.9, t * 1.8, t * 1.8) }
    } else {                                               // flicked into the wings
        g.fillRect(mx + side * gone * H * 0.9, my - sin(gone * .pi) * H * 0.22 + gone * H * 0.3, t * 2, t)
    }
    if lit == 0 { return }
    plume(&g, b, x: mx + len, y: my, u: u, t0: t0, H: H, rot: rot)
}

/// Smoke off a cigarette, steam off a cup: five squares rising, spreading and fading. `rot` turns
/// the column back to world-up for a pose that has the body over.
private func plume(_ g: inout Pen, _ b: Body, x: Double, y: Double, u: Double, t0: Double, H: Double,
                   rate: Double = 3.4, spread: Double? = nil, rot: Double = 0) {
    let t = max(2, b.thick * 0.34)
    g.save()
    if rot != 0 { g.translate(x, y); g.rotate(-rot); g.translate(-x, -y) }
    for j in 0..<5 {
        let p = ((u - t0) * rate + Double(j) * 0.2).truncatingRemainder(dividingBy: 1)
        if p < 0 { continue }
        let d = t * (1.1 + p * 2.2)
        g.globalAlpha = (1 - p) * 0.5
        g.fillStyle = g.C.ink
        let s = (spread ?? 0) != 0 ? spread! : b.hr * 0.5
        g.fillRect(x + sin(p * 4 + Double(j)) * s - d / 2, y - p * H * 0.30 - d / 2, d, d)
    }
    g.globalAlpha = 1
    g.restore()
}
