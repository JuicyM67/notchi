import Foundation

/// Pratar med Claude API när en fråga inte kan hanteras lokalt.
/// Kostnadsknep: Haiku, korta svar, kort historik (bara text sparas), högst 1 webbsökning.
actor Brain {
    private var config: Config
    private var history: [[String: Any]] = []
    private let lastCwd: @Sendable () async -> String?

    init(config: Config, lastCwd: @escaping @Sendable () async -> String?) {
        self.config = config
        self.lastCwd = lastCwd
    }

    func update(config: Config) { self.config = config }
    func reset() { history.removeAll() }

    private var systemPrompt: String {
        """
        Du är Tamanotchi, en liten glad maskot som bor i notchen på användarens Mac och håller koll på Claude Code.
        Du svarar alltid på svenska, muntligt: 1–3 korta meningar, ingen markdown, inga listor, inga länkar, inga emojis.
        Siffror och förkortningar skrivs så att de låter bra uppläst.
        Använd verktygen för att öppna mappar, hitta filer, starta program, köra genvägar
        eller för att fråga Claude Code om kod i det aktuella projektet.
        Använd webbsökning bara när frågan gäller något aktuellt som du inte säkert vet.
        Om något kräver mer än ett kort svar: säg det kort och erbjud att öppna eller göra något.
        Dagens datum: \(Date().formatted(date: .complete, time: .omitted)).
        """
    }

    private var tools: [[String: Any]] {
        // Byggs i små steg så att kompilatorn inte kvävs av en jättelik literal
        func tool(_ name: String, _ description: String, _ params: [String], required: [String]) -> [String: Any] {
            var props: [String: Any] = [:]
            for p in params { props[p] = ["type": "string"] as [String: Any] }
            let schema: [String: Any] = ["type": "object", "properties": props, "required": required]
            return ["name": name, "description": description, "input_schema": schema]
        }
        var t: [[String: Any]] = []
        t.append(tool("open_folder", "Öppnar en mapp i Finder. Namn som 'Skrivbordet', 'Hämtade filer', en sökväg eller ett mappnamn att söka efter.", ["name"], required: ["name"]))
        t.append(tool("find_files", "Söker efter filer med Spotlight på filnamn och visar träffarna i Finder.", ["query"], required: ["query"]))
        t.append(tool("launch_app", "Startar ett program på Macen, t.ex. 'Safari', 'Spotify', 'Terminal'.", ["name"], required: ["name"]))
        t.append(tool("run_shortcut", "Kör en genväg från Genvägar-appen med exakt namn, valfritt med textinput.", ["name", "input"], required: ["name"]))
        t.append(tool("ask_claude_code", "Ställer en fråga till Claude Code i användarens senaste projektmapp (läser kod, förklarar, sammanfattar). Tar upp till några minuter.", ["prompt"], required: ["prompt"]))
        if config.webSearch {
            let location: [String: Any] = ["type": "approximate", "country": "SE", "timezone": "Europe/Stockholm"]
            let search: [String: Any] = ["type": "web_search_20250305", "name": "web_search",
                                         "max_uses": config.webSearchMaxUses, "user_location": location]
            t.append(search)
        }
        return t
    }

    /// Ställ en fråga, få tillbaka en text att läsa upp.
    /// `onProgress` används för korta mellanbesked ("Jag söker…").
    func ask(_ question: String, onProgress: @escaping @Sendable (String) async -> Void) async -> String {
        guard let key = config.resolvedAnthropicKey else {
            return "Jag saknar en API-nyckel. Lägg in den i punkt tamanotchi slash config punkt json."
        }
        var messages = Array(history.suffix(config.historyTurns))
        // Historiken måste börja med ett användarmeddelande
        while let first = messages.first, first["role"] as? String != "user" { messages.removeFirst() }
        messages.append(["role": "user", "content": question])

        for _ in 0..<6 {   // max antal verktygsvarv
            let body: [String: Any] = [
                "model": config.model,
                "max_tokens": config.maxTokens,
                "system": [["type": "text", "text": systemPrompt]],
                "tools": tools,
                "messages": messages,
            ]
            let response: [String: Any]
            do { response = try await post(body, key: key) }
            catch { return "Jag når inte Claude just nu." }

            if let err = response["error"] as? [String: Any] {
                return "Claude svarade med ett fel: \(err["message"] as? String ?? "okänt")."
            }
            let content = response["content"] as? [[String: Any]] ?? []
            let stop = response["stop_reason"] as? String ?? ""
            messages.append(["role": "assistant", "content": content])

            if stop == "pause_turn" { continue }   // server-verktyg (webbsökning) vill fortsätta

            if stop == "tool_use" {
                var results: [[String: Any]] = []
                for block in content where block["type"] as? String == "tool_use" {
                    let id = block["id"] as? String ?? ""
                    let name = block["name"] as? String ?? ""
                    let input = block["input"] as? [String: Any] ?? [:]
                    let output = await runTool(name, input, onProgress: onProgress)
                    results.append(["type": "tool_result", "tool_use_id": id, "content": output])
                }
                messages.append(["role": "user", "content": results])
                continue
            }

            // Klart: plocka ut texten
            let text = content.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }
                .joined(separator: " ")
            // Spara bara text i historiken (webbsökresultat är stora och kostar tokens nästa gång)
            history.append(["role": "user", "content": question])
            history.append(["role": "assistant", "content": text.isEmpty ? "…" : text])
            if history.count > 20 { history.removeFirst(history.count - 20) }
            return Self.cleanForSpeech(text)
        }
        return "Det där tog för många steg, jag gav upp."
    }

    private func runTool(_ name: String, _ input: [String: Any], onProgress: @escaping @Sendable (String) async -> Void) async -> String {
        let s = { (k: String) in input[k] as? String ?? "" }
        switch name {
        case "open_folder":
            let n = s("name"); return await Task.detached { LocalTools.openFolder(n) }.value
        case "find_files":
            let q = s("query")
            return await Task.detached {
                let r = LocalTools.findFiles(q)
                return r.summary + (r.paths.isEmpty ? "" : "\nSökvägar:\n" + r.paths.joined(separator: "\n"))
            }.value
        case "launch_app":
            let n = s("name"); return await Task.detached { LocalTools.launchApp(n) }.value
        case "run_shortcut":
            let n = s("name"), i = input["input"] as? String
            return await Task.detached { LocalTools.runShortcut(n, input: i) }.value
        case "ask_claude_code":
            await onProgress("Jag frågar Claude Code, det kan ta en stund.")
            let p = s("prompt"), cwd = await lastCwd()
            return await Task.detached { LocalTools.askClaudeCode(p, cwd: cwd) }.value
        default:
            return "Okänt verktyg."
        }
    }

    private func post(_ body: [String: Any], key: String) async throws -> [String: Any] {
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        req.httpMethod = "POST"
        req.timeoutInterval = 60
        req.setValue(key, forHTTPHeaderField: "x-api-key")
        req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await URLSession.shared.data(for: req)
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    /// Ta bort markdown och sånt som låter konstigt uppläst.
    static func cleanForSpeech(_ s: String) -> String {
        var t = s
        for pattern in [#"\*\*|__|`|#+\s"#, #"\[(.*?)\]\(.*?\)"#] {
            t = t.replacingOccurrences(of: pattern, with: pattern.contains("(.*?)") ? "$1" : "", options: .regularExpression)
        }
        t = t.replacingOccurrences(of: #"https?://\S+"#, with: "", options: .regularExpression)
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
