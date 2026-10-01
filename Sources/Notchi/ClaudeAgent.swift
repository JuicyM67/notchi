import Foundation
import AppKit

/// Notchis "händer": låter Claude Code utföra uppgifter på datorn.
///
/// Ingen API-nyckel behövs – det körs med `claude -p` och ditt vanliga Claude-abonnemang.
/// Claude Code får bara använda en kort lista med verktyg (öppna appar och filer, AppleScript,
/// skapa mappar, Spotlight, Genvägar, läsa filer, söka på webben). Radera, flytta och skriva
/// över är spärrat, och instruktionen säger uttryckligen att aldrig skicka, köpa eller ta bort något.
enum ClaudeAgent {

    static let allowedTools = [
        "Bash(open:*)", "Bash(osascript:*)", "Bash(mkdir:*)", "Bash(mdfind:*)", "Bash(ls:*)",
        "Bash(shortcuts:*)", "Bash(code:*)", "Bash(touch:*)", "Bash(pwd)",
        "Read", "Glob", "Grep", "WebSearch", "WebFetch",
    ]
    static let disallowedTools = [
        "Bash(rm:*)", "Bash(mv:*)", "Bash(sudo:*)", "Bash(curl:*)", "Bash(git push:*)", "Edit", "Write",
    ]

    /// Vad "här" och liknande betyder just nu
    struct Context {
        var frontApp: String
        var here: String          // mapp
        var hereReason: String    // "mappen som är öppen i Finder", …
        var recentProject: String?
    }

    /// Samla läget innan vi frågar (körs på huvudtråden)
    @MainActor
    static func gatherContext(recentProject: String?) -> Context {
        let front = NSWorkspace.shared.frontmostApplication
        let name = front?.localizedName ?? "okänd"
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if front?.bundleIdentifier == "com.apple.finder", let path = finderFrontFolder() {
            return Context(frontApp: name, here: path, hereReason: "mappen som är öppen i Finder", recentProject: recentProject)
        }
        let editors = ["com.microsoft.VSCode", "com.todesktop.230313mzl4w4u92", "com.apple.Terminal",
                       "com.googlecode.iterm2", "dev.warp.Warp-Stable", "com.mitchellh.ghostty", "dev.zed.Zed"]
        if let id = front?.bundleIdentifier, editors.contains(id), let p = recentProject {
            return Context(frontApp: name, here: p, hereReason: "projektet du senast jobbade i med Claude Code", recentProject: recentProject)
        }
        return Context(frontApp: name, here: home + "/Desktop", hereReason: "skrivbordet (ingen mapp var öppen)", recentProject: recentProject)
    }

    /// Mappen i Finders främsta fönster. Första gången frågar macOS om Notchi får styra Finder.
    static func finderFrontFolder() -> String? {
        let script = """
        tell application "Finder"
            if (count of Finder windows) is 0 then return ""
            return POSIX path of (target of front Finder window as alias)
        end tell
        """
        let out = LocalTools.run("/usr/bin/osascript", ["-e", script], timeout: 5)
        return out.isEmpty ? nil : out
    }

    static func systemPrompt(_ c: Context) -> String {
        """
        Du är Notchis händer på användarens Mac (macOS). Användaren pratar med dig via röst, på svenska.
        Utför uppgiften direkt med dina verktyg: `open -a App`, `open <fil/url>`, `osascript -e '…'` (AppleScript),
        `mkdir -p`, `mdfind`, `code <mapp>`, `shortcuts run <namn>`.
        Ställ inga följdfrågor – gör det mest rimliga tolkningen. Om ett namn är otydligt (taligenkänning), gissa förnuftigt.
        Radera, flytta, byt namn på, skriv över eller skicka aldrig något, och köp eller betala aldrig något.
        Om uppgiften kräver det: gör inget och säg att användaren får göra just det själv.
        Läget just nu: appen längst fram är \(c.frontApp). "Här" betyder \(c.here) (\(c.hereReason)).
        \(c.recentProject.map { "Senaste projektet: \($0)." } ?? "")
        Avsluta med EN kort mening på svenska om vad du gjorde. Den läses upp: ingen markdown, inga sökvägar om det inte behövs.
        """
    }

    /// Kör uppgiften. Tar några sekunder; körs utanför huvudtråden.
    static func run(_ request: String, context c: Context, model: String) -> String {
        var args: [String] = [
            "-p", request,
            "--output-format", "text",
            "--model", model,
            "--append-system-prompt", systemPrompt(c),
            "--disallowedTools",
        ]
        args += disallowedTools
        args.append("--allowedTools")
        args += allowedTools
        let script = """
        export PATH="$HOME/.local/bin:$HOME/.claude/local:/opt/homebrew/bin:/usr/local/bin:$PATH"
        export NOTCHI_AGENT=1
        cd "$1" 2>/dev/null || cd "$HOME"
        shift
        exec claude "$@"
        """
        let out = LocalTools.run("/bin/zsh", ["-lc", script, "notchi", c.here] + args, timeout: 180)
        let text = out.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return "Det gick inte. Är Claude Code installerat och inloggat?" }
        // Bara sista stycket läses upp (själva sammanfattningen)
        let last = text.components(separatedBy: "\n\n").last ?? text
        return Brain.cleanForSpeech(String(last.prefix(400)))
    }
}
