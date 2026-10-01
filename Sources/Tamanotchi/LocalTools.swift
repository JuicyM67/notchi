import Foundation
import AppKit

/// Saker Tamanotchi kan göra på datorn. Samma funktioner används både av den lokala
/// kommandotolken (gratis) och av Claude som verktyg (tool use).
enum LocalTools {

    static let knownFolders: [String: String] = [
        "skrivbord": "Desktop", "skrivbordet": "Desktop", "desktop": "Desktop",
        "hämtade filer": "Downloads", "hämtningar": "Downloads", "nedladdningar": "Downloads", "downloads": "Downloads",
        "dokument": "Documents", "dokumenten": "Documents", "documents": "Documents",
        "bilder": "Pictures", "bilderna": "Pictures", "musik": "Music", "filmer": "Movies",
        "hem": "", "hemmappen": "",
    ]

    // MARK: Mappar

    @discardableResult
    static func openFolder(_ name: String) -> String {
        let key = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let home = FileManager.default.homeDirectoryForCurrentUser
        if key == "program" || key == "programmappen" || key == "applications" {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications"))
            return "Öppnar Program."
        }
        if let sub = knownFolders[key] {
            NSWorkspace.shared.open(sub.isEmpty ? home : home.appendingPathComponent(sub))
            return "Öppnar \(name)."
        }
        if key.hasPrefix("/") || key.hasPrefix("~") {
            let url = URL(fileURLWithPath: (name as NSString).expandingTildeInPath)
            if FileManager.default.fileExists(atPath: url.path) { NSWorkspace.shared.open(url); return "Öppnar \(url.lastPathComponent)." }
        }
        // Sök med Spotlight efter en mapp med det namnet
        let hits = spotlight("kMDItemContentType == 'public.folder' && kMDItemDisplayName == '*\(escape(name))*'cd", limit: 5)
            .sorted { $0.count < $1.count }     // kortast sökväg = troligast
        if let first = hits.first {
            NSWorkspace.shared.open(URL(fileURLWithPath: first))
            return "Öppnar \((first as NSString).lastPathComponent)."
        }
        return "Jag hittade ingen mapp som heter \(name)."
    }

    // MARK: Filer

    static func findFiles(_ query: String, reveal: Bool = true, limit: Int = 10) -> (summary: String, paths: [String]) {
        let q = escape(query)
        let hits = spotlight("kMDItemDisplayName == '*\(q)*'cd && kMDItemContentType != 'public.folder'", limit: limit)
        guard !hits.isEmpty else { return ("Jag hittade inga filer som matchar \(query).", []) }
        if reveal {
            NSWorkspace.shared.activateFileViewerSelecting(hits.prefix(5).map { URL(fileURLWithPath: $0) })
        }
        let names = hits.prefix(3).map { ($0 as NSString).lastPathComponent }.joined(separator: ", ")
        let summary = hits.count == 1 ? "Hittade \(names)." : "Hittade \(hits.count) filer, bland annat \(names)."
        return (summary, hits)
    }

    // MARK: Program

    @discardableResult
    static func launchApp(_ name: String) -> String {
        let q = escape(name)
        let apps = spotlight("kMDItemContentType == 'com.apple.application-bundle' && kMDItemDisplayName == '\(q)*'cd", limit: 10)
            .filter { !$0.contains("/Library/") || $0.hasPrefix("/System/Applications") }
            .sorted { $0.count < $1.count }
        guard let path = apps.first else { return "Jag hittade inget program som heter \(name)." }
        let cfg = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: cfg)
        return "Startar \(((path as NSString).lastPathComponent as NSString).deletingPathExtension)."
    }

    // MARK: Genvägar (Shortcuts-appen) — superverktyget

    static func runShortcut(_ name: String, input: String? = nil) -> String {
        var args = ["run", name]
        var tmp: URL?
        if let input {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("tamanotchi-\(UUID().uuidString).txt")
            try? input.write(to: url, atomically: true, encoding: .utf8)
            args += ["-i", url.path]; tmp = url
        }
        let out = run("/usr/bin/shortcuts", args, timeout: 60)
        if let tmp { try? FileManager.default.removeItem(at: tmp) }
        return out.isEmpty ? "Körde genvägen \(name)." : out
    }

    // MARK: Musik (Spotify om det finns, annars Musik) – gratis och direkt via AppleScript

    enum Media { case play, pause, toggle, next, previous }

    static func media(_ action: Media) -> String {
        let spotify = FileManager.default.fileExists(atPath: "/Applications/Spotify.app")
            || NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == "com.spotify.client" }
        let app = spotify ? "Spotify" : "Music"
        let verb: String
        let reply: String
        switch action {
        case .play:     verb = "play";             reply = "Spelar musik."
        case .pause:    verb = "pause";            reply = "Pausat."
        case .toggle:   verb = "playpause";        reply = "Okej."
        case .next:     verb = "next track";       reply = "Nästa låt."
        case .previous: verb = "previous track";   reply = "Förra låten."
        }
        let script = """
        tell application "\(app)"
            if not running then launch
            delay 0.8
            \(verb)
        end tell
        """
        _ = run("/usr/bin/osascript", ["-e", script], timeout: 10)
        return reply
    }

    // MARK: Delegera till Claude Code (använder ditt Claude-abonnemang, inte API-krediter)

    static func askClaudeCode(_ prompt: String, cwd: String?) -> String {
        let dir = cwd ?? FileManager.default.homeDirectoryForCurrentUser.path
        // Prompten skickas som argument, aldrig inbakad i skalsträngen
        let out = run("/bin/zsh", ["-lc", "export PATH=\"$HOME/.local/bin:$HOME/.claude/local:/opt/homebrew/bin:/usr/local/bin:$PATH\"; cd \"$1\" && claude -p \"$2\" --output-format text", "tamanotchi", dir, prompt], timeout: 300)
        return out.isEmpty ? "Claude Code svarade inte." : String(out.prefix(2000))
    }

    // MARK: Hjälpfunktioner

    static func spotlight(_ query: String, limit: Int) -> [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        var results = run("/usr/bin/mdfind", ["-onlyin", home, query], timeout: 8)
            .split(separator: "\n").map(String.init)
        if query.contains("application-bundle") {
            results += run("/usr/bin/mdfind", ["-onlyin", "/Applications", query], timeout: 8).split(separator: "\n").map(String.init)
            results += run("/usr/bin/mdfind", ["-onlyin", "/System/Applications", query], timeout: 8).split(separator: "\n").map(String.init)
        }
        // Skippa bibliotek, cachar och dolda mappar
        let filtered = results.filter { p in
            !p.contains("/Library/Caches") && !p.contains("/node_modules/") && !p.contains("/.") &&
            (!p.contains("/Library/") || p.hasPrefix("/System/Applications") || p.hasPrefix("/Applications"))
        }
        var seen = Set<String>()
        return Array(filtered.filter { seen.insert($0).inserted }.prefix(limit))
    }

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "").replacingOccurrences(of: "'", with: "").replacingOccurrences(of: "*", with: "")
    }

    static func run(_ exe: String, _ args: [String], timeout: TimeInterval) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return "" }
        let deadline = Date().addingTimeInterval(timeout)
        DispatchQueue.global().async {
            while p.isRunning && Date() < deadline { usleep(100_000) }
            if p.isRunning { p.terminate() }
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}
