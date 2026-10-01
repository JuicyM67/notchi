import SwiftUI

/// De fyra karaktärerna. Alla ritas med kod (ingen bildfil behövs) i en 100×100-yta.
enum Skin: String, CaseIterable, Identifiable {
    case pim, oda, bo, kix
    var id: String { rawValue }

    /// Bara namnet: "Pim", "Oda", …
    var name: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }

    var displayName: String {
        switch self {
        case .pim: "Pim – mintgrön pebble med skott"
        case .oda: "Oda – korallröd droppe"
        case .bo:  "Bo – lavendelböna med antenn"
        case .kix: "Kix – solgul blomma"
        }
    }

    var body: Color {
        switch self {
        case .pim: Color(red: 0.37, green: 0.84, blue: 0.66)
        case .oda: Color(red: 1.00, green: 0.48, blue: 0.42)
        case .bo:  Color(red: 0.66, green: 0.55, blue: 1.00)
        case .kix: Color(red: 1.00, green: 0.78, blue: 0.24)
        }
    }
    var shade: Color {
        switch self {
        case .pim: Color(red: 0.18, green: 0.64, blue: 0.48)
        case .oda: Color(red: 0.86, green: 0.30, blue: 0.27)
        case .bo:  Color(red: 0.46, green: 0.35, blue: 0.86)
        case .kix: Color(red: 0.93, green: 0.58, blue: 0.10)
        }
    }
    var ink: Color { Color(red: 0.12, green: 0.10, blue: 0.16) }
    var cheek: Color { Color(red: 1.0, green: 0.55, blue: 0.62).opacity(self == .oda ? 0.9 : 0.55) }

    /// Kroppens form
    func shape() -> Path {
        var p = Path()
        switch self {
        case .pim:
            p.addRoundedRect(in: CGRect(x: 12, y: 24, width: 76, height: 66),
                             cornerSize: CGSize(width: 30, height: 30), style: .continuous)
        case .oda:
            p.move(to: CGPoint(x: 50, y: 8))
            p.addCurve(to: CGPoint(x: 86, y: 60), control1: CGPoint(x: 60, y: 26), control2: CGPoint(x: 86, y: 38))
            p.addArc(center: CGPoint(x: 50, y: 60), radius: 36, startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
            p.addCurve(to: CGPoint(x: 50, y: 8), control1: CGPoint(x: 14, y: 38), control2: CGPoint(x: 40, y: 26))
        case .bo:
            p.addRoundedRect(in: CGRect(x: 6, y: 34, width: 88, height: 54),
                             cornerSize: CGSize(width: 27, height: 27), style: .continuous)
        case .kix:
            for i in 0..<8 {
                let a = Double(i) / 8 * 2 * .pi
                let c = CGPoint(x: 50 + cos(a) * 30, y: 56 + sin(a) * 30)
                p.addEllipse(in: CGRect(x: c.x - 15, y: c.y - 15, width: 30, height: 30))
            }
            p.addEllipse(in: CGRect(x: 18, y: 24, width: 64, height: 64))
        }
        return p
    }

    /// Var ögonen sitter (vänster, höger) och mun
    var eyes: (CGPoint, CGPoint) {
        switch self {
        case .pim: (CGPoint(x: 37, y: 54), CGPoint(x: 63, y: 54))
        case .oda: (CGPoint(x: 38, y: 58), CGPoint(x: 62, y: 58))
        case .bo:  (CGPoint(x: 34, y: 58), CGPoint(x: 66, y: 58))
        case .kix: (CGPoint(x: 39, y: 54), CGPoint(x: 61, y: 54))
        }
    }
    var mouth: CGPoint {
        switch self {
        case .pim: CGPoint(x: 50, y: 69)
        case .oda: CGPoint(x: 50, y: 74)
        case .bo:  CGPoint(x: 50, y: 72)
        case .kix: CGPoint(x: 50, y: 68)
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

/// Animerad maskot. `level` = röst/mikrofonnivå 0–1.
struct MascotView: View {
    let skin: Skin
    let state: MascotState
    var level: Float = 0
    var mood: Mood = .normal

    private var calm: Bool { state == .idle || state == .done }
    /// Gäspar ca 1,6 s var 14:e sekund (bara sömnig och i vila)
    private func yawning(_ t: Double) -> Bool {
        mood == .sleepy && state == .idle && t.truncatingRemainder(dividingBy: 14) < 1.6
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

        // Lyssnar: pulserande ring
        if state == .listening {
            let r = 44 + Double(level) * 8
            ctx.stroke(Path(ellipseIn: CGRect(x: 50 - r, y: 56 - r, width: 2 * r, height: 2 * r)),
                       with: .color(skin.body.opacity(0.5)), lineWidth: 3)
        }

        ctx.translateBy(x: 50, y: 90 + bob)
        ctx.rotate(by: .degrees(tilt))
        ctx.scaleBy(x: 1 / squash, y: squash)
        ctx.translateBy(x: -50, y: -90)

        // Tillbehör bakom kroppen
        drawAccessoryBack(&ctx, t: t)

        // Kropp med skugga + glans
        let body = skin.shape()
        ctx.fill(body, with: .linearGradient(Gradient(colors: [skin.body, skin.shade]),
                                             startPoint: CGPoint(x: 30, y: 20), endPoint: CGPoint(x: 70, y: 95)))
        ctx.fill(Path(ellipseIn: CGRect(x: 26, y: 32, width: 18, height: 9)), with: .color(.white.opacity(0.35)))

        drawAccessoryFront(&ctx, t: t)
        drawFace(&ctx, t: t)
        drawMood(&ctx, t: t)

        // Utropstecken vid godkännande
        if state == .needsApproval {
            var badge = Path(ellipseIn: CGRect(x: 76, y: 10, width: 20, height: 20))
            ctx.fill(badge, with: .color(Color(red: 1, green: 0.35, blue: 0.3)))
            badge = Path(roundedRect: CGRect(x: 84.5, y: 13.5, width: 3, height: 8), cornerRadius: 1.5)
            ctx.fill(badge, with: .color(.white))
            ctx.fill(Path(ellipseIn: CGRect(x: 84.5, y: 23.5, width: 3, height: 3)), with: .color(.white))
        }
    }

    private func drawFace(_ ctx: inout GraphicsContext, t: Double) {
        let (l, r) = skin.eyes
        // Blink ca var 4:e sekund
        let blinkEvery = mood == .sleepy ? 2.8 : 4.2
        let blink = (t.truncatingRemainder(dividingBy: blinkEvery)) < (mood == .sleepy ? 0.3 : 0.12) && state != .done
            || yawning(t)
        var look = CGSize.zero
        switch state {
        case .thinking: look = CGSize(width: 2.5, height: -3)
        case .working:  look = CGSize(width: 3 * sin(t * 1.5), height: 1)
        default: break
        }
        let wide: CGFloat = (state == .needsApproval || state == .listening) ? 1.25 : 1

        for e in [l, r] {
            let c = CGPoint(x: e.x + look.width, y: e.y + look.height)
            if state == .done {
                // Glada ^^-ögon
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
            // Bo är sömnig: tunga ögonlock
            if state == .idle && (skin == .bo || mood == .sleepy) {
                ctx.fill(Path(CGRect(x: c.x - w / 2 - 1, y: c.y - h / 2 - 1, width: w + 2, height: h / 2 + 0.5)),
                         with: .color(skin.body))
            }
        }

        // Kinder
        for e in [l, r] {
            let dx: CGFloat = e.x < 50 ? -8 : 8
            ctx.fill(Path(ellipseIn: CGRect(x: e.x + dx - 5, y: e.y + 7, width: 10, height: 5)), with: .color(skin.cheek))
        }
        // Kix har fräknar
        if skin == .kix {
            for (x, y) in [(33.0, 60.0), (36.0, 63.0), (64.0, 60.0), (67.0, 63.0)] {
                ctx.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1.8, height: 1.8)), with: .color(skin.shade))
            }
        }

        // Mun
        let m = skin.mouth
        if state == .speaking || (state == .listening && level > 0.05) {
            let h = 2 + CGFloat(level) * 9
            ctx.fill(Path(ellipseIn: CGRect(x: m.x - 4.5, y: m.y - h / 2, width: 9, height: h)), with: .color(skin.ink))
        } else if state == .needsApproval {
            ctx.fill(Path(ellipseIn: CGRect(x: m.x - 3, y: m.y - 3, width: 6, height: 6)), with: .color(skin.ink))
        } else if yawning(t) {
            ctx.fill(Path(ellipseIn: CGRect(x: m.x - 4, y: m.y - 4, width: 8, height: 10)), with: .color(skin.ink))
        } else if mood == .stressed && calm {
            // Snett, lite nervöst leende
            var p = Path()
            p.move(to: CGPoint(x: m.x - 5, y: m.y))
            p.addQuadCurve(to: CGPoint(x: m.x + 5, y: m.y - 2), control: CGPoint(x: m.x + 1, y: m.y + 1.5))
            ctx.stroke(p, with: .color(skin.ink), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
        } else {
            let smile: CGFloat = state == .done || (mood == .proud && calm) ? 6 : 3.5
            var p = Path()
            p.move(to: CGPoint(x: m.x - 5, y: m.y - 1))
            p.addQuadCurve(to: CGPoint(x: m.x + 5, y: m.y - 1), control: CGPoint(x: m.x, y: m.y - 1 + smile))
            ctx.stroke(p, with: .color(skin.ink), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
        }
    }

    private func drawMood(_ ctx: inout GraphicsContext, t: Double) {
        switch mood {
        case .sleepy where state == .idle:
            // Små z som stiger uppåt till höger
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
            // Svettdroppe som glider ner längs sidan
            let y = 34 + (t * 12).truncatingRemainder(dividingBy: 14)
            var d = Path()
            d.move(to: CGPoint(x: 80, y: y - 7))
            d.addQuadCurve(to: CGPoint(x: 80, y: y + 4), control: CGPoint(x: 87, y: y + 2))
            d.addQuadCurve(to: CGPoint(x: 80, y: y - 7), control: CGPoint(x: 73, y: y + 2))
            ctx.fill(d, with: .color(Color(red: 0.55, green: 0.80, blue: 1.0).opacity(0.95)))
        case .proud where calm:
            // Gnistor som tänds och släcks runt huvudet
            for (i, p) in [CGPoint(x: 18, y: 22), CGPoint(x: 84, y: 30), CGPoint(x: 74, y: 10)].enumerated() {
                let a = max(0, sin(t * 3 + Double(i) * 2.1))
                guard a > 0.2 else { continue }
                let r = 2 + 3 * a
                var s = Path()
                s.move(to: CGPoint(x: p.x, y: p.y - r)); s.addLine(to: CGPoint(x: p.x, y: p.y + r))
                s.move(to: CGPoint(x: p.x - r, y: p.y)); s.addLine(to: CGPoint(x: p.x + r, y: p.y))
                ctx.stroke(s, with: .color(Color(red: 1, green: 0.85, blue: 0.4).opacity(a)),
                           style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
            }
        default:
            break
        }
    }

    private func drawAccessoryBack(_ ctx: inout GraphicsContext, t: Double) {
        switch skin {
        case .bo:
            // Antenn med lysande prick
            var stem = Path()
            stem.move(to: CGPoint(x: 50, y: 35))
            stem.addQuadCurve(to: CGPoint(x: 56, y: 16), control: CGPoint(x: 50, y: 22))
            ctx.stroke(stem, with: .color(skin.shade), style: StrokeStyle(lineWidth: 3, lineCap: .round))
            let glow = state == .working || state == .thinking ? 0.6 + 0.4 * sin(t * 6) : 1
            ctx.fill(Path(ellipseIn: CGRect(x: 51, y: 9, width: 11, height: 11)),
                     with: .color(Color(red: 1, green: 0.85, blue: 0.4).opacity(glow)))
        default: break
        }
    }

    private func drawAccessoryFront(_ ctx: inout GraphicsContext, t: Double) {
        switch skin {
        case .pim:
            // Litet skott på huvudet som vajar
            let sway = state == .working ? 8 * sin(t * 6) : 3 * sin(t * 1.5)
            var stem = Path()
            stem.move(to: CGPoint(x: 50, y: 26))
            stem.addLine(to: CGPoint(x: 50 + sway * 0.2, y: 15))
            ctx.stroke(stem, with: .color(skin.shade), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            var leaf = Path()
            let base = CGPoint(x: 50 + sway * 0.2, y: 16)
            leaf.move(to: base)
            leaf.addQuadCurve(to: CGPoint(x: base.x + 14, y: base.y - 8), control: CGPoint(x: base.x + 4, y: base.y - 12))
            leaf.addQuadCurve(to: base, control: CGPoint(x: base.x + 12, y: base.y + 2))
            ctx.fill(leaf, with: .color(Color(red: 0.45, green: 0.78, blue: 0.35)))
        case .oda:
            // Liten lock i toppen
            var curl = Path()
            curl.addArc(center: CGPoint(x: 55, y: 8), radius: 5, startAngle: .degrees(180), endAngle: .degrees(60), clockwise: false)
            ctx.stroke(curl, with: .color(skin.shade), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
        default: break
        }
    }
}
