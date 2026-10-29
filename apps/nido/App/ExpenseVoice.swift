import AVFoundation
import Foundation
import Speech

@MainActor final class ExpenseVoiceDiagnostics: ObservableObject {
    static let shared = ExpenseVoiceDiagnostics()
    @Published private(set) var stage = "Sin iniciar"
    private let fileURL: URL

    private init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("expense-voice-diagnostics.log")
    }

    func record(_ event: String) {
        stage = event
        let line = "\(Date().formatted(.iso8601)) \(event)\n"
        let data = Data(line.utf8)
        let size = ((try? FileManager.default.attributesOfItem(atPath: fileURL.path))?[.size] as? NSNumber)?.intValue ?? 0
        if size > 65_536 { try? FileManager.default.removeItem(at: fileURL) }
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }
        if let handle = try? FileHandle(forWritingTo: fileURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        }
    }
}

@MainActor final class ExpenseSpeechRecognizer: ObservableObject {
    @Published var transcript = ""
    @Published var listening = false
    @Published var starting = false
    @Published var completedTranscript: String?
    @Published var finishedWithoutTranscript = false
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
        guard !listening, !finishing, !starting else { return }
        sessionID = UUID()
        let currentSession = sessionID
        starting = true
        defer { starting = false }
        transcript = ""
        completedTranscript = nil
        finishedWithoutTranscript = false
        errorMessage = nil
        ExpenseVoiceDiagnostics.shared.record("Dictado: solicitando permisos")
        let authorized = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in continuation.resume(returning: status == .authorized) }
        }
        guard sessionID == currentSession else { return }
        guard authorized, await AVAudioApplication.requestRecordPermission() else {
            errorMessage = "Permití micrófono y reconocimiento de voz en Configuración."
            ExpenseVoiceDiagnostics.shared.record("Dictado: permisos denegados")
            return
        }
        guard sessionID == currentSession else { return }
        guard let recognizer, recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else {
            errorMessage = "El dictado en español sin conexión no está disponible en este iPhone."
            ExpenseVoiceDiagnostics.shared.record("Dictado: reconocimiento local no disponible")
            return
        }
        do {
            finishing = false
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
            ExpenseVoiceDiagnostics.shared.record("Dictado: escuchando")
            task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor in
                    guard let self, self.sessionID == currentSession else { return }
                    if let result {
                        let next = result.bestTranscription.formattedString
                        if !next.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, self.transcript != next {
                            let firstWords = self.transcript.isEmpty
                            self.transcript = next
                            if firstWords { ExpenseVoiceDiagnostics.shared.record("Dictado: texto detectado") }
                            if !self.finishing { self.scheduleSilence(for: currentSession) }
                        }
                        if result.isFinal, next.isEmpty {
                            ExpenseVoiceDiagnostics.shared.record("Dictado: resultado final vacío; conservando texto parcial")
                        }
                    }
                    if result?.isFinal == true {
                        ExpenseVoiceDiagnostics.shared.record("Dictado: resultado final")
                        self.complete(for: currentSession)
                    }
                    else if let error {
                        if !self.finishing { self.errorMessage = error.localizedDescription }
                        ExpenseVoiceDiagnostics.shared.record("Dictado: error \(type(of: error))")
                        self.complete(for: currentSession)
                    }
                }
            }
        } catch {
            errorMessage = error.localizedDescription
            ExpenseVoiceDiagnostics.shared.record("Dictado: no inició audio \(type(of: error))")
            complete(for: sessionID)
        }
    }

    func stop() {
        finish()
    }

    func cancel() {
        sessionID = UUID()
        silenceTask?.cancel()
        finalizationTask?.cancel()
        if engine.isRunning { engine.stop(); engine.inputNode.removeTap(onBus: 0) }
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        transcript = ""
        completedTranscript = nil
        listening = false
        finishing = false
        try? AVAudioSession.sharedInstance().setActive(false)
        ExpenseVoiceDiagnostics.shared.record("Dictado: cancelado")
    }

    private func scheduleSilence(for id: UUID) {
        silenceTask?.cancel()
        silenceTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.2))
            guard !Task.isCancelled, sessionID == id, listening else { return }
            ExpenseVoiceDiagnostics.shared.record("Dictado: silencio detectado")
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
        ExpenseVoiceDiagnostics.shared.record("Dictado: esperando transcripción final")
        let id = sessionID
        finalizationTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled, sessionID == id else { return }
            ExpenseVoiceDiagnostics.shared.record("Dictado: finalización por tiempo")
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
            ExpenseVoiceDiagnostics.shared.record("Dictado: texto entregado (\(transcript.count) caracteres)")
        } else {
            if errorMessage == nil { finishedWithoutTranscript = true }
            ExpenseVoiceDiagnostics.shared.record("Dictado: sin texto utilizable")
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
