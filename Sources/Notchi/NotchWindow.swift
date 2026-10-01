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

    /// "Örat" på varje sida om den fysiska notchen
    var ear: CGFloat { notchHeight + 8 }
    /// Extra bredd per sida när en statustext visas
    static let labelRoom: CGFloat = 92

    /// Den svarta formens storlek i olika lägen
    func shapeSize(expanded: Bool, showsLabel: Bool) -> NSSize {
        if expanded { return NSSize(width: max(notchWidth + 2 * ear + 2 * Self.labelRoom, 460), height: notchHeight + 196) }
        let extra = showsLabel ? Self.labelRoom : 0
        return NSSize(width: notchWidth + 2 * (ear + extra), height: notchHeight)
    }

    /// Fönstret har ALLTID samma storlek (den största formen). Det stoppar fladdret som uppstår
    /// när ett fönster byter storlek under muspekaren.
    var canvas: NSRect {
        let s = shapeSize(expanded: true, showsLabel: true)
        return NSRect(x: screenFrame.midX - s.width / 2, y: screenFrame.maxY - s.height, width: s.width, height: s.height)
    }

    /// Formens yta i skärmkoordinater (för att avgöra om musen är över den)
    func shapeRect(expanded: Bool, showsLabel: Bool) -> NSRect {
        let s = shapeSize(expanded: expanded, showsLabel: showsLabel)
        return NSRect(x: screenFrame.midX - s.width / 2, y: screenFrame.maxY - s.height, width: s.width, height: s.height)
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
    let skin: () -> Skin

    var body: some View {
        let expanded = store.expanded
        let label = store.shortStatus
        let size = geometry.shapeSize(expanded: expanded, showsLabel: label != nil)
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                NotchShape(radius: expanded ? 22 : 10)
                    .fill(Color.black)
                if expanded {
                    expandedContent
                        .padding(.top, geometry.notchHeight + 8)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 14)
                        .transition(.opacity)
                } else {
                    collapsedContent(label: label)
                        .transition(.opacity)
                }
            }
            .frame(width: size.width, height: size.height)
            .contentShape(Rectangle())
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: expanded)
        .animation(.spring(response: 0.3, dampingFraction: 0.9), value: label)
    }

    // MARK: Hopfälld: maskot till vänster, kort status till höger

    private func collapsedContent(label: String?) -> some View {
        HStack(spacing: 0) {
            MascotView(skin: skin(), state: store.state, level: voice.level)
                .frame(width: geometry.notchHeight + 2, height: geometry.notchHeight - 2)
                .padding(.leading, 6)
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                if let label {
                    Text(label)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(statusColor)
                        .lineLimit(1)
                        .fixedSize()
                }
                statusDot
            }
            .padding(.trailing, 12)
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
        return Circle().fill(color).frame(width: 7, height: 7)
    }

    // MARK: Utfälld

    @ViewBuilder
    private var expandedContent: some View {
        HStack(alignment: .top, spacing: 14) {
            MascotView(skin: skin(), state: store.state, level: voice.level)
                .frame(width: 72, height: 72)
                .onTapGesture { store.pinned.toggle() }

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

            Button { store.pinned.toggle() } label: {
                Image(systemName: store.pinned ? "pin.fill" : "pin")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(store.pinned ? 0.95 : 0.5))
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(store.pinned ? "Släpp (stängs när musen lämnar)" : "Håll öppen")
            .accessibilityLabel(store.pinned ? "Släpp notchen" : "Håll notchen öppen")
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
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Circle().fill(s.working ? Color(red: 0.231, green: 0.510, blue: 0.965) : Color.gray)
                            .frame(width: 6, height: 6)
                        Text(s.project).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                        Text(s.short).font(.system(size: 12)).foregroundStyle(.white.opacity(0.65))
                        Spacer(minLength: 0)
                        Text(s.updated, style: .relative)
                            .font(.system(size: 10)).foregroundStyle(.white.opacity(0.4))
                    }
                    if s.working, !s.activity.isEmpty, s.activity != s.short {
                        Text(s.activity).font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.55)).lineLimit(1)
                            .padding(.leading, 12)
                    }
                }
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
