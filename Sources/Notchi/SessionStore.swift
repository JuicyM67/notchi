import Foundation
import AppKit
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
    var skin: Skin = .pim           // varje session har sin egen karaktär
    var appPath: String? = nil      // appen sessionen körs i (Terminal, VS Code, Claude …)
}

/// Claude-användning från Claude Codes statusrad (bara Pro/Max)
struct Usage: Codable, Equatable {
    var fiveHour: Double? = nil
    var fiveHourReset: Date? = nil
    var sevenDay: Double? = nil
    var sevenDayReset: Date? = nil
    var updated: Date? = nil

    var hasData: Bool { fiveHour != nil || sevenDay != nil }

    static let file = Config.dir.appendingPathComponent("usage.json")
    static func load() -> Usage {
        guard let d = try? Data(contentsOf: file), var u = try? JSONDecoder().decode(Usage.self, from: d) else { return Usage() }
        u.dropExpired()
        return u
    }
    func save() { if let d = try? JSONEncoder().encode(self) { try? d.write(to: Usage.file, options: .atomic) } }

    /// Ett fönster vars nollställning passerat gäller inte längre
    mutating func dropExpired() {
        let now = Date()
        if let r = fiveHourReset, r < now { fiveHour = 0; fiveHourReset = nil }
        if let r = sevenDayReset, r < now { sevenDay = 0; sevenDayReset = nil }
    }
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
    @Published var usage = Usage.load()
    @Published var pinned = false                 // låst öppen (klicka på nålen)
    @Published var dismissed = false              // du stängde den: öppna inte av sig själv förrän något nytt händer
    /// Klick på maskoten
    var onPoke: (() -> Void)?
    /// Klick på en session i listan
    var onJump: ((SessionInfo) -> Void)?
    /// Avklarade uppgifter (för humöret "stolt")
    private var completions: [Date] = []
    private var lastMood: Mood = .normal

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

    /// Din valda karaktär (menyn) – används när inget pågår och för första sessionen
    var preferredSkin: Skin { Skin(rawValue: config.skin) ?? .pim }
    var style: MascotStyle { MascotStyle(rawValue: config.style) ?? .visor }

    /// Ny session: din valda karaktär om den är ledig, annars nästa lediga i gänget
    private func nextSkin() -> Skin {
        let used = Set(sessions.values.map(\.skin))
        // Samma familj först: väljer du ett djur får nästa session också ett djur
        let family = preferredSkin.isAnimal ? Skin.animals : Skin.gang
        let others = preferredSkin.isAnimal ? Skin.gang : Skin.animals
        let order = [preferredSkin] + family.filter { $0 != preferredSkin } + others
        return order.first { !used.contains($0) } ?? order[sessions.count % order.count]
    }

    /// Du bytte karaktär i menyn: ge pågående sessioner nya karaktärer direkt.
    /// Den viktigaste (eller senaste) får den du valde, resten nästa ur samma grupp.
    func reassignSkins() {
        let family = preferredSkin.isAnimal ? Skin.animals : Skin.gang
        let others = preferredSkin.isAnimal ? Skin.gang : Skin.animals
        let order = [preferredSkin] + family.filter { $0 != preferredSkin } + others
        var ids = sessions.values.sorted { $0.updated > $1.updated }.map(\.id)
        if let p = primarySession?.id, let i = ids.firstIndex(of: p) { ids.remove(at: i); ids.insert(p, at: 0) }
        for (i, id) in ids.enumerated() { sessions[id]?.skin = order[i % order.count] }
    }

    /// Den session som är viktigast just nu: den som väntar på dig, annars den som jobbar
    var primarySession: SessionInfo? {
        if let p = pending.first, let s = sessions[p.event.sessionId] { return s }
        if let s = sessions.values.filter({ $0.working }).max(by: { $0.updated < $1.updated }) { return s }
        return sessions.values.filter { Date().timeIntervalSince($0.updated) < 600 }.max(by: { $0.updated < $1.updated })
    }

    /// Karaktären som syns i notchen
    var primarySkin: Skin { primarySession?.skin ?? preferredSkin }

    /// Uttrycket för en enskild session i listan
    func state(for s: SessionInfo) -> MascotState {
        if pending.contains(where: { $0.event.sessionId == s.id }) { return .needsApproval }
        if s.working { return s.short == "Tänker…" ? .thinking : .working }
        if s.short == "Klar", Date().timeIntervalSince(s.updated) < 6 { return .done }
        return .idle
    }

