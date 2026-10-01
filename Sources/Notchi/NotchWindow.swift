import AppKit
import SwiftUI

/// Ett ramlöst fönster som ligger ovanpå allt, precis runt notchen.
final class NotchPanel: NSPanel {
    init() {
        super.init(contentRect: .zero,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        // Över menyraden (som ligger på .mainMenu), annars kan macOS lägga menyraden ovanpå oss
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isMovable = false
        hidesOnDeactivate = false
    }
    override var canBecomeKey: Bool { true }
}

struct NotchGeometry: Equatable {
    let screenFrame: NSRect
    let notchWidth: CGFloat
    let notchHeight: CGFloat

    static func current() -> NotchGeometry {
        let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main ?? NSScreen.screens[0]
        var width: CGFloat = 200
        if let l = screen.auxiliaryTopLeftArea, let r = screen.auxiliaryTopRightArea {
            width = screen.frame.width - l.width - r.width
        }
        let height = screen.safeAreaInsets.top > 0 ? screen.safeAreaInsets.top : 26   // ingen notch: menyradshöjd
        return NotchGeometry(screenFrame: screen.frame, notchWidth: width, notchHeight: height)
    }

    /// "Örat" på varje sida om den fysiska notchen (här bor maskoten till vänster)
    var ear: CGFloat { notchHeight + 4 }
    /// Statustextens typsnitt (samma som i vyn) och mått runt den på höger sida
    static let labelFont = NSFont.systemFont(ofSize: 11, weight: .semibold)
    static let rightLead: CGFloat = 10      // luft mellan notchens kant och texten
    static let dotWidth: CGFloat = 15
    static let gap: CGFloat = 6
    static let rightTrail: CGFloat = 10
    static let maxLabelRoom: CGFloat = 150

    static func textWidth(_ s: String) -> CGFloat {
        ceil((s as NSString).size(withAttributes: [.font: labelFont]).width) + 2
    }

    /// Bredd på höger sida av den fysiska notchen
    func rightWidth(label: String?) -> CGFloat {
        guard let label else { return ear }
        let need = Self.rightLead + Self.textWidth(label) + Self.gap + Self.dotWidth + Self.rightTrail
        return max(ear, min(need, ear + Self.maxLabelRoom))
    }

    /// Extra bredd till HÖGER när en statustext visas (bara på den sidan, så notchen hålls smal)
    func labelRoom(_ label: String?) -> CGFloat { rightWidth(label: label) - ear }

    var expandedSize: NSSize {
        NSSize(width: max(notchWidth + 2 * ear + 96, 380), height: notchHeight + 184)
    }

    /// Den svarta formens storlek i olika lägen
    func shapeSize(expanded: Bool, label: String?) -> NSSize {
        if expanded { return expandedSize }
        return NSSize(width: notchWidth + 2 * ear + labelRoom(label), height: notchHeight)
    }

    /// Hur långt formen förskjuts åt höger från mitten (statustexten växer bara åt höger)
    func shapeOffset(expanded: Bool, label: String?) -> CGFloat {
        expanded ? 0 : labelRoom(label) / 2
    }

    /// Fönstret har ALLTID samma storlek. Det stoppar fladdret som uppstår
    /// när ett fönster byter storlek under muspekaren.
    var canvas: NSRect {
        let collapsedHalf = notchWidth / 2 + ear + Self.maxLabelRoom
        let w = max(expandedSize.width, 2 * collapsedHalf)
        let h = expandedSize.height
        return NSRect(x: screenFrame.midX - w / 2, y: screenFrame.maxY - h, width: w, height: h)
    }

    /// Formens yta i skärmkoordinater (för att avgöra om musen är över den)
    func shapeRect(expanded: Bool, label: String?) -> NSRect {
        let s = shapeSize(expanded: expanded, label: label)
        let cx = screenFrame.midX + shapeOffset(expanded: expanded, label: label)
        return NSRect(x: cx - s.width / 2, y: screenFrame.maxY - s.height, width: s.width, height: s.height)
    }
}

/// Svart form med rundade underhörn, som smälter ihop med notchen.
struct NotchShape: Shape {
    var radius: CGFloat
    var animatableData: CGFloat { get { radius } set { radius = newValue } }
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - radius))
        p.addQuadCurve(to: CGPoint(x: r.maxX - radius, y: r.maxY), control: CGPoint(x: r.maxX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX + radius, y: r.maxY))
        p.addQuadCurve(to: CGPoint(x: r.minX, y: r.maxY - radius), control: CGPoint(x: r.minX, y: r.maxY))
        p.closeSubpath()
        return p
    }
}

struct NotchView: View {
    @ObservedObject var store: SessionStore
    @ObservedObject var voice: VoiceState
    let geometry: NotchGeometry

