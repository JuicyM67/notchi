import Foundation

/// Hämtar Claude-användningen (5 timmar / vecka) direkt, med Claude Codes egen inloggning.
///
/// Varför: statusraden – den dokumenterade vägen – körs bara i Claude Code i Terminal.
/// Jobbar du i Claude-appen eller VS Code kommer inga siffror den vägen. Det här är
/// samma interna anrop som Claude Code själv använder för /usage. Det är inte
/// dokumenterat och kan ändras; slutar det fungera tystnar det bara, och statusraden
/// fortsätter som förut.
///
/// Snällt mot servern: var 5:e minut, och 15 minuters paus om servern säger "för många".
/// Stängs av med "usagePolling": false i ~/.notchi/config.json.
actor UsagePoller {
    private var backoffUntil: Date?
    private var lastFailure: String?

    struct Result { let fiveHour: Double?; let fiveReset: Date?; let sevenDay: Double?; let sevenReset: Date? }

    func fetch() async -> Result? {
        if let b = backoffUntil, b > Date() { return nil }
        guard let token = Self.readToken() else { lastFailure = "ingen inloggning"; return nil }

        var req = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        req.timeoutInterval = 15
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("notchi/0.1", forHTTPHeaderField: "User-Agent")

        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse else { return nil }
        switch http.statusCode {
        case 200: break
        case 429:
            backoffUntil = Date().addingTimeInterval(15 * 60); return nil
        default:
            // 401 = token utgången; Claude Code förnyar den själv nästa gång du använder det
            backoffUntil = Date().addingTimeInterval(5 * 60); return nil
        }
        guard let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

        func window(_ key: String) -> (Double?, Date?) {
            guard let w = j[key] as? [String: Any] else { return (nil, nil) }
            let pct = (w["utilization"] as? NSNumber)?.doubleValue
            return (pct, Self.parseDate(w["resets_at"]))
        }
        let (f, fr) = window("five_hour")
        let (s, sr) = window("seven_day")
        if f == nil && s == nil { return nil }
        return Result(fiveHour: f, fiveReset: fr, sevenDay: s, sevenReset: sr)
    }

    /// Claude Codes inloggning ligger i Nyckelhanden. Första gången frågar macOS om lov
    /// – välj "Tillåt alltid" så frågar den inte igen.
    static func readToken() -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        p.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0,
              let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = j["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String, !token.isEmpty else { return nil }
        // Utgången token: hoppa över (Claude Code förnyar den när du använder det)
        if let exp = (oauth["expiresAt"] as? NSNumber)?.doubleValue,
           Date(timeIntervalSince1970: exp / 1000) < Date() { return nil }
        return token
    }

    static func parseDate(_ v: Any?) -> Date? {
        if let n = v as? NSNumber { return Date(timeIntervalSince1970: n.doubleValue) }
        guard let s = v as? String else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        if let d = f.date(from: s) { return d }
        // "2025-11-04T04:59:59.943648+00:00" har 6 decimaler; korta till 3
        let trimmed = s.replacingOccurrences(of: #"(\.\d{3})\d+"#, with: "$1", options: .regularExpression)
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: trimmed)
    }
}
