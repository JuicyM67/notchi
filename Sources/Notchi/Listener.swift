import Foundation
import Speech
import AVFoundation

/// Tryck-och-håll-för-att-prata. Använder Apples taligenkänning (gratis),
/// och kör helt på enheten när datorn stödjer det för språket.
@MainActor
final class Listener {
    private let recognizer: SFSpeechRecognizer?
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var latest = ""
    var onPartial: ((String) -> Void)?
    var onLevel: ((Float) -> Void)?

    init(language: String) {
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: language))
    }

    static func requestPermissions() {
        SFSpeechRecognizer.requestAuthorization { _ in }
        AVCaptureDevice.requestAccess(for: .audio) { _ in }
    }

    func start() {
        guard let recognizer, recognizer.isAvailable else {
            onPartial?("Taligenkänning är inte tillgänglig.")
            return
        }
        stopEngine()
        latest = ""
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition {
            req.requiresOnDeviceRecognition = true   // gratis + privat
        }
        request = req

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            req.append(buffer)
            // Enkel ljudnivå till maskoten (visar att den hör dig)
            if let ch = buffer.floatChannelData?[0] {
                let n = Int(buffer.frameLength)
                var sum: Float = 0
                for i in 0..<n { sum += ch[i] * ch[i] }
                let rms = sqrt(sum / Float(max(n, 1)))
                let level = min(1, rms * 12)
                Task { @MainActor in self?.onLevel?(level) }
            }
        }
        engine.prepare()
        do { try engine.start() } catch {
            onPartial?("Kunde inte starta mikrofonen.")
            return
        }
        task = recognizer.recognitionTask(with: req) { [weak self] result, _ in
            guard let text = result?.bestTranscription.formattedString else { return }
            Task { @MainActor in
                self?.latest = text
                self?.onPartial?(text)
            }
        }
    }

    /// Släpp tangenten: vänta en kort stund på sista resultatet och returnera texten.
    func finish() async -> String {
        request?.endAudio()
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        try? await Task.sleep(nanoseconds: 450_000_000)
        task?.cancel()
        task = nil; request = nil
        onLevel?(0)
        return latest.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func stopEngine() {
        if engine.isRunning {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        task?.cancel(); task = nil
    }
}
