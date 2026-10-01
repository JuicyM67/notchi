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

struct NotchGeometry {
    let screen: NSScreen
    let notchWidth: CGFloat
    let notchHeight: CGFloat

    static func current() -> NotchGeometry {
        let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main ?? NSScreen.screens[0]
        var width: CGFloat = 200
        if let l = screen.auxiliaryTopLeftArea, let r = screen.auxiliaryTopRightArea {
            width = screen.frame.width - l.width - r.width
        }
        let height = screen.safeAreaInsets.top > 0 ? screen.safeAreaInsets.top : 26   // ingen notch: menyradshöjd
        return NotchGeometry(screen: screen, notchWidth: width, notchHeight: height)
    }

    /// Hopfälld: notchen + ett "öra" på varje sida. Utfälld: en panel under notchen.
    func frame(expanded: Bool) -> NSRect {
        let ear: CGFloat = notchHeight + 8
        let size = expanded ? NSSize(width: max(notchWidth + 2 * ear, 420), height: notchHeight + 150)
                            : NSSize(width: notchWidth + 2 * ear, height: notchHeight)
        let f = screen.frame
        return NSRect(x: f.midX - size.width / 2, y: f.maxY - size.height, width: size.width, height: size.height)
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
        ZStack(alignment: .top) {
            NotchShape(radius: expanded ? 22 : 10)
                .fill(Color.black)

            if expanded {
                expandedContent
                    .padding(.top, geometry.notchHeight + 6)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 14)
                    .transition(.opacity)
            } else {
                HStack(spacing: 0) {
                    MascotView(skin: skin(), state: store.state, level: voice.level)
                        .frame(width: geometry.notchHeight + 4, height: geometry.notchHeight)
                        .padding(.leading, 4)
                    Spacer()
                    statusDot
                        .padding(.trailing, 12)
                }
                .frame(height: geometry.notchHeight)
            }
        }
        .onHover { store.hovering = $0 }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: expanded)
    }

    private var statusDot: some View {
        let color: Color = switch store.state {
        case .needsApproval: .orange
        case .working, .thinking: .blue
        case .done: .green
        case .listening: .pink
        default: .gray.opacity(0.5)
        }
        return Circle().fill(color).frame(width: 7, height: 7)
    }

    @ViewBuilder
    private var expandedContent: some View {
        HStack(alignment: .top, spacing: 14) {
            MascotView(skin: skin(), state: store.state, level: voice.level)
                .frame(width: 84, height: 84)

            VStack(alignment: .leading, spacing: 8) {
                if let p = store.pending.first {
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
                } else if let text = store.bubble {
                    Text(text).font(.system(size: 13)).foregroundStyle(.white).lineLimit(5)
                } else {
                    ForEach(store.sessions.values.sorted { $0.updated > $1.updated }.prefix(3)) { s in
                        HStack(spacing: 6) {
                            Circle().fill(s.working ? Color.blue : Color.gray).frame(width: 6, height: 6)
                            Text(s.project).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                            Text(s.activity).font(.system(size: 12)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                        }
                    }
                    if store.sessions.isEmpty {
                        Text("Håll ⌃⌥ Mellanslag och prata med mig.")
                            .font(.system(size: 12)).foregroundStyle(.white.opacity(0.6))
                    }
                }
            }
            Spacer(minLength: 0)
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
