import Foundation
import Combine

/// Maskotens humör/tillstånd. Styr animation och färgaccent.
enum MascotState: String {
    case idle, thinking, working, needsApproval, done, listening, speaking, error
}

struct SessionInfo: Identifiable {
    let id: String
    var project: String
    var cwd: String
    var activity: String      // "Tänker…", "Bash npm test", …
    var working: Bool
    var updated: Date
}

struct PendingPermission: Identifiable {
    let id = UUID()
    let event: HookEvent
    let reply: HookReply
}

@MainActor
final class SessionStore: ObservableObject {
    @Published var sessions: [String: SessionInfo] = [:]
    @Published var pending: [PendingPermission] = []
    @Published var bubble: String? = nil          // text i pratbubblan
    @Published var listening = false
    @Published var speaking = false
    @Published var thinkingLocally = false        // Notchi själv väntar på Claude API
    @Published var justFinished: Date? = nil
    @Published var hovering = false

    /// Anropas när något ska sägas högt.
    var say: ((String) -> Void)?
    var config: Config

    init(config: Config) { self.config = config }

    var state: MascotState {
        if listening { return .listening }
        if !pending.isEmpty { return .needsApproval }
        if speaking { return .speaking }
        if thinkingLocally { return .thinking }
        if sessions.values.contains(where: { $0.working }) { return .working }
        if let t = justFinished, Date().timeIntervalSince(t) < 6 { return .done }
        return .idle
    }

    var expanded: Bool { hovering || !pending.isEmpty || bubble != nil || listening }

    var mostRecentCwd: String? {
        sessions.values.max(by: { $0.updated < $1.updated })?.cwd
    }

    // MARK: - Händelser från Claude Code

    func handle(_ e: HookEvent, reply: HookReply?) {
        var s = sessions[e.sessionId] ?? SessionInfo(id: e.sessionId, project: e.projectName, cwd: e.cwd,
                                                      activity: "", working: false, updated: Date())
        s.updated = Date()
        if !e.cwd.isEmpty { s.cwd = e.cwd; s.project = e.projectName }

        switch e.name {
        case "SessionStart":
            s.activity = "Redo"
        case "UserPromptSubmit":
            s.activity = "Tänker…"; s.working = true
        case "PreToolUse":
            s.activity = e.toolSummary; s.working = true
        case "PermissionRequest":
            s.activity = "Väntar på godkännande"
            if let reply {
                let item = PendingPermission(event: e, reply: reply)
                // Svarade du i terminalen eller avbröts sessionen? Ta bort frågan från notchen.
                reply.onClosed = { [weak self] in self?.pending.removeAll { $0.id == item.id } }
                pending.append(item)
                if config.speakEvents {
                    say?(Narrator.permission(e))
                }
            }
        case "Notification":
            if e.notificationType == "idle_prompt" {
                s.working = false
                s.activity = "Väntar på dig"
                if config.speakEvents { say?("\(s.project) väntar på dig.") }
            }
        case "Stop":
            s.working = false
            s.activity = "Klar"
            justFinished = Date()
            if config.speakEvents { say?(Narrator.done(project: s.project)) }
            // Uppdatera vyn igen när "klar"-glädjen har gått över
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(6.5))
                self?.objectWillChange.send()
            }
        case "SessionEnd":
            sessions[e.sessionId] = nil
            return
        default:
            break
        }
        sessions[e.sessionId] = s
    }

    // MARK: - Godkännanden

    func resolve(_ p: PendingPermission, allow: Bool) {
        allow ? p.reply.allow() : p.reply.deny()
        pending.removeAll { $0.id == p.id }
    }

    func passToTerminal(_ p: PendingPermission) {
        p.reply.passToTerminal()
        pending.removeAll { $0.id == p.id }
    }

    /// Kort sammanfattning av läget, utan API-anrop.
    func statusSummary() -> String {
        if sessions.isEmpty { return "Inga Claude Code-sessioner är igång just nu." }
        let parts = sessions.values.sorted { $0.updated > $1.updated }.prefix(3).map { s in
            "\(s.project): \(s.working ? s.activity : (s.activity.isEmpty ? "vilar" : s.activity.lowercased()))"
        }
        var text = parts.joined(separator: ". ")
        if !pending.isEmpty { text += ". \(pending.count) sak väntar på ditt godkännande." }
        return text
    }

    func showBubble(_ text: String, seconds: Double = 8) {
        bubble = text
        let snapshot = text
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            if self?.bubble == snapshot && self?.speaking == false { self?.bubble = nil }
        }
    }
}

/// Färdiga fraser: gratis och snabba (ingen AI behövs för att läsa upp händelser).
enum Narrator {
    static func permission(_ e: HookEvent) -> String {
        let project = e.projectName.isEmpty ? "Claude" : e.projectName
        switch e.toolName ?? "" {
        case "Bash":
            let first = (e.toolInput["command"] as? String ?? "").split(separator: " ").prefix(3).joined(separator: " ")
            return "\(project) vill köra \(first). Godkänner du?"
        case "Edit", "Write", "MultiEdit":
            let file = ((e.toolInput["file_path"] as? String ?? "") as NSString).lastPathComponent
            return "\(project) vill ändra \(file). Okej?"
        case "WebFetch":
            return "\(project) vill hämta en webbsida. Okej?"
        default:
            return "\(project) behöver ditt godkännande."
        }
    }

    static func done(project: String) -> String {
        ["Klart i \(project)!", "\(project) är färdigt.", "Nu är \(project) klart."].randomElement()!
    }
}