    var body: some View {
        let expanded = store.expanded
        let label = store.shortStatus
        let size = geometry.shapeSize(expanded: expanded, label: label)
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                NotchShape(radius: expanded ? 22 : 10)
                    .fill(Color.black)
                    .onTapGesture { store.onPoke?() }
                if expanded {
                    expandedContent
                        .padding(.top, geometry.notchHeight + 8)
                        .padding(.horizontal, 18)
                        .padding(.bottom, 12)
                        .transition(.opacity)
                } else {
                    collapsedContent(label: label)
                        .transition(.opacity)
                }
            }
            .frame(width: size.width, height: size.height)
            .contentShape(Rectangle())
            .offset(x: geometry.shapeOffset(expanded: expanded, label: label))
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: expanded)
        .animation(.spring(response: 0.3, dampingFraction: 0.9), value: label)
    }

    // MARK: Hopfälld: maskot till vänster, kort status till höger

    private func collapsedContent(label: String?) -> some View {
        HStack(spacing: 0) {
            // Vänster öra: maskoten
            MascotView(skin: store.primarySkin, state: store.state, level: voice.level, mood: store.mood)
                .frame(width: geometry.notchHeight - 2, height: geometry.notchHeight - 4)
                .frame(width: geometry.ear)
            // Den fysiska notchen: här kan inget synas
            Color.clear.frame(width: geometry.notchWidth)
            // Höger del: text och prick, alltid till höger om notchen
            HStack(spacing: NotchGeometry.gap) {
                if let label {
                    Text(label)
                        .font(Font(NotchGeometry.labelFont))
                        .foregroundStyle(statusColor)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Spacer(minLength: 0)
                statusDot
            }
            .padding(.leading, label == nil ? 0 : NotchGeometry.rightLead)
            .padding(.trailing, NotchGeometry.rightTrail)
            .frame(width: geometry.rightWidth(label: label))
        }
        .frame(height: geometry.notchHeight)
    }

    private var statusColor: Color {
        switch store.state {
        case .needsApproval: Color(red: 1, green: 0.55, blue: 0.5)
        case .working, .thinking: Color(red: 0.55, green: 0.72, blue: 1)
        case .done: Color(red: 0.37, green: 0.84, blue: 0.66)
        case .listening: Color(red: 1, green: 0.6, blue: 0.75)
        default: .white.opacity(0.75)
        }
    }

    private var statusDot: some View {
        let color: Color = switch store.state {
        case .needsApproval: Color(red: 0.898, green: 0.282, blue: 0.302)
        case .working, .thinking: Color(red: 0.231, green: 0.510, blue: 0.965)
        case .done: Color(red: 0.37, green: 0.84, blue: 0.66)
        case .listening: .pink
        default: .gray.opacity(0.5)
        }
        return ZStack {
            if let pct = store.usage.fiveHour {
                Circle().stroke(Color.white.opacity(0.15), lineWidth: 2)
                Circle().trim(from: 0, to: min(1, pct / 100))
                    .stroke(UsageMeter.color(pct), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            Circle().fill(color).frame(width: 7, height: 7)
        }
        .frame(width: NotchGeometry.dotWidth, height: NotchGeometry.dotWidth)
        .help(store.usage.fiveHour.map { "\(Int($0.rounded())) % av 5-timmarsgränsen använd" } ?? "")
    }

    // MARK: Utfälld

    @ViewBuilder
    private var expandedContent: some View {
        VStack(spacing: 10) {
            mainRow
            if store.usage.hasData {
                UsageFooter(usage: store.usage)
            }
        }
    }

    @ViewBuilder
    private var mainRow: some View {
        HStack(alignment: .top, spacing: 12) {
            MascotView(skin: store.primarySkin, state: store.state, level: voice.level, mood: store.mood)
                .frame(width: 60, height: 60)
                .contentShape(Rectangle())
                .onTapGesture { store.onPoke?() }
                .help("Klicka så berättar jag vad som händer")

            VStack(alignment: .leading, spacing: 8) {
                if let p = store.pending.first {
                    approval(p)
                } else if let text = store.bubble {
                    ScrollView { Text(text).font(.system(size: 13)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity, alignment: .leading) }
                } else {
                    sessionList
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 4) {
                Button { store.dismiss() } label: {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white.opacity(0.75))
                        .frame(width: 28, height: 28)
                        .background(Color.white.opacity(0.08), in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Fäll ihop")
                .accessibilityLabel("Fäll ihop notchen")

                Button { store.pinned.toggle() } label: {
                    Image(systemName: store.pinned ? "pin.fill" : "pin")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(store.pinned ? 0.95 : 0.5))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(store.pinned ? "Släpp (stängs när musen lämnar)" : "Håll öppen")
                .accessibilityLabel(store.pinned ? "Släpp notchen" : "Håll notchen öppen")
            }
        }
    }

    @ViewBuilder
    private func approval(_ p: PendingPermission) -> some View {
        Text(p.event.projectName.isEmpty ? "Godkännande" : p.event.projectName)
            .font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.6))
        Text(p.event.toolSummary)
            .font(.system(size: 13, design: .monospaced)).foregroundStyle(.white)
            .lineLimit(3)
        HStack(spacing: 8) {
            Button("Tillåt") { store.resolve(p, allow: true) }
                .buttonStyle(PillStyle(color: Color(red: 0.106, green: 0.490, blue: 0.271)))  // #1B7D45
            Button("Neka") { store.resolve(p, allow: false) }
                .buttonStyle(PillStyle(color: Color(red: 0.769, green: 0.204, blue: 0.227)))  // #C4343A
            Button("Terminal") { store.passToTerminal(p) }
                .buttonStyle(PillStyle(color: Color(red: 0.290, green: 0.282, blue: 0.325)))  // #4A4853
        }
        if p.event.isRisky {
            Text("Känsligt kommando – kräver klick").font(.system(size: 10)).foregroundStyle(.orange)
        }
    }

    @ViewBuilder
    private var sessionList: some View {
        let sessions = store.sessions.values.sorted { $0.updated > $1.updated }
        if sessions.isEmpty {
            Text("Inga Claude Code-sessioner just nu.")
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
            Text("Håll ⌃⌥ Mellanslag och prata med mig.")
                .font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
        } else {
            ForEach(sessions.prefix(3)) { s in
                Button { store.onJump?(s) } label: {
                    HStack(alignment: .top, spacing: 7) {
                        // Varje session har sin egen karaktär, med sitt eget uttryck
                        MascotView(skin: s.skin, state: store.state(for: s), mood: store.mood)
                            .frame(width: 22, height: 22)
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 6) {
                                Text(s.project).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                                Text(s.short).font(.system(size: 12)).foregroundStyle(.white.opacity(0.65))
                                Spacer(minLength: 0)
                                Text(s.updated, style: .relative)
                                    .font(.system(size: 10)).foregroundStyle(.white.opacity(0.4))
                                if s.appPath != nil {
                                    Image(systemName: "arrow.up.forward.app")
                                        .font(.system(size: 10)).foregroundStyle(.white.opacity(0.45))
                                }
                            }
                            if s.working, !s.activity.isEmpty, s.activity != s.short {
                                Text(s.activity).font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.white.opacity(0.55)).lineLimit(1)
                            }
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(s.appPath.map { "Hoppa till \(((($0 as NSString).lastPathComponent) as NSString).deletingPathExtension)" } ?? "Öppna projektmappen")
                .accessibilityLabel("\(s.skin.name) i \(s.project): \(s.short). Hoppa dit.")
            }
            if let last = sessions.first(where: { $0.lastMessage != nil }), let msg = last.lastMessage {
                Divider().overlay(Color.white.opacity(0.12))
                Text("Senaste svaret · \(last.project)")
                    .font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(0.45))
                ScrollView {
                    Text(msg).font(.system(size: 12)).foregroundStyle(.white.opacity(0.9))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            }
        }
    }
}

// MARK: - Användning (5 timmar / vecka)

enum UsageMeter {
    /// Pim-mint upp till 70 %, Kix-gul till 90 %, Oda-korall över
    static func color(_ pct: Double) -> Color {
        if pct >= 90 { return Color(red: 1.00, green: 0.48, blue: 0.42) }
        if pct >= 70 { return Color(red: 1.00, green: 0.78, blue: 0.24) }
        return Color(red: 0.37, green: 0.84, blue: 0.66)
    }

    static func resetText(_ date: Date?) -> String {
        guard let date else { return "" }
        let secs = date.timeIntervalSinceNow
        if secs <= 0 { return "nollställs nu" }
        if secs < 3600 { return "om \(Int(secs / 60)) min" }
        if secs < 24 * 3600 {
            let f = DateFormatter(); f.locale = Locale(identifier: "sv_SE"); f.dateFormat = "HH:mm"
            return "kl \(f.string(from: date))"
        }
        let f = DateFormatter(); f.locale = Locale(identifier: "sv_SE"); f.dateFormat = "EEE HH:mm"
        return f.string(from: date)
    }
}

struct UsageFooter: View {
    let usage: Usage
    var body: some View {
        HStack(spacing: 14) {
            if let p = usage.fiveHour { bar("5 tim", p, usage.fiveHourReset) }
            if let p = usage.sevenDay { bar("Vecka", p, usage.sevenDayReset) }
        }
        .padding(.horizontal, 2)
        .accessibilityElement(children: .combine)
    }

    private func bar(_ title: String, _ pct: Double, _ reset: Date?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(title).font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(0.55))
                Text("\(Int(pct.rounded())) %").font(.system(size: 10, weight: .bold)).foregroundStyle(.white.opacity(0.9))
                    .monospacedDigit()
                Spacer(minLength: 0)
                Text(UsageMeter.resetText(reset)).font(.system(size: 10)).foregroundStyle(.white.opacity(0.4))
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.1))
                    Capsule().fill(UsageMeter.color(pct))
                        .frame(width: max(5, g.size.width * min(1, pct / 100)))
                }
            }
            .frame(height: 5)
        }
        .frame(maxWidth: .infinity)
    }
}

struct PillStyle: ButtonStyle {
    let color: Color
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 12).padding(.vertical, 5)
            .background(color.opacity(configuration.isPressed ? 0.7 : 1), in: Capsule())
            .foregroundStyle(.white)
    }
}

/// Röst-/mikrofonnivå hålls separat så att 30 uppdateringar/s inte ritar om hela appen.
@MainActor
final class VoiceState: ObservableObject {
    @Published var level: Float = 0
}
