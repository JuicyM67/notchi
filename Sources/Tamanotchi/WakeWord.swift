import Foundation
import Speech
import AVFoundation

/// "Hej Tamanotchi": lyssnar efter väckningsordet hela tiden, helt på enheten (gratis, inget lämnar datorn).
///
/// - Kräver att Macen kan känna igen svenska på enheten. Annars startar den inte alls,
///   eftersom ljudet då skulle skickas till Apple hela tiden.
/// - Pausar när Tamanotchi själv pratar (så den inte hör sig själv) och när du håller snabbtangenten.
/// - Efter väckningsordet: det du säger fram till en kort tystnad blir kommandot.
///   "Hej Tamanotchi, öppna hämtade filer" fungerar i ett andetag.
/// - Mikrofonlampan (orange prick) lyser medan den lyssnar. Stäng av i menyn om du inte vill det.
@MainActor
final class WakeWord {
    private let recognizer: SFSpeechRecognizer?
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var generation = 0                 // ignorera svar från gamla igenkänningar
    private var enabled = false
    /// Varför den är pausad just nu (flera skäl kan gälla samtidigt)
    enum PauseReason: Hashable { case speaking, hotkey, command }
    private var pausedFor: Set<PauseReason> = []
    private var awake = false
    private var wakeEndOffset = 0              // antal tecken fram till och med "Tamanotchi"
    private var latest = ""
    private var lastChange = Date()
    private var wokeAt = Date()
    private var restartTimer: Timer?
    private var silenceTimer: Timer?

    var onWake: (() -> Void)?
    var onPartial: ((String) -> Void)?
    var onCommand: ((String) -> Void)?

    init(language: String) {
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: language))
    }

    /// Kan vi lyssna utan att skicka ljud från datorn?
    var supported: Bool { recognizer?.supportsOnDeviceRecognition == true }
    var isRunning: Bool { enabled && pausedFor.isEmpty && task != nil }

    func setEnabled(_ on: Bool) {
        enabled = on
        on ? begin() : teardown()
    }

    func pause(_ reason: PauseReason) {
        let wasRunning = pausedFor.isEmpty
        pausedFor.insert(reason)
        if wasRunning {
            if awake { awake = false; silenceTimer?.invalidate() }
            teardown()
        }
    }

    func resume(_ reason: PauseReason) {
        guard pausedFor.remove(reason) != nil else { return }
        if pausedFor.isEmpty { begin() }
    }

    // MARK: -

    private func begin() {
        guard enabled, pausedFor.isEmpty else { return }
        guard SFSpeechRecognizer.authorizationStatus() == .authorized,
              AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            // Behörighet inte given än: försök igen om en stund
            restartTimer?.invalidate()
            restartTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.begin() }
            }
            return
        }
        guard let recognizer, recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else { return }
        teardown()

        awake = false
        latest = ""
        generation += 1
        let gen = generation

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.requiresOnDeviceRecognition = true
        req.contextualStrings = ["Tamanotchi", "hej Tamanotchi", "hallå Tamanotchi", "Notchi"]
        request = req

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else { return }
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { buffer, _ in
            req.append(buffer)
        }
        engine.prepare()
        do { try engine.start() } catch { teardown(); return }

        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let done = (result?.isFinal ?? false) || error != nil
            Task { @MainActor in self?.handle(text, done: done, gen: gen) }
        }

        // Apple avbryter en igenkänning efter ungefär en minut: börja om lite innan
        restartTimer?.invalidate()
        restartTimer = Timer.scheduledTimer(withTimeInterval: 50, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.awake, gen == self.generation else { return }
                self.begin()
            }
        }
    }

    private func teardown() {
        restartTimer?.invalidate(); restartTimer = nil
        silenceTimer?.invalidate(); silenceTimer = nil
        generation += 1
        task?.cancel(); task = nil
        request?.endAudio(); request = nil
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
    }

    private func handle(_ text: String?, done: Bool, gen: Int) {
        guard gen == generation, enabled, pausedFor.isEmpty else { return }
        if let text {
            if !awake {
                if let end = Self.wakeEnd(in: text) {
                    awake = true
                    wakeEndOffset = end
                    wokeAt = Date()
                    lastChange = Date()
                    onWake?()
                    startSilenceWatch()
                }
            } else if text != latest {
                lastChange = Date()
                onPartial?(command(from: text))
            }
            latest = text
        }
        if done {
            if awake { finish() } else { begin() }
        }
    }

    private func startSilenceWatch() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.awake else { return }
                let quiet = Date().timeIntervalSince(self.lastChange)
                let hasWords = !self.command(from: self.latest).isEmpty
                let total = Date().timeIntervalSince(self.wokeAt)
                // Klart när du tystnat en stund; vänta lite längre om du inte sagt något än
                if (hasWords && quiet > 1.3) || (!hasWords && quiet > 4) || total > 15 {
                    self.finish()
                }
            }
        }
    }

    private func finish() {
        guard awake else { return }
        awake = false
        let cmd = command(from: latest)
        pausedFor.insert(.command)   // håll tyst tills appen är klar: den anropar resume(.command)
        teardown()
        onCommand?(cmd)
    }

    private func command(from text: String) -> String {
        guard text.count > wakeEndOffset else { return "" }
        let rest = text.dropFirst(wakeEndOffset)
        return rest.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
    }

    /// Var slutar väckningsordet? Taligenkänningen stavar "Tamanotchi" på många sätt.
    static func wakeEnd(in text: String) -> Int? {
        let pattern = #"(?i)\b(hej|hey|hallå|tja|hejsan)[\s,!.]+(?:tama[\s-]?)?([gn][oåa]h?t?[cst]?[hj]?[iy]e?|notch(?:\s?i)?|gotchi|nachi|natchi|notschi|nåtschi|notji|nottji)\b"#
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let r = Range(m.range, in: text) else { return nil }
        return text.distance(from: text.startIndex, to: r.upperBound)
    }
}
