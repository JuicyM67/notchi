import Foundation

/// Tolkar enkla svenska röstkommandon lokalt — utan att fråga Claude.
/// Det här är den största kostnadsbesparingen: vardagskommandon kostar 0 kr.
enum LocalIntent {
    case approve, deny
    case openFolder(String)
    case launchApp(String)
    case openAny(String)          // "öppna X" — program om det finns, annars mapp
    case findFile(String)
    case runShortcut(String)
    case status
    case usage
    case media(LocalTools.Media)
    case stopTalking
    case askClaude(String)        // allt annat
}

enum IntentRouter {
    /// "Öppna Spotify och spela musik" → flera lokala steg, om ALLA delar går att göra lokalt.
    /// Annars nil: då får Claude Code ta hela meningen.
    static func steps(_ raw: String) -> [String] {
        raw.lowercased()
            .replacingOccurrences(of: #"\s*(,\s*)?\b(och sen|och sedan|och|sen|sedan|därefter)\b\s*"#, with: "|", options: .regularExpression)
            .split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// Innehåller meningen flera steg? ("öppna X och gör Y")
    static func isMultiStep(_ raw: String) -> Bool { steps(raw).count > 1 }

    static func chain(_ raw: String) -> [LocalIntent]? {
        let parts = raw.lowercased()
            .replacingOccurrences(of: #"\s*(,\s*)?\b(och sen|och sedan|och|sen|sedan|därefter)\b\s*"#, with: "|", options: .regularExpression)
            .split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard parts.count > 1 else { return nil }
        var out: [LocalIntent] = []
        for p in parts {
            let i = parse(p, hasPending: false)
            switch i {
            case .askClaude, .approve, .deny, .stopTalking: return nil
            default: out.append(i)
            }
        }
        return out
    }

    static func parse(_ raw: String, hasPending: Bool) -> LocalIntent {
        let t = raw.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".!?"))

        if hasPending {
            if match(t, #"^(ja|japp|jajamän|godkänn|godkänt|kör|kör på|okej|ok|tillåt|visst|absolut)( det| tack)?$"#) { return .approve }
            if match(t, #"^(nej|neka|stopp|stoppa|avbryt|nix|vänta)( det| tack)?$"#) { return .deny }
        }
        if match(t, #"^(tyst|sluta prata|shh+|var tyst)"#) { return .stopTalking }

        // Musik: bara korta, entydiga kommandon. "Spela X" (en viss låt) går till Claude Code.
        if match(t, #"^(spela musik|spela upp musik|sätt på musik(en)?|starta musik(en)?|spela|play|fortsätt spela)$"#) { return .media(.play) }
        if match(t, #"^(pausa|paus|pausa musik(en)?|stoppa musik(en)?|stäng av musik(en)?)$"#) { return .media(.pause) }
        if match(t, #"^(nästa|nästa låt|hoppa över|skippa)( låt(en)?)?$"#) { return .media(.next) }
        if match(t, #"^(förra|förra låten|föregående( låt)?|tillbaka en låt)$"#) { return .media(.previous) }
        if match(t, #"(användning|hur mycket (har jag )?(kvar|använt)|gräns|usage)"#) { return .usage }
        if match(t, #"(vad gör (claude|du)|hur går det|status|vad händer)"#) { return .status }

        if let x = capture(t, #"^(?:öppna|visa) (?:mappen|katalogen) (.+)$"#) { return .openFolder(x) }
        if let x = capture(t, #"^(?:öppna|visa) (.+?)(?:-| )?mappen$"#) { return .openFolder(x) }
        if let x = capture(t, #"^(?:starta|kör igång|öppna (?:programmet|appen)) (.+)$"#) { return .launchApp(x) }
        if let x = capture(t, #"^(?:hitta|leta upp|leta efter|sök efter|var är|var ligger) (?:filen |filerna |dokumentet )?(.+)$"#) {
            // "sök efter" följt av typiska frågeord är nog en webbfråga, inte en fil
            if !match(x, #"^(nyheter|vädret|hur|vad|vem|när|varför)"#) { return .findFile(x) }
        }
        if let x = capture(t, #"^kör genvägen (.+)$"#) { return .runShortcut(x) }
        if let x = capture(t, #"^öppna (.+)$"#) { return .openAny(x) }

        return .askClaude(raw)
    }

    private static func match(_ s: String, _ pattern: String) -> Bool {
        s.range(of: pattern, options: .regularExpression) != nil
    }

    private static func capture(_ s: String, _ pattern: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
              m.numberOfRanges > 1, let r = Range(m.range(at: 1), in: s) else { return nil }
        let v = s[r].trimmingCharacters(in: .whitespaces)
        return v.isEmpty ? nil : v
    }
}
