import SwiftUI

// MARK: - Karaktärer

/// Gänget (former) och djuren. Alla ritas med kod i en 100×100-yta, i valfri stil.
enum Skin: String, CaseIterable, Identifiable {
    case pim, oda, bo, kix          // gänget
    case fia, misse, hubbe, pingo   // djuren: räv, katt, uggla, pingvin
    var id: String { rawValue }

    static let gang: [Skin] = [.pim, .oda, .bo, .kix]
    static let animals: [Skin] = [.fia, .misse, .hubbe, .pingo]
    var isAnimal: Bool { Skin.animals.contains(self) }

    /// Bara namnet: "Pim", "Fia", …
    var name: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }

    var displayName: String {
        switch self {
        case .pim:   "Pim – mintgrön pebble"
        case .oda:   "Oda – korallröd droppe"
        case .bo:    "Bo – lavendelböna med antenn"
        case .kix:   "Kix – solgul blomma"
        case .fia:   "Fia – räv"
        case .misse: "Misse – katt"
        case .hubbe: "Hubbe – uggla"
        case .pingo: "Pingo – pingvin"
        }
    }

    var body: Color {
        switch self {
        case .pim:   Color(hex: 0x5ED6A8)
        case .oda:   Color(hex: 0xFF7A6B)
        case .bo:    Color(hex: 0xA88CFF)
        case .kix:   Color(hex: 0xFFC73D)
        case .fia:   Color(hex: 0xFF8A3D)
        case .misse: Color(hex: 0x8FA3BF)
        case .hubbe: Color(hex: 0x6FC2B0)
        case .pingo: Color(hex: 0x4A5A8F)
        }
    }
    var shade: Color {
        switch self {
        case .pim:   Color(hex: 0x2EA37A)
        case .oda:   Color(hex: 0xDB4D45)
        case .bo:    Color(hex: 0x7559DB)
        case .kix:   Color(hex: 0xED941A)
        case .fia:   Color(hex: 0xD9601A)
        case .misse: Color(hex: 0x5E7190)
        case .hubbe: Color(hex: 0x3F8F7E)
        case .pingo: Color(hex: 0x283158)
        }
    }
    /// LED-färgen i visiret
    var led: Color {
        switch self {
        case .pim:   Color(hex: 0x7DFFC9)
        case .oda:   Color(hex: 0xFFB3A8)
        case .bo:    Color(hex: 0xC9B8FF)
        case .kix:   Color(hex: 0xFFE58A)
        case .fia:   Color(hex: 0xFFD2A6)
        case .misse: Color(hex: 0xBFE3FF)
        case .hubbe: Color(hex: 0xB8FFF0)
        case .pingo: Color(hex: 0xA9C4FF)
        }
    }
    /// Neonfärgen: lite ljusare för mörka karaktärer så att glöden syns
    var neon: Color { self == .pingo ? Color(hex: 0x8FA6FF) : body }
    var ink: Color { Color(hex: 0x1F1A29) }
    var cheek: Color { Color(hex: 0xFF8C9E).opacity(self == .oda ? 0.9 : 0.55) }

    /// Kroppens form
    func shape() -> Path {
        var p = Path()
        switch self {
        case .pim:
            p.addRoundedRect(in: CGRect(x: 12, y: 24, width: 76, height: 66), cornerSize: CGSize(width: 30, height: 30), style: .continuous)
        case .oda:
            p.move(to: CGPoint(x: 50, y: 8))
            p.addCurve(to: CGPoint(x: 86, y: 60), control1: CGPoint(x: 60, y: 26), control2: CGPoint(x: 86, y: 38))
            p.addArc(center: CGPoint(x: 50, y: 60), radius: 36, startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
            p.addCurve(to: CGPoint(x: 50, y: 8), control1: CGPoint(x: 14, y: 38), control2: CGPoint(x: 40, y: 26))
        case .bo:
            p.addRoundedRect(in: CGRect(x: 6, y: 34, width: 88, height: 54), cornerSize: CGSize(width: 27, height: 27), style: .continuous)
        case .kix:
            for i in 0..<8 {
                let a = Double(i) / 8 * 2 * .pi
                let c = CGPoint(x: 50 + cos(a) * 30, y: 56 + sin(a) * 30)
                p.addEllipse(in: CGRect(x: c.x - 15, y: c.y - 15, width: 30, height: 30))
            }
            p.addEllipse(in: CGRect(x: 18, y: 24, width: 64, height: 64))
        case .fia:
            p.addRoundedRect(in: CGRect(x: 16, y: 30, width: 68, height: 60), cornerSize: CGSize(width: 28, height: 28), style: .continuous)
        case .misse:
            p.addRoundedRect(in: CGRect(x: 16, y: 32, width: 68, height: 58), cornerSize: CGSize(width: 28, height: 28), style: .continuous)
        case .hubbe:
            p.addEllipse(in: CGRect(x: 18, y: 22, width: 64, height: 72))
        case .pingo:
            p.addRoundedRect(in: CGRect(x: 20, y: 20, width: 60, height: 72), cornerSize: CGSize(width: 30, height: 30), style: .continuous)
        }
        return p
    }

    /// Ytterkonturen (för neon). Kix blomma blir en sammanhängande solkontur.
    func outline() -> Path {
        guard self == .kix else { return shape() }
        var p = Path()
        for i in 0...240 {
            let a = Double(i) / 240 * 2 * .pi
            let r = 36 + 7 * cos(8 * a)
            let pt = CGPoint(x: 50 + r * cos(a), y: 56 + r * sin(a))
            i == 0 ? p.move(to: pt) : p.addLine(to: pt)
        }
        p.closeSubpath()
        return p
    }

    /// Var ögonen sitter (vänster, höger) och mun
    var eyes: (CGPoint, CGPoint) {
        switch self {
        case .pim:   (CGPoint(x: 37, y: 54), CGPoint(x: 63, y: 54))
        case .oda:   (CGPoint(x: 38, y: 58), CGPoint(x: 62, y: 58))
        case .bo:    (CGPoint(x: 34, y: 58), CGPoint(x: 66, y: 58))
        case .kix:   (CGPoint(x: 39, y: 54), CGPoint(x: 61, y: 54))
        case .fia:   (CGPoint(x: 38, y: 55), CGPoint(x: 62, y: 55))
        case .misse: (CGPoint(x: 38, y: 57), CGPoint(x: 62, y: 57))
        case .hubbe: (CGPoint(x: 37, y: 50), CGPoint(x: 63, y: 50))
        case .pingo: (CGPoint(x: 41, y: 49), CGPoint(x: 59, y: 49))
        }
    }
    var mouth: CGPoint {
        switch self {
        case .pim:   CGPoint(x: 50, y: 69)
        case .oda:   CGPoint(x: 50, y: 74)
        case .bo:    CGPoint(x: 50, y: 72)
        case .kix:   CGPoint(x: 50, y: 68)
        case .fia:   CGPoint(x: 50, y: 77)
        case .misse: CGPoint(x: 50, y: 72)
        case .hubbe: CGPoint(x: 50, y: 74)
        case .pingo: CGPoint(x: 50, y: 69)
        }
    }
}

