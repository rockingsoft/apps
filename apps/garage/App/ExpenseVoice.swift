import AVFoundation
import Foundation
import Speech

@MainActor final class ExpenseSpeechRecognizer: ObservableObject {
    @Published var transcript = ""
    @Published var listening = false
    @Published var completedTranscript: String?
    @Published var errorMessage: String?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "es-AR"))
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var silenceTask: Task<Void, Never>?
    private var finalizationTask: Task<Void, Never>?
    private var sessionID = UUID()
    private var finishing = false

    func start() async {
        guard !listening, !finishing else { return }
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
            sessionID = UUID()
            let currentSession = sessionID
            transcript = ""
            completedTranscript = nil
            finishing = false
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
                    guard let self, self.sessionID == currentSession else { return }
                    if let result {
                        let next = result.bestTranscription.formattedString
                        if self.transcript != next {
                            self.transcript = next
                            if !self.finishing { self.scheduleSilence(for: currentSession) }
                        }
                    }
                    if result?.isFinal == true { self.complete(for: currentSession) }
                    else if let error {
                        if !self.finishing { self.errorMessage = error.localizedDescription }
                        self.complete(for: currentSession)
                    }
                }
            }
        } catch {
            errorMessage = error.localizedDescription
            complete(for: sessionID)
        }
    }

    func stop() {
        finish()
    }

    private func scheduleSilence(for id: UUID) {
        silenceTask?.cancel()
        silenceTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.2))
            guard !Task.isCancelled, sessionID == id, listening else { return }
            finish()
        }
    }

    private func finish() {
        guard listening, !finishing else { return }
        finishing = true
        silenceTask?.cancel()
        if engine.isRunning { engine.stop(); engine.inputNode.removeTap(onBus: 0) }
        request?.endAudio()
        listening = false
        let id = sessionID
        finalizationTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled, sessionID == id else { return }
            complete(for: id)
        }
    }

    private func complete(for id: UUID) {
        guard sessionID == id else { return }
        sessionID = UUID()
        silenceTask?.cancel()
        finalizationTask?.cancel()
        if engine.isRunning { engine.stop(); engine.inputNode.removeTap(onBus: 0) }
        task?.cancel()
        request = nil
        task = nil
        listening = false
        finishing = false
        try? AVAudioSession.sharedInstance().setActive(false)
        if errorMessage == nil, !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            completedTranscript = transcript
        }
    }
}

struct ExpenseInterpretation: Decodable {
    let amount: Decimal?
    let category: String?
    let paidBy: String?
    let detail: String?
    let date: String?
}
