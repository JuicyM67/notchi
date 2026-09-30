import Foundation
import AVFoundation

/// Gemensamt gränssnitt för röster. `level` (0–1) driver maskotens mun.
@MainActor
protocol Speaker: AnyObject {
    var onLevel: ((Float) -> Void)? { get set }
    var onFinished: (() -> Void)? { get set }
    func speak(_ text: String)
    func stop()
}

// MARK: - Gratis: macOS inbyggda talsyntes

@MainActor
final class SystemSpeaker: NSObject, Speaker, AVSpeechSynthesizerDelegate {
    private let synth = AVSpeechSynthesizer()
    private var voice: AVSpeechSynthesisVoice?
    private var rate: Float
    private var timer: Timer?
    private var phase: Float = 0
    var onLevel: ((Float) -> Void)?
    var onFinished: (() -> Void)?

    init(language: String, identifier: String?, rate: Float) {
        self.rate = rate
        super.init()
        synth.delegate = self
        if let id = identifier, let v = AVSpeechSynthesisVoice(identifier: id) {
            voice = v
        } else {
            // Välj bästa svenska rösten som finns installerad (premium > förbättrad > standard).
            // Tips: Systeminställningar → Hjälpmedel → Talat innehåll → Systemröst → Hantera röster → Svenska → Alva (Premium)
            voice = AVSpeechSynthesisVoice.speechVoices()
                .filter { $0.language == language }
                .max(by: { $0.quality.rawValue < $1.quality.rawValue })
                ?? AVSpeechSynthesisVoice(language: language)
        }
    }

    func speak(_ text: String) {
        stop()
        let u = AVSpeechUtterance(string: text)
        u.voice = voice
        u.rate = rate
        u.pitchMultiplier = 1.15   // lite ljusare = gladare maskot
        synth.speak(u)
        startFakeLevel()
    }

    func stop() {
        synth.stopSpeaking(at: .immediate)
        stopFakeLevel()
    }

    /// Systemrösten ger ingen ljudnivå, så munnen animeras med en mjuk pseudo-slumpkurva.
    private func startFakeLevel() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.phase += 0.35
                let t = self.phase
                let v = 0.35 + 0.3 * sin(t) * sin(t * 0.37) + Float.random(in: 0...0.25)
                self.onLevel?(max(0, min(1, v)))
            }
        }
    }
    private func stopFakeLevel() {
        timer?.invalidate(); timer = nil
        onLevel?(0)
    }

    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish u: AVSpeechUtterance) {
        Task { @MainActor in self.stopFakeLevel(); self.onFinished?() }
    }
    nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, willSpeakRangeOfSpeechString r: NSRange, utterance u: AVSpeechUtterance) {
        // Ett ord börjar: liten extra munrörelse
        Task { @MainActor in self.onLevel?(0.9) }
    }
}

// MARK: - Betald, bättre kvalitet: ElevenLabs

@MainActor
final class ElevenLabsSpeaker: NSObject, Speaker, AVAudioPlayerDelegate {
    private let apiKey: String
    private let voiceId: String
    private let model: String
    private var player: AVAudioPlayer?
    private var meter: Timer?
    private var task: Task<Void, Never>?
    private let fallback: SystemSpeaker
    var onLevel: ((Float) -> Void)?
    var onFinished: (() -> Void)?

    init(apiKey: String, voiceId: String, model: String, fallback: SystemSpeaker) {
        self.apiKey = apiKey; self.voiceId = voiceId; self.model = model; self.fallback = fallback
    }

    func speak(_ text: String) {
        stop()
        task = Task { [weak self] in
            guard let self else { return }
            do {
                var req = URLRequest(url: URL(string: "https://api.elevenlabs.io/v1/text-to-speech/\(voiceId)")!)
                req.httpMethod = "POST"
                req.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
                req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                req.setValue("audio/mpeg", forHTTPHeaderField: "Accept")
                req.httpBody = try JSONSerialization.data(withJSONObject: ["text": text, "model_id": model])
                let (data, resp) = try await URLSession.shared.data(for: req)
                guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
                if Task.isCancelled { return }
                try self.play(data)
            } catch {
                if Task.isCancelled { return }
                // Nätfel eller slut på krediter: fall tillbaka på gratisrösten
                self.fallback.onLevel = self.onLevel
                self.fallback.onFinished = self.onFinished
                self.fallback.speak(text)
            }
        }
    }

    private func play(_ data: Data) throws {
        let p = try AVAudioPlayer(data: data)
        p.delegate = self
        p.isMeteringEnabled = true
        player = p
        p.play()
        meter = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let p = self.player else { return }
                p.updateMeters()
                let db = p.averagePower(forChannel: 0)          // ca -60…0 dB
                self.onLevel?(max(0, min(1, (db + 50) / 40)))
            }
        }
    }

    func stop() {
        task?.cancel()
        player?.stop(); player = nil
        meter?.invalidate(); meter = nil
        fallback.stop()
        onLevel?(0)
    }

    nonisolated func audioPlayerDidFinishPlaying(_ p: AVAudioPlayer, successfully: Bool) {
        Task { @MainActor in
            self.meter?.invalidate(); self.meter = nil
            self.onLevel?(0)
            self.onFinished?()
        }
    }
}
