import Foundation

/// Inställningar läses från ~/.notchi/config.json (skapas med standardvärden första gången).
/// Allt är inställt för lägsta möjliga kostnad som standard:
///  - röst: macOS inbyggda talsyntes (gratis, lokalt)
///  - taligenkänning: Apples, på enheten när det stöds (gratis)
///  - enkla kommandon (öppna/starta/hitta/godkänn) hanteras lokalt utan API-anrop
///  - frågor går till Claude Haiku med korta svar och högst 1 webbsökning
struct Config: Codable {
    var anthropicApiKey: String? = nil
    var model: String = "claude-haiku-4-5-20251001"
    var maxTokens: Int = 350
    var webSearch: Bool = true
    var webSearchMaxUses: Int = 1
    var historyTurns: Int = 6            // hur många tidigare meddelanden som skickas med (fler = dyrare)

    var voice: String = "system"         // "system" (gratis) eller "elevenlabs"
    var systemVoiceIdentifier: String? = nil
    var speechRate: Float = 0.52
    var elevenLabsApiKey: String? = nil
    var elevenLabsVoiceId: String? = nil
    var elevenLabsModel: String = "eleven_flash_v2_5"

    var skin: String = "pim"             // pim | oda | bo | kix
    var speakEvents: Bool = true         // läs upp godkännanden/klart
    var voiceApprovals: Bool = true      // tillåt "ja"/"nej" med rösten (känsliga kommandon kräver alltid klick)
    var language: String = "sv-SE"
    var wakeWord: Bool = true            // lyssna efter "Hej Notchi" (på enheten, gratis)
    var usagePolling: Bool = true        // hämta användning var 5:e min (fungerar även i appen och VS Code)

    static let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".notchi")
    static let file = dir.appendingPathComponent("config.json")
    static let socketPath = dir.appendingPathComponent("notchi.sock").path

    static func load() -> Config {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: file),
           let cfg = try? JSONDecoder().decode(Config.self, from: data) {
            return cfg
        }
        let cfg = Config()
        if !FileManager.default.fileExists(atPath: file.path) {
            cfg.save()
        } else {
            print("⚠️ Kunde inte läsa \(file.path) – kolla JSON-syntaxen. Använder standardvärden tills vidare.")
        }
        return cfg
    }

    func save() {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(self) {
            try? data.write(to: Config.file, options: .atomic)
            // Filen kan innehålla API-nycklar: bara du ska kunna läsa den
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: Config.file.path)
        }
    }

    /// Nyckel från config, annars miljövariabeln ANTHROPIC_API_KEY.
    var resolvedAnthropicKey: String? {
        if let k = anthropicApiKey, !k.isEmpty { return k }
        return ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"]
    }
}

// Tillåt att config.json saknar fält (nya fält får standardvärden)
extension Config {
    init(from decoder: Decoder) throws {
        let d = Config()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        anthropicApiKey = try c.decodeIfPresent(String.self, forKey: .anthropicApiKey)
        model = try c.decodeIfPresent(String.self, forKey: .model) ?? d.model
        maxTokens = try c.decodeIfPresent(Int.self, forKey: .maxTokens) ?? d.maxTokens
        webSearch = try c.decodeIfPresent(Bool.self, forKey: .webSearch) ?? d.webSearch
        webSearchMaxUses = try c.decodeIfPresent(Int.self, forKey: .webSearchMaxUses) ?? d.webSearchMaxUses
        historyTurns = try c.decodeIfPresent(Int.self, forKey: .historyTurns) ?? d.historyTurns
        voice = try c.decodeIfPresent(String.self, forKey: .voice) ?? d.voice
        systemVoiceIdentifier = try c.decodeIfPresent(String.self, forKey: .systemVoiceIdentifier)
        speechRate = try c.decodeIfPresent(Float.self, forKey: .speechRate) ?? d.speechRate
        elevenLabsApiKey = try c.decodeIfPresent(String.self, forKey: .elevenLabsApiKey)
        elevenLabsVoiceId = try c.decodeIfPresent(String.self, forKey: .elevenLabsVoiceId)
        elevenLabsModel = try c.decodeIfPresent(String.self, forKey: .elevenLabsModel) ?? d.elevenLabsModel
        skin = try c.decodeIfPresent(String.self, forKey: .skin) ?? d.skin
        speakEvents = try c.decodeIfPresent(Bool.self, forKey: .speakEvents) ?? d.speakEvents
        voiceApprovals = try c.decodeIfPresent(Bool.self, forKey: .voiceApprovals) ?? d.voiceApprovals
        language = try c.decodeIfPresent(String.self, forKey: .language) ?? d.language
        usagePolling = try c.decodeIfPresent(Bool.self, forKey: .usagePolling) ?? d.usagePolling
        wakeWord = try c.decodeIfPresent(Bool.self, forKey: .wakeWord) ?? d.wakeWord
    }
}