    /// Humöret över dagen
    var mood: Mood {
        if (usage.fiveHour ?? 0) >= 90 || (usage.sevenDay ?? 0) >= 95 { return .stressed }
        let recent = completions.filter { Date().timeIntervalSince($0) < 90 * 60 }.count
        if recent >= 4 { return .proud }
        let h = Calendar.current.component(.hour, from: Date())
        if h < 8 || h >= 23 { return .sleepy }
        return .normal
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

    private func updateUsage(from j: [String: Any], session: String) {
        guard let rl = j["rate_limits"] as? [String: Any] else { return }
        var u = usage
        func read(_ key: String) -> (Double?, Date?) {
            guard let w = rl[key] as? [String: Any] else { return (nil, nil) }
            let pct = (w["used_percentage"] as? NSNumber)?.doubleValue
            let reset = (w["resets_at"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
            return (pct, reset)
        }
        let (f, fr) = read("five_hour"); if let f { u.fiveHour = f; u.fiveHourReset = fr }
        let (s, sr) = read("seven_day"); if let s { u.sevenDay = s; u.sevenDayReset = sr }
        u.updated = Date()
        setUsage(u)
    }

    /// Värden från den direkta hämtningen (UsagePoller)
    func applyPolled(_ r: UsagePoller.Result) {
        var u = usage
        if let f = r.fiveHour { u.fiveHour = f; u.fiveHourReset = r.fiveReset }
        if let s = r.sevenDay { u.sevenDay = s; u.sevenDayReset = r.sevenReset }
        u.updated = Date()
        setUsage(u)
    }

    private func setUsage(_ u: Usage) {
        guard u != usage else { return }
        usage = u
        u.save()
        warnIfNeeded(u)
    }

    // MARK: - Varning för gränsen (en gång per fönster, kommer ihåg det mellan omstarter)

    private func warnIfNeeded(_ u: Usage) {
        var lines: [String] = []
        if let f = u.fiveHour {
            if f >= 100, once("5h-100", u.fiveHourReset) {
                lines.append("Nu är femtimmarsgränsen nådd. Du kan köra igen \(Narrator.when(u.fiveHourReset)).")
            } else if f >= 80, f < 100, once("5h-80", u.fiveHourReset) {
                lines.append("Du har använt \(Int(f.rounded())) procent av femtimmarsgränsen. Den nollställs \(Narrator.when(u.fiveHourReset)).")
            }
        }
        if let w = u.sevenDay {
            if w >= 100, once("7d-100", u.sevenDayReset) {
                lines.append("Veckogränsen är nådd. Den nollställs \(Narrator.when(u.sevenDayReset)).")
            } else if w >= 90, w < 100, once("7d-90", u.sevenDayReset) {
                lines.append("Veckan ligger på \(Int(w.rounded())) procent. Den nollställs \(Narrator.when(u.sevenDayReset)).")
            }
        }
        guard !lines.isEmpty else { return }
        let text = lines.joined(separator: " ")
        announce(text, sound: "Funk", important: true)
    }

    /// true första gången för just det här fönstret (identifieras av när det nollställs)
    private func once(_ key: String, _ reset: Date?) -> Bool {
        let id = reset.map { String(Int($0.timeIntervalSince1970 / 60)) } ?? "okänd"
        let defaults = UserDefaults.standard
        var seen = defaults.dictionary(forKey: "notchi.warned") as? [String: String] ?? [:]
        if seen[key] == id { return false }
        seen[key] = id
        defaults.set(seen, forKey: "notchi.warned")
        return true
    }

    /// Sessioner som inte hörts av på länge räknas inte längre som aktiva
    func expireStale() {
        var u = usage; u.dropExpired(); if u != usage { usage = u }
        if mood != lastMood { lastMood = mood; objectWillChange.send() }   // t.ex. när klockan slår 8
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
        if e.name == "StatusLine" { updateUsage(from: e.raw, session: e.sessionId); return }
        var s = sessions[e.sessionId] ?? SessionInfo(id: e.sessionId, project: e.projectName, cwd: e.cwd,
                                                      activity: "", working: false, updated: Date(),
                                                      skin: nextSkin())
        s.updated = Date()
        if let app = e.raw["notchi_app"] as? String, !app.isEmpty { s.appPath = app }
        let isAgent = e.raw["notchi_agent"] as? Bool == true
        if isAgent { s.project = "Notchi" }
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
                announce(Narrator.permission(e), sound: "Ping")
            }
        case "Notification":
            if e.notificationType == "idle_prompt" {
                s.working = false
                s.short = "Väntar på dig"
                announce("\(s.project) väntar på dig.", sound: "Pop")
            }
        case "Stop":
            s.working = false
            s.short = "Klar"
            s.activity = ""
            if let m = e.lastAssistantMessage { s.lastMessage = m }
            justFinished = Date()
            completions.append(Date())
            completions.removeAll { Date().timeIntervalSince($0) > 3 * 3600 }
            if !isAgent { announce(Narrator.done(project: s.project), sound: "Glass") }
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
        let many = sessions.count > 1
        for s in sorted.filter({ $0.working }).prefix(2) {
            parts.append(many ? "\(s.skin.name) i \(s.project): \(Narrator.doing(s, inverted: false)) just nu."
                              : "I \(s.project) \(Narrator.doing(s)) just nu.")
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
        if let u = usageSentence(onlyIfHigh: !parts.isEmpty) { parts.append(u) }
        if parts.isEmpty { parts.append(["Det är lugnt just nu. Inga sessioner är igång.",
                                         "Allt är tyst. Claude vilar.",
                                         "Inget på gång just nu."].randomElement()!) }
        if let m = Narrator.moodOpener(mood) { parts.insert(m, at: 0) }
        return parts.joined(separator: " ")
    }

    /// "Du har använt 42 procent av femtimmarsgränsen …"
    func usageSentence(onlyIfHigh: Bool = false) -> String? {
        guard let f = usage.fiveHour else { return nil }
        if onlyIfHigh && f < 70 && (usage.sevenDay ?? 0) < 80 { return nil }
        var s = "Du har använt \(Int(f.rounded())) procent av femtimmarsgränsen"
        if let r = usage.fiveHourReset {
            let mins = Int(r.timeIntervalSinceNow / 60)
            if mins > 0 { s += mins < 60 ? ", den nollställs om \(mins) minuter" : ", den nollställs om \(mins / 60) timmar och \(mins % 60) minuter" }
        }
        s += "."
        if let w = usage.sevenDay { s += " Veckan ligger på \(Int(w.rounded())) procent." }
        return s
    }

    /// Säg till om en händelse på det sätt du valt i menyn.
    /// important: visa texten i notchen även i ljudläge (t.ex. gränsvarningar)
    func announce(_ text: String, sound: String, important: Bool = false) {
        switch config.eventStyle {
        case "voice":
            say?(text)
        case "silent":
            if important { showBubble(text, seconds: 12) }
        default:   // "sounds"
            NSSound(named: NSSound.Name(sound))?.play()
            if important { showBubble(text, seconds: 12) }
        }
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
    /// inverted: "skriver Claude kod" (efter "I projekt"); annars "Claude skriver kod"
    static func doing(_ s: SessionInfo, inverted: Bool = true) -> String {
        guard inverted else {
            let v = doing(s)                       // "skriver Claude kod i X"
            if v.hasPrefix("har Claude") { return "Claude har" + v.dropFirst("har Claude".count) }
            let parts = v.split(separator: " ", maxSplits: 2).map(String.init)
            guard parts.count >= 2, parts[1] == "Claude" else { return v }
            return "Claude " + parts[0] + (parts.count > 2 ? " " + parts[2] : "")
        }
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

    /// "kl 14:30", "om 12 minuter", "på torsdag kl 09:00"
    static func when(_ date: Date?) -> String {
        guard let date else { return "snart" }
        let secs = date.timeIntervalSinceNow
        if secs <= 60 { return "alldeles strax" }
        if secs < 3600 { return "om \(Int(secs / 60)) minuter" }
        let f = DateFormatter(); f.locale = Locale(identifier: "sv_SE")
        if Calendar.current.isDateInToday(date) { f.dateFormat = "HH:mm"; return "klockan \(f.string(from: date))" }
        if Calendar.current.isDateInTomorrow(date) { f.dateFormat = "HH:mm"; return "i morgon klockan \(f.string(from: date))" }
        f.dateFormat = "EEEE 'klockan' HH:mm"; return "på " + f.string(from: date)
    }

    /// En liten inledning efter humör, ibland
    static func moodOpener(_ mood: Mood) -> String? {
        guard Bool.random() else { return nil }
        let h = Calendar.current.component(.hour, from: Date())
        switch mood {
        case .sleepy: return h < 12 ? ["Gääsp… god morgon.", "Morgon. Kaffe först?"].randomElement()
                                    : ["Det börjar bli sent…", "Gääsp. Sent ikväll, va?"].randomElement()
        case .proud: return ["Vilken fart idag!", "Det flyter på!"].randomElement()
        case .stressed: return ["Oj, nu börjar det bli trångt.", "Puh, vi närmar oss gränsen."].randomElement()
        case .normal: return nil
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
