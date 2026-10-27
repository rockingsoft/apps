import AVFoundation
import Foundation
import Speech

@MainActor final class ExpenseSpeechRecognizer: ObservableObject {
    @Published var transcript = ""
    @Published var listening = false
    @Published var errorMessage: String?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "es-AR"))
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    func start() async {
        guard !listening else { return }
        let authorized = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in continuation.resume(returning: status == .authorized) }
        }
        guard authorized, await AVAudioApplication.requestRecordPermission() else {
            errorMessage = "Permití micrófono y reconocimiento de voz en Configuración."
            return
        }
        guard let recognizer, recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else {
            errorMessage = "El dictado en español sin conexión no está disponible en este iPhone."
            return
        }
        do {
            transcript = ""
            errorMessage = nil
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.requiresOnDeviceRecognition = true
            request.shouldReportPartialResults = true
            self.request = request
            try AVAudioSession.sharedInstance().setCategory(.record, mode: .measurement, options: .duckOthers)
            try AVAudioSession.sharedInstance().setActive(true)
            let input = engine.inputNode
            input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buffer, _ in
                request.append(buffer)
            }
            engine.prepare()
            try engine.start()
            listening = true
            task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor in
                    if let result { self?.transcript = result.bestTranscription.formattedString }
                    if let error { self?.errorMessage = error.localizedDescription; self?.stop() }
                    else if result?.isFinal == true { self?.stop() }
                }
            }
        } catch {
            errorMessage = error.localizedDescription
            stop()
        }
    }

    func stop() {
        if engine.isRunning { engine.stop(); engine.inputNode.removeTap(onBus: 0) }
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        listening = false
        try? AVAudioSession.sharedInstance().setActive(false)
    }
}

struct ExpenseInterpretation: Decodable {
    let amount: Decimal?
    let category: String?
    let paidBy: String?
    let detail: String?
    let date: String?
}