/// Utseende som gäller alla karaktärer
enum MascotStyle: String, CaseIterable {
    case visor, neon, classic
    var displayName: String {
        switch self {
        case .visor: "Visir"
        case .neon: "Neon"
        case .classic: "Klassisk"
        }
    }
}

/// Humöret över dagen. Påverkar mest hur maskoten ser ut när den vilar.
enum Mood: String {
    case normal
    case sleepy     // tidig morgon och sen kväll: tunga ögonlock, gäspar, zzz
    case proud      // många uppgifter klara på kort tid: gnistrar
    case stressed   // användningen nära gränsen: svettdroppe, rör sig fortare
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

// MARK: - Vyn

/// Animerad maskot. `level` = röst/mikrofonnivå 0–1.
struct MascotView: View {
    let skin: Skin
    let state: MascotState
    var level: Float = 0
    var mood: Mood = .normal
    var style: MascotStyle = .visor

    private var calm: Bool { state == .idle || state == .done }
    /// Gäspar ca 1,6 s var 14:e sekund (bara sömnig och i vila)
    private func yawning(_ t: Double) -> Bool {
        mood == .sleepy && state == .idle && t.truncatingRemainder(dividingBy: 14) < 1.6
    }
    private func blinking(_ t: Double) -> Bool {
        let every = mood == .sleepy ? 2.8 : 4.2
        return (t.truncatingRemainder(dividingBy: every) < (mood == .sleepy ? 0.3 : 0.12) && state != .done) || yawning(t)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                let s = min(size.width, size.height) / 100
                ctx.translateBy(x: (size.width - 100 * s) / 2, y: (size.height - 100 * s) / 2)
                ctx.scaleBy(x: s, y: s)
                draw(ctx: &ctx, t: t)
            }
        }
    }

    private func draw(ctx: inout GraphicsContext, t: Double) {
        // Rörelse per tillstånd
        var bob = 0.0, squash = 1.0, tilt = 0.0
        let pace = mood == .stressed ? 1.8 : (mood == .sleepy ? 0.6 : 1.0)
        switch state {
        case .idle:          squash = 1 + 0.025 * sin(t * 2.0 * pace) + (yawning(t) ? 0.05 : 0)
        case .thinking:      bob = 2 * sin(t * 2.5)
        case .working:       bob = 2.5 * abs(sin(t * 6)); squash = 1 + 0.03 * sin(t * 12)
        case .needsApproval: bob = -6 * abs(sin(t * 5)); squash = 1 + 0.06 * sin(t * 10)
        case .done:          bob = -8 * max(0, sin(t * 4)); squash = 1 + 0.05 * sin(t * 8)
        case .listening:     tilt = 8; squash = 1 + Double(level) * 0.06
        case .speaking:      squash = 1 + Double(level) * 0.05
        case .error:         tilt = 4 * sin(t * 20)
        }

        if state == .listening {
            let r = 44 + Double(level) * 8
            ctx.stroke(Path(ellipseIn: CGRect(x: 50 - r, y: 56 - r, width: 2 * r, height: 2 * r)),
                       with: .color(skin.body.opacity(0.5)), lineWidth: 3)
        }

        ctx.translateBy(x: 50, y: 90 + bob)
        ctx.rotate(by: .degrees(tilt))
        ctx.scaleBy(x: 1 / squash, y: squash)
        ctx.translateBy(x: -50, y: -90)

        drawBack(&ctx, t: t)
        drawBody(&ctx)
        drawFeatures(&ctx)
        drawFront(&ctx, t: t)
        switch style {
        case .classic: drawFaceClassic(&ctx, t: t)
        case .visor:   drawFaceVisor(&ctx, t: t)
        case .neon:    drawFaceNeon(&ctx, t: t)
        }
        drawMood(&ctx, t: t)

        if state == .needsApproval {
            ctx.fill(Path(ellipseIn: CGRect(x: 76, y: 10, width: 20, height: 20)), with: .color(Color(hex: 0xE5484D)))
            ctx.fill(Path(roundedRect: CGRect(x: 84.5, y: 13.5, width: 3, height: 8), cornerRadius: 1.5), with: .color(.white))
            ctx.fill(Path(ellipseIn: CGRect(x: 84.5, y: 23.5, width: 3, height: 3)), with: .color(.white))
        }
    }

    // MARK: Hjälp för stilarna

    /// Fyll en form i karaktärens stil (neon: mörk fyllning + glödande kontur)
    private func paint(_ ctx: inout GraphicsContext, _ p: Path, fill: Color, glow: Color? = nil, width: CGFloat = 1.6) {
        if style == .neon {
            ctx.fill(p, with: .color(Color(hex: 0x15141B)))
            let c = glow ?? skin.neon
            ctx.stroke(p, with: .color(c.opacity(0.25)), style: StrokeStyle(lineWidth: width + 3, lineJoin: .round))
            ctx.stroke(p, with: .color(c), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
        } else {
            ctx.fill(p, with: .color(fill))
        }
    }

    /// Glödande linje (neon) i flera lager
    private func glowStroke(_ ctx: inout GraphicsContext, _ p: Path, _ c: Color, _ w: CGFloat) {
        for (ww, op) in [(w + 8, 0.08), (w + 4, 0.16), (w + 1.5, 0.35)] {
            ctx.stroke(p, with: .color(c.opacity(op)), style: StrokeStyle(lineWidth: ww, lineCap: .round, lineJoin: .round))
        }
        ctx.stroke(p, with: .color(c), style: StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round))
    }

    private func tri(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> Path {
        var p = Path(); p.move(to: a); p.addLine(to: b); p.addLine(to: c); p.closeSubpath(); return p
    }

    // MARK: Kropp

    private func drawBody(_ ctx: inout GraphicsContext) {
        let body = skin.shape()
        switch style {
        case .classic:
            ctx.fill(body, with: .linearGradient(Gradient(colors: [skin.body, skin.shade]),
                                                 startPoint: CGPoint(x: 30, y: 20), endPoint: CGPoint(x: 70, y: 95)))
            ctx.fill(Path(ellipseIn: CGRect(x: 26, y: 32, width: 18, height: 9)), with: .color(.white.opacity(0.35)))
        case .visor:
            ctx.fill(body, with: .linearGradient(Gradient(stops: [
                .init(color: skin.body, location: 0), .init(color: skin.shade, location: 0.65),
                .init(color: Color(hex: 0x1B1A22), location: 1)]),
                startPoint: CGPoint(x: 32, y: 18), endPoint: CGPoint(x: 66, y: 98)))
            ctx.fill(Path(ellipseIn: CGRect(x: 26, y: 30.5, width: 20, height: 9)), with: .color(.white.opacity(0.45)))
            ctx.fill(Path(ellipseIn: CGRect(x: 41.8, y: 29.6, width: 4.4, height: 2.8)), with: .color(.white.opacity(0.7)))
        case .neon:
            ctx.fill(body, with: .linearGradient(Gradient(colors: [Color(hex: 0x22202B), Color(hex: 0x0C0B10)]),
                                                 startPoint: CGPoint(x: 30, y: 20), endPoint: CGPoint(x: 70, y: 95)))
            ctx.fill(body, with: .radialGradient(Gradient(colors: [skin.neon.opacity(0.22), skin.neon.opacity(0)]),
                                                 center: CGPoint(x: 50, y: 40), startRadius: 0, endRadius: 45))
            glowStroke(&ctx, skin.outline(), skin.neon, 2.2)
        }
    }

    // MARK: Bakom kroppen: antenn, öron, tofsar, fötter

    private func drawBack(_ ctx: inout GraphicsContext, t: Double) {
        switch skin {
        case .bo:
            var stem = Path()
            stem.move(to: CGPoint(x: 50, y: 35))
            stem.addQuadCurve(to: CGPoint(x: 56, y: 16), control: CGPoint(x: 50, y: 22))
            let busy = state == .working || state == .thinking
            switch style {
            case .classic:
                ctx.stroke(stem, with: .color(skin.shade), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                ctx.fill(Path(ellipseIn: CGRect(x: 51, y: 9, width: 11, height: 11)),
                         with: .color(Color(hex: 0xFFD966).opacity(busy ? 0.6 + 0.4 * sin(t * 6) : 1)))
            case .visor:
                ctx.stroke(stem, with: .color(Color(hex: 0x2A2833)), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                let a = busy ? 0.6 + 0.4 * sin(t * 6) : 1
                ctx.fill(Path(ellipseIn: CGRect(x: 48.5, y: 5.5, width: 16, height: 16)), with: .color(Color(hex: 0x7CF2FF).opacity(0.2 * a)))
                ctx.fill(Path(ellipseIn: CGRect(x: 52.3, y: 9.3, width: 8.4, height: 8.4)), with: .color(Color(hex: 0x7CF2FF).opacity(a)))
                var arc = Path()
                arc.addArc(center: CGPoint(x: 57.5, y: 15), radius: 9, startAngle: .degrees(-150), endAngle: .degrees(-30), clockwise: false)
                ctx.stroke(arc, with: .color(Color(hex: 0x7CF2FF).opacity(0.7 * a)), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
            case .neon:
                ctx.stroke(stem, with: .color(skin.neon), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
                ctx.fill(Path(ellipseIn: CGRect(x: 47.5, y: 4.5, width: 18, height: 18)), with: .color(skin.neon.opacity(0.18)))
                ctx.fill(Path(ellipseIn: CGRect(x: 52, y: 9, width: 9, height: 9)), with: .color(.white))
                ctx.fill(Path(ellipseIn: CGRect(x: 52, y: 9, width: 9, height: 9)), with: .color(skin.neon.opacity(busy ? 0.3 + 0.4 * sin(t * 6) : 0.55)))
            }
        case .fia:
            let inner = Color(hex: 0xFFD9BD)
            for flip in [false, true] {
                let m: (CGFloat) -> CGFloat = { flip ? 100 - $0 : $0 }
                paint(&ctx, tri(CGPoint(x: m(20), y: 42), CGPoint(x: m(25), y: 11), CGPoint(x: m(46), y: 31)), fill: skin.body)
                if style != .neon {
                    ctx.fill(tri(CGPoint(x: m(26), y: 34), CGPoint(x: m(28), y: 19), CGPoint(x: m(39), y: 30)), with: .color(inner))
                }
            }
        case .misse:
            let inner = Color(hex: 0xF4B6C8)
            for flip in [false, true] {
                let m: (CGFloat) -> CGFloat = { flip ? 100 - $0 : $0 }
                paint(&ctx, tri(CGPoint(x: m(19), y: 46), CGPoint(x: m(21), y: 13), CGPoint(x: m(44), y: 35)), fill: skin.body)
                if style != .neon {
                    ctx.fill(tri(CGPoint(x: m(24), y: 38), CGPoint(x: m(25), y: 22), CGPoint(x: m(36), y: 33)), with: .color(inner))
                }
            }
        case .hubbe:
            for flip in [false, true] {
                let m: (CGFloat) -> CGFloat = { flip ? 100 - $0 : $0 }
                paint(&ctx, tri(CGPoint(x: m(25), y: 33), CGPoint(x: m(21), y: 11), CGPoint(x: m(40), y: 25)), fill: skin.shade)
            }
        case .pingo:
            let feet = Color(hex: 0xFFB547)
            for x in [33.0, 53.0] {
                paint(&ctx, Path(ellipseIn: CGRect(x: x, y: 87, width: 14, height: 7)), fill: feet, glow: feet)
            }
        default:
            break
        }
    }

    // MARK: På kroppen: nos, mule, mage, morrhår, näbb

    private func drawFeatures(_ ctx: inout GraphicsContext) {
        switch skin {
        case .fia:
            paint(&ctx, Path(ellipseIn: CGRect(x: 32, y: 62, width: 36, height: 24)), fill: Color(hex: 0xFFF1E6))
            ctx.fill(Path(ellipseIn: CGRect(x: 46.5, y: 64.5, width: 7, height: 5)),
                     with: .color(style == .neon ? skin.neon : skin.ink))
        case .misse:
            let c = style == .neon ? skin.neon : Color(hex: 0x1F1A29).opacity(0.55)
            for flip in [false, true] {
                let m: (CGFloat) -> CGFloat = { flip ? 100 - $0 : $0 }
                var w = Path()
                w.move(to: CGPoint(x: m(31), y: 66)); w.addLine(to: CGPoint(x: m(15), y: 63))
                w.move(to: CGPoint(x: m(31), y: 69)); w.addLine(to: CGPoint(x: m(15), y: 70))
                ctx.stroke(w, with: .color(c), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
            }
            ctx.fill(tri(CGPoint(x: 47, y: 64), CGPoint(x: 53, y: 64), CGPoint(x: 50, y: 67.5)),
                     with: .color(style == .neon ? skin.neon : Color(hex: 0xE88AA6)))
        case .hubbe:
            if style == .classic {
                for e in [skin.eyes.0, skin.eyes.1] {
                    ctx.fill(Path(ellipseIn: CGRect(x: e.x - 12, y: e.y - 12, width: 24, height: 24)), with: .color(Color(hex: 0xEAFBF6)))
                }
            }
            if style != .neon {
                ctx.fill(Path(ellipseIn: CGRect(x: 32, y: 64, width: 36, height: 26)), with: .color(.white.opacity(0.22)))
            } else {
                for e in [skin.eyes.0, skin.eyes.1] {
                    ctx.stroke(Path(ellipseIn: CGRect(x: e.x - 11, y: e.y - 11, width: 22, height: 22)),
                               with: .color(skin.neon.opacity(0.6)), lineWidth: 1.2)
                }
            }
            paint(&ctx, tri(CGPoint(x: 45.5, y: 59), CGPoint(x: 54.5, y: 59), CGPoint(x: 50, y: 67)),
                  fill: Color(hex: 0xFFB547), glow: Color(hex: 0xFFB547), width: 1.3)
        case .pingo:
            paint(&ctx, Path(ellipseIn: CGRect(x: 29, y: 34, width: 42, height: 56)), fill: Color(hex: 0xF4F2EE), glow: skin.neon.opacity(0.7), width: 1.2)
            paint(&ctx, tri(CGPoint(x: 45.5, y: 56), CGPoint(x: 54.5, y: 56), CGPoint(x: 50, y: 62)),
                  fill: Color(hex: 0xFFB547), glow: Color(hex: 0xFFB547), width: 1.3)
        default:
            break
        }
    }

    // MARK: Framför: skott, lock/flamma, stjärna

    private func drawFront(_ ctx: inout GraphicsContext, t: Double) {
        switch skin {
        case .pim:
            let sway = state == .working ? 8 * sin(t * 6) : 3 * sin(t * 1.5)
            var stem = Path()
            stem.move(to: CGPoint(x: 50, y: 26))
            stem.addLine(to: CGPoint(x: 50 + sway * 0.2, y: 15))
            let base = CGPoint(x: 50 + sway * 0.2, y: 16)
            switch style {
            case .visor:
                ctx.stroke(stem, with: .color(Color(hex: 0x1B1A22)), style: StrokeStyle(lineWidth: 2.6, lineCap: .round))
                var bolt = Path()
                let pts: [(CGFloat, CGFloat)] = [(-1, 1), (8, -12), (6, -5), (14, -7), (3, 6), (5, -1)]
                for (i, p) in pts.enumerated() {
                    let q = CGPoint(x: base.x + p.0, y: base.y + p.1)
                    i == 0 ? bolt.move(to: q) : bolt.addLine(to: q)
                }
                bolt.closeSubpath()
                ctx.fill(bolt, with: .color(Color(hex: 0xC8F55A)))
                ctx.stroke(bolt, with: .color(Color(hex: 0x1B1A22)), style: StrokeStyle(lineWidth: 1.2, lineJoin: .round))
            default:
                var leaf = Path()
                leaf.move(to: base)
                leaf.addQuadCurve(to: CGPoint(x: base.x + 14, y: base.y - 8), control: CGPoint(x: base.x + 4, y: base.y - 12))
                leaf.addQuadCurve(to: base, control: CGPoint(x: base.x + 12, y: base.y + 2))
                if style == .neon {
                    ctx.stroke(stem, with: .color(skin.neon), style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                    glowStroke(&ctx, leaf, Color(hex: 0xB6F27A), 1.6)
                } else {
                    ctx.stroke(stem, with: .color(skin.shade), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    ctx.fill(leaf, with: .color(Color(hex: 0x73C759)))
                }
            }
        case .oda:
            if style == .visor {
                let flick = 1 + 0.06 * sin(t * 9)
                var f = Path()
                f.move(to: CGPoint(x: 50, y: 1 + (1 - flick) * 10))
                f.addCurve(to: CGPoint(x: 46, y: 20), control1: CGPoint(x: 45, y: 8), control2: CGPoint(x: 43, y: 13))
                f.addCurve(to: CGPoint(x: 51, y: 8), control1: CGPoint(x: 47, y: 15), control2: CGPoint(x: 51, y: 13))
                f.addCurve(to: CGPoint(x: 53, y: 21), control1: CGPoint(x: 55, y: 12), control2: CGPoint(x: 56, y: 16))
                f.addCurve(to: CGPoint(x: 50, y: 1 + (1 - flick) * 10), control1: CGPoint(x: 59, y: 17), control2: CGPoint(x: 59, y: 9))
                ctx.fill(f, with: .color(Color(hex: 0xFFB547)))
                var core = Path()
                core.move(to: CGPoint(x: 50, y: 9))
                core.addCurve(to: CGPoint(x: 50, y: 20.5), control1: CGPoint(x: 47.5, y: 13), control2: CGPoint(x: 47.5, y: 17))
                core.addCurve(to: CGPoint(x: 50, y: 9), control1: CGPoint(x: 52.5, y: 17), control2: CGPoint(x: 52.5, y: 13))
                ctx.fill(core, with: .color(Color(hex: 0xFFF0B3)))
            } else {
                var curl = Path()
                curl.addArc(center: CGPoint(x: 55, y: 8), radius: 5, startAngle: .degrees(180), endAngle: .degrees(60), clockwise: false)
                if style == .neon { glowStroke(&ctx, curl, skin.neon, 2) }
                else { ctx.stroke(curl, with: .color(skin.shade), style: StrokeStyle(lineWidth: 2.5, lineCap: .round)) }
            }
        case .kix where style == .visor:
            var star = Path()
            for i in 0..<10 {
                let a = Double(i) / 10 * 2 * .pi - .pi / 2
                let r: Double = i % 2 == 0 ? 5 : 2.2
                let pt = CGPoint(x: 75 + r * cos(a), y: 27 + r * sin(a))
                i == 0 ? star.move(to: pt) : star.addLine(to: pt)
            }
            star.closeSubpath()
            ctx.fill(star, with: .color(.white.opacity(0.4 + 0.5 * max(0, sin(t * 2)))))
        default:
            break
        }
    }

    // MARK: Ansikten

    /// Gemensam mun (klassisk och visir); neon ritar sin egen
    private func drawMouth(_ ctx: inout GraphicsContext, t: Double, color: Color, smirk: Bool) {
        let m = skin.mouth
        if state == .speaking || (state == .listening && level > 0.05) {
            let h = 2 + CGFloat(level) * 9
            ctx.fill(Path(ellipseIn: CGRect(x: m.x - 4.5, y: m.y - h / 2, width: 9, height: h)), with: .color(color))
        } else if state == .needsApproval {
            ctx.fill(Path(ellipseIn: CGRect(x: m.x - 3, y: m.y - 3, width: 6, height: 6)), with: .color(color))
        } else if yawning(t) {
            ctx.fill(Path(ellipseIn: CGRect(x: m.x - 4, y: m.y - 4, width: 8, height: 10)), with: .color(color))
        } else if mood == .stressed && calm {
            var p = Path()
            p.move(to: CGPoint(x: m.x - 5, y: m.y))
            p.addQuadCurve(to: CGPoint(x: m.x + 5, y: m.y - 2), control: CGPoint(x: m.x + 1, y: m.y + 1.5))
            ctx.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
        } else if smirk && state != .done && !(mood == .proud && calm) {
            var p = Path()
            p.move(to: CGPoint(x: m.x - 4, y: m.y + 1))
            p.addQuadCurve(to: CGPoint(x: m.x + 5, y: m.y - 1), control: CGPoint(x: m.x + 1, y: m.y + 4))
            ctx.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: 2.4, lineCap: .round))
        } else {
            let smile: CGFloat = state == .done || (mood == .proud && calm) ? 6 : 3.5
            var p = Path()
            p.move(to: CGPoint(x: m.x - 5, y: m.y - 1))
            p.addQuadCurve(to: CGPoint(x: m.x + 5, y: m.y - 1), control: CGPoint(x: m.x, y: m.y - 1 + smile))
            ctx.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
        }
    }

    private var look: CGSize {
        switch state {
        case .thinking: CGSize(width: 2.5, height: -3)
        case .working:  CGSize(width: 0, height: 1)
        default: .zero
        }
    }

    private func drawFaceClassic(_ ctx: inout GraphicsContext, t: Double) {
        let (l, r) = skin.eyes
        let blink = blinking(t)
        var lk = look
        if state == .working { lk.width = 3 * sin(t * 1.5) }
        let wide: CGFloat = (state == .needsApproval || state == .listening) ? 1.25 : 1
        let lidColor = skin == .hubbe ? Color(hex: 0xEAFBF6) : skin == .pingo ? Color(hex: 0xF4F2EE) : skin.body

        for e in [l, r] {
            let c = CGPoint(x: e.x + lk.width, y: e.y + lk.height)
            if state == .done {
                var p = Path()
                p.move(to: CGPoint(x: c.x - 5, y: c.y + 2))
                p.addQuadCurve(to: CGPoint(x: c.x + 5, y: c.y + 2), control: CGPoint(x: c.x, y: c.y - 6))
                ctx.stroke(p, with: .color(skin.ink), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                continue
            }
            if blink {
                var p = Path()
                p.move(to: CGPoint(x: c.x - 4.5, y: c.y)); p.addLine(to: CGPoint(x: c.x + 4.5, y: c.y))
                ctx.stroke(p, with: .color(skin.ink), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                continue
            }
            let (w, h): (CGFloat, CGFloat) = skin == .oda ? (8 * wide, 11 * wide) : (8.5 * wide, 8.5 * wide)
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - w / 2, y: c.y - h / 2, width: w, height: h)), with: .color(skin.ink))
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - w / 2 + 1.5, y: c.y - h / 2 + 1.2, width: 3, height: 3)), with: .color(.white))
            if state == .idle && (skin == .bo || mood == .sleepy) {
                ctx.fill(Path(CGRect(x: c.x - w / 2 - 1, y: c.y - h / 2 - 1, width: w + 2, height: h / 2 + 0.5)), with: .color(lidColor))
            }
        }
        if skin != .hubbe {
            for e in [l, r] {
                let dx: CGFloat = e.x < 50 ? -8 : 8
                ctx.fill(Path(ellipseIn: CGRect(x: e.x + dx - 5, y: e.y + 7, width: 10, height: 5)), with: .color(skin.cheek))
            }
        }
        if skin == .kix {
            for (x, y) in [(33.0, 60.0), (36.0, 63.0), (64.0, 60.0), (67.0, 63.0)] {
                ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1.8, height: 1.8)), with: .color(skin.shade))
            }
        }
        drawMouth(&ctx, t: t, color: skin.ink, smirk: false)
    }

    private func drawFaceVisor(_ ctx: inout GraphicsContext, t: Double) {
        let (l, r) = skin.eyes
        // Visiret
        let band = CGRect(x: l.x - 12, y: l.y - 8, width: (r.x - l.x) + 24, height: 16)
        let visor = Path(roundedRect: band, cornerRadius: 8)
        ctx.fill(visor, with: .linearGradient(Gradient(colors: [Color(hex: 0x2A2833), Color(hex: 0x0B0A0F)]),
                                              startPoint: CGPoint(x: band.midX, y: band.minY), endPoint: CGPoint(x: band.midX, y: band.maxY)))
        ctx.fill(Path(roundedRect: CGRect(x: band.minX + 3, y: band.minY + 2, width: band.width - 6, height: 2.2), cornerRadius: 1.1),
                 with: .color(.white.opacity(0.18)))

        // LED-ögon
        var led = skin.led
        if state == .needsApproval { led = Color(hex: 0xFF8A8A) }
        let blink = blinking(t)
        let sleepy = mood == .sleepy && state == .idle
        var dx: CGFloat = 0
        if state == .working { dx = 3 * sin(t * 1.5) }
        if state == .thinking { dx = 2.5 }
        for e in [l, r] {
            let c = CGPoint(x: e.x + dx, y: e.y + (state == .thinking ? -1 : 0))
            if state == .done {
                var p = Path()
                p.move(to: CGPoint(x: c.x - 4.5, y: c.y + 1.5))
                p.addQuadCurve(to: CGPoint(x: c.x + 4.5, y: c.y + 1.5), control: CGPoint(x: c.x, y: c.y - 4.5))
                glowStroke(&ctx, p, led, 2)
                continue
            }
            let big = state == .needsApproval || state == .listening
            let w: CGFloat = big ? 10 : 8
            let h: CGFloat = blink ? 1.4 : (sleepy ? 2.4 : (big ? 7 : 5))
            let rect = CGRect(x: c.x - w / 2, y: c.y - h / 2, width: w, height: h)
            ctx.fill(Path(roundedRect: rect.insetBy(dx: -3, dy: -3), cornerRadius: (min(w, h) + 6) / 2), with: .color(led.opacity(0.18)))
            ctx.fill(Path(roundedRect: rect, cornerRadius: min(w, h) / 2), with: .color(led))
        }
        drawMouth(&ctx, t: t, color: Color(hex: 0x1B1A22), smirk: true)
    }

    private func drawFaceNeon(_ ctx: inout GraphicsContext, t: Double) {
        let (l, r) = skin.eyes
        let c0 = skin.neon
        let blink = blinking(t)
        var dx: CGFloat = 0
        if state == .working { dx = 3 * sin(t * 1.5) }
        if state == .thinking { dx = 2.5 }
        for e in [l, r] {
            let c = CGPoint(x: e.x + dx, y: e.y + (state == .thinking ? -2 : 0))
            if state == .done {
                var p = Path()
                p.move(to: CGPoint(x: c.x - 5, y: c.y + 2))
                p.addQuadCurve(to: CGPoint(x: c.x + 5, y: c.y + 2), control: CGPoint(x: c.x, y: c.y - 6))
                glowStroke(&ctx, p, c0, 2.6)
                continue
            }
            let big = state == .needsApproval || state == .listening
            let w: CGFloat = big ? 8 : 6.5
            let tall: CGFloat = skin == .oda ? 11 : 9.5
            let h: CGFloat = blink ? 1.6 : ((mood == .sleepy && state == .idle) ? tall * 0.45 : (big ? tall * 1.2 : tall))
            let rect = CGRect(x: c.x - w / 2, y: c.y - h / 2, width: w, height: h)
            ctx.fill(Path(roundedRect: rect.insetBy(dx: -3, dy: -3), cornerRadius: (min(w, h) + 6) / 2), with: .color(c0.opacity(0.18)))
            ctx.fill(Path(roundedRect: rect, cornerRadius: min(w, h) / 2), with: .color(c0))
        }
        // Mun som glödande linje
        let m = skin.mouth
        var p = Path()
        if state == .speaking || (state == .listening && level > 0.05) {
            let h = 2 + CGFloat(level) * 9
            p.addEllipse(in: CGRect(x: m.x - 4.5, y: m.y - h / 2, width: 9, height: h))
        } else if state == .needsApproval || yawning(t) {
            p.addEllipse(in: CGRect(x: m.x - 3, y: m.y - 3, width: 6, height: 6))
        } else {
            let smile: CGFloat = state == .done || (mood == .proud && calm) ? 6 : (mood == .stressed ? 0.5 : 4)
            p.move(to: CGPoint(x: m.x - 5, y: m.y - 1))
            p.addQuadCurve(to: CGPoint(x: m.x + 5, y: m.y - 1), control: CGPoint(x: m.x, y: m.y - 1 + smile))
        }
        glowStroke(&ctx, p, c0, 2)
    }

    // MARK: Humör

    private func drawMood(_ ctx: inout GraphicsContext, t: Double) {
        switch mood {
        case .sleepy where state == .idle:
            for i in 0..<2 {
                let phase = (t * 0.5 + Double(i) * 0.5).truncatingRemainder(dividingBy: 1)
                let size = 9 + phase * 6
                ctx.opacity = 1 - phase
                ctx.draw(Text("z").font(.system(size: size, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.85)),
                         at: CGPoint(x: 84 + phase * 8, y: 26 - phase * 18))
            }
            ctx.opacity = 1
        case .stressed:
            let y = 34 + (t * 12).truncatingRemainder(dividingBy: 14)
            var d = Path()
            d.move(to: CGPoint(x: 80, y: y - 7))
            d.addQuadCurve(to: CGPoint(x: 80, y: y + 4), control: CGPoint(x: 87, y: y + 2))
            d.addQuadCurve(to: CGPoint(x: 80, y: y - 7), control: CGPoint(x: 73, y: y + 2))
            ctx.fill(d, with: .color(Color(hex: 0x8CCCFF).opacity(0.95)))
        case .proud where calm:
            for (i, p) in [CGPoint(x: 18, y: 22), CGPoint(x: 84, y: 30), CGPoint(x: 74, y: 10)].enumerated() {
                let a = max(0, sin(t * 3 + Double(i) * 2.1))
                guard a > 0.2 else { continue }
                let r = 2 + 3 * a
                var s = Path()
                s.move(to: CGPoint(x: p.x, y: p.y - r)); s.addLine(to: CGPoint(x: p.x, y: p.y + r))
                s.move(to: CGPoint(x: p.x - r, y: p.y)); s.addLine(to: CGPoint(x: p.x + r, y: p.y))
                ctx.stroke(s, with: .color(Color(hex: 0xFFD966).opacity(a)), style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
            }
        default:
            break
        }
    }
}
