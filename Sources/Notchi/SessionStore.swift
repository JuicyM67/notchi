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
    var activity: String      // detalj: "npm test", "Edit App.swift", …
    var short: String = ""    // kort: "Tänker…", "Kodar", "Kör kommando", …
    var lastMessage: String? = nil
    var detail: String? = nil       // "App.swift", "npm", …
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
    @Published var pinned = false                 // låst öppen (klicka på nålen)
    @Published var dismissed = false              // du stängde den: öppna inte av sig själv förrän något nytt händer
    /// Klick på maskoten
    var onPoke: (() -> Void)?

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

    var expanded: Bool {
        hovering || pinned || listening || (!dismissed && (!pending.isEmpty || bubble != nil))
    }

    /// Stängknappen: fäll ihop, oavsett vad som höll den öppen
    func dismiss() {
        pinned = false
        hovering = false
        dismissed = true
        bubble = nil
    }

    /// Kort text som visas bredvid notchen även när den är hopfälld (nil = bara prick)
    var shortStatus: String? {
        if listening { return "Lyssnar…" }
        if !pending.isEmpty { return "Behöver dig" }
        if speaking { return "Pratar" }
        if thinkingLocally { return "Tänker…" }
        if let s = sessions.values.filter({ $0.working }).max(by: { $0.updated < $1.updated }) {
            return s.short.isEmpty ? "Jobbar" : s.short
        }
        if let t = justFinished, Date().timeIntervalSince(t) < 6 { return "Klar!" }
        return nil
    }

    /// Sessioner som inte hörts av på länge räknas inte längre som aktiva
    func expireStale() {
        let now = Date()
        for (id, s) in sessions where s.working && now.timeIntervalSince(s.updated) > 15 * 60 {
            sessions[id]?.working = false
            sessions[id]?.short = "Tyst"
        }
    }

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
            s.activity = ""; s.short = "Redo"
        case "UserPromptSubmit":
            s.activity = ""; s.short = "Tänker…"; s.working = true
        case "PreToolUse":
            s.activity = e.toolSummary; s.short = e.shortLabel; s.detail = e.spokenDetail; s.working = true
        case "PostToolUse", "PostToolUseFailure":
            s.short = "Tänker…"; s.detail = nil; s.working = true
        case "PermissionRequest":
            s.activity = e.toolSummary; s.short = "Behöver dig"
            if let reply {
                let item = PendingPermission(event: e, reply: reply)
                // Svarade du i terminalen eller avbröts sessionen? Ta bort frågan från notchen.
                reply.onClosed = { [weak self] in self?.pending.removeAll { $0.id == item.id } }
                pending.append(item)
                dismissed = false            // ny fråga: visa den
                if config.speakEvents {
                    say?(Narrator.permission(e))
                }
            }
        case "Notification":
            if e.notificationType == "idle_prompt" {
                s.working = false
                s.short = "Väntar på dig"
                if config.speakEvents { say?("\(s.project) väntar på dig.") }
            }
        case "Stop":
            s.working = false
            s.short = "Klar"
            s.activity = ""
            if let m = e.lastAssistantMessage { s.lastMessage = m }
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
            "\(s.project): \(s.working ? s.short.lowercased() : (s.short.isEmpty ? "vilar" : s.short.lowercased()))"
        }
        var text = parts.joined(separator: ". ")
        if !pending.isEmpty { text += ". \(pending.count) sak väntar på ditt godkännande." }
        return text
    }

    /// Det Notchi säger när du klickar på den. Byggs av färdiga fraser: gratis och direkt.
    func spokenStatus() -> String {
        var parts: [String] = []
        if let p = pending.first {
            parts.append(Narrator.permission(p.event))
        }
        let sorted = sessions.values.sorted { $0.updated > $1.updated }
        for s in sorted.filter({ $0.working }).prefix(2) {
            parts.append("I \(s.project) \(Narrator.doing(s)) just nu.")
        }
        if parts.isEmpty, let s = sorted.first {
            var line = s.short == "Väntar på dig"
                ? "\(s.project) väntar på dig, \(Narrator.ago(s.updated))."
                : "\(s.project) blev klart \(Narrator.ago(s.updated))."
            if let m = s.lastMessage, let first = Narrator.firstSentence(m) {
                line += " Claude sa: \(first)"
            }
            parts.append(line)
        }
        let others = sorted.filter { $0.working }.count - 2
        if others > 0 { parts.append("Och \(others) till jobbar.") }
        if parts.isEmpty { return ["Det är lugnt just nu. Inga sessioner är igång.",
                                   "Allt är tyst. Claude vilar.",
                                   "Inget på gång just nu."].randomElement()! }
        return parts.joined(separator: " ")
    }

    func showBubble(_ text: String, seconds: Double = 8) {
        dismissed = false
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

    /// "skriver kod i App.swift", "kör npm", "tänker", …
    static func doing(_ s: SessionInfo) -> String {
        let d = s.detail
        switch s.short {
        case "Kodar": return d.map { "skriver Claude kod i \($0)" } ?? "skriver Claude kod"
        case "Kör kommando": return d.map { "kör Claude \($0)" } ?? "kör Claude ett kommando"
        case "Läser": return d.map { "läser Claude \($0)" } ?? "läser Claude filer"
        case "Söker": return d.map { "söker Claude efter \($0)" } ?? "söker Claude på webben"
        case "Delegerar": return "har Claude skickat iväg en hjälpreda"
        case "Planerar": return "planerar Claude"
        case "Har en fråga": return "har Claude en fråga till dig"
        case "Använder verktyg": return "använder Claude ett verktyg"
        case "Behöver dig": return "väntar Claude på ditt godkännande"
        default: return "tänker Claude"
        }
    }

    static func ago(_ date: Date) -> String {
        let s = Int(Date().timeIntervalSince(date))
        switch s {
        case ..<60: return "nyss"
        case ..<120: return "för en minut sedan"
        case ..<3600: return "för \(s / 60) minuter sedan"
        case ..<7200: return "för en timme sedan"
        default: return "för \(s / 3600) timmar sedan"
        }
    }

    /// Första meningen i Claudes svar, utan markdown, max ca 160 tecken
    static func firstSentence(_ text: String) -> String? {
        var t = text.replacingOccurrences(of: #"```[\s\S]*?```"#, with: " ", options: .regularExpression)
        t = t.replacingOccurrences(of: #"[*_`#>|]"#, with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return nil }
        if let r = t.range(of: #"[.!?](\s|$)"#, options: .regularExpression) {
            t = String(t[..<r.upperBound]).trimmingCharacters(in: .whitespaces)
        }
        if t.count > 160 { t = String(t.prefix(157)) + "…" }
        return t
    }

    static func done(project: String) -> String {
        ["Klart i \(project)!", "\(project) är färdigt.", "Nu är \(project) klart."].randomElement()!
    }
}
