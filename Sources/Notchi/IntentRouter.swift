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
    case stopTalking
    case askClaude(String)        // allt annat
}

enum IntentRouter {
    static func parse(_ raw: String, hasPending: Bool) -> LocalIntent {
        let t = raw.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".!?"))

        if hasPending {
            if match(t, #"^(ja|japp|jajamän|godkänn|godkänt|kör|kör på|okej|ok|tillåt|visst|absolut)( det| tack)?$"#) { return .approve }
            if match(t, #"^(nej|neka|stopp|stoppa|avbryt|nix|vänta)( det| tack)?$"#) { return .deny }
        }
        if match(t, #"^(tyst|sluta prata|shh+|var tyst)"#) { return .stopTalking }
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
