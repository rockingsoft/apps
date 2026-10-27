import AVFoundation
import Foundation
import llama
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

enum ExpenseModelError: LocalizedError {
    case invalidResult, modelUnavailable, modelLoadFailed
    var errorDescription: String? {
        switch self {
        case .invalidResult: return "La IA no pudo interpretar el gasto. Probá decirlo de otra forma."
        case .modelUnavailable: return "Esta versión de Garage no incluye el modelo de IA. Reinstalá la app."
        case .modelLoadFailed: return "Este iPhone no pudo abrir el modelo de IA."
        }
    }
}

enum ExpenseModel {
    static let fileName = "qwen2.5-1.5b-instruct-q4_k_m.gguf"
    static var fileURL: URL? { Bundle.main.url(forResource: "qwen2.5-1.5b-instruct-q4_k_m", withExtension: "gguf") }
    private static let inferenceLock = NSLock()
    private static var cachedModel: OpaquePointer?
    private static var cachedContext: OpaquePointer?

    static func prepare() async {
        _ = try? await Task.detached(priority: .utility) { try loadIfNeeded() }.value
    }

    static func interpret(_ transcript: String) async throws -> ExpenseInterpretation {
        guard fileURL != nil else { throw ExpenseModelError.modelUnavailable }
        let result = try await Task.detached(priority: .userInitiated) { try generate(transcript) }.value
        guard let start = result.firstIndex(of: "{"), let end = result.lastIndex(of: "}"),
              let data = String(result[start...end]).data(using: .utf8),
              let interpretation = try? JSONDecoder().decode(ExpenseInterpretation.self, from: data) else {
            throw ExpenseModelError.invalidResult
        }
        return interpretation
    }

    private static func generate(_ transcript: String) throws -> String {
        inferenceLock.lock()
        defer { inferenceLock.unlock() }
        try loadIfNeededLocked()
        guard let model = cachedModel, let context = cachedContext else { throw ExpenseModelError.modelLoadFailed }
        llama_memory_clear(llama_get_memory(context), true)
        let vocab = llama_model_get_vocab(model)
        let categories = FamilyBudget.categories.joined(separator: ", ")
        let todayFormatter = DateFormatter()
        todayFormatter.timeZone = FamilyBudget.calendar.timeZone
        todayFormatter.dateFormat = "yyyy-MM-dd"
        let today = todayFormatter.string(from: .now)
        let yesterday = todayFormatter.string(from: FamilyBudget.calendar.date(byAdding: .day, value: -1, to: .now) ?? .now)
        let prompt = """
        <|im_start|>system
        Extraé un gasto familiar argentino. Hoy es \(today). Respondé SOLO un objeto JSON con estas claves exactas: amount (número en pesos), category, paidBy, detail y date (AAAA-MM-DD o null si no se mencionó fecha). "mil" y "lucas" significan multiplicar por 1000. Usá null si falta un dato. Categorías válidas: \(categories). Pagadores válidos: Sebastián, Misha, Común. Mapa: nafta/combustible/service/mecánico -> Auto; supermercado/comida para casa -> Super; farmacia/medicamentos/prepaga -> Prepaga; bar/restaurante/café -> Salidas; colegio/cuota escolar -> Colegio. Si el pagador no aparece explícito, paidBy=null. Para 72 mil el amount es 72000. No inventes importes ni pagadores. Conservá el comercio o motivo en detail. Sin markdown ni explicación.
        Ejemplos:
        "Pagué 18 lucas de nafta en Shell" -> {"amount":18000,"category":"Auto","paidBy":null,"detail":"Nafta en Shell","date":null}
        "Gasté 32 mil en la farmacia, pagó Misha" -> {"amount":32000,"category":"Prepaga","paidBy":"Misha","detail":"Farmacia","date":null}
        "Sebastián pagó 12500 en el supermercado ayer" -> {"amount":12500,"category":"Super","paidBy":"Sebastián","detail":"Supermercado","date":"\(yesterday)"}
        <|im_end|>
        <|im_start|>user
        \(transcript)
        <|im_end|>
        <|im_start|>assistant
        """
        var tokens = [llama_token](repeating: 0, count: prompt.utf8.count + 1)
        let count = llama_tokenize(vocab, prompt, Int32(prompt.utf8.count), &tokens, Int32(tokens.count), true, true)
        guard count > 0, count < 900 else { throw ExpenseModelError.invalidResult }
        var batch = llama_batch_init(1024, 0, 1)
        defer { llama_batch_free(batch) }
        batch.n_tokens = count
        for index in 0..<Int(count) {
            batch.token[index] = tokens[index]
            batch.pos[index] = Int32(index)
            batch.n_seq_id[index] = 1
            batch.seq_id[index]?[0] = 0
            batch.logits[index] = index == Int(count) - 1 ? 1 : 0
        }
        guard llama_decode(context, batch) == 0 else { throw ExpenseModelError.invalidResult }
        var output = Data()
        var position = count
        for _ in 0..<112 {
            guard let logits = llama_get_logits_ith(context, batch.n_tokens - 1) else { break }
            let vocabularySize = Int(llama_vocab_n_tokens(vocab))
            var best = 0
            for candidate in 1..<vocabularySize where logits[candidate] > logits[best] { best = candidate }
            let next = llama_token(best)
            if next == llama_vocab_eos(vocab) { break }
            var buffer = [CChar](repeating: 0, count: 256)
            let length = llama_token_to_piece(vocab, next, &buffer, Int32(buffer.count), 0, false)
            if length > 0 { output.append(contentsOf: buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }) }
            if let text = String(data: output, encoding: .utf8),
               let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"),
               let data = String(text[start...end]).data(using: .utf8),
               (try? JSONDecoder().decode(ExpenseInterpretation.self, from: data)) != nil { break }
            batch.n_tokens = 1
            batch.token[0] = next
            batch.pos[0] = position
            batch.n_seq_id[0] = 1
            batch.seq_id[0]?[0] = 0
            batch.logits[0] = 1
            position += 1
            guard llama_decode(context, batch) == 0 else { break }
        }
        return String(data: output, encoding: .utf8) ?? ""
    }

    private static func loadIfNeeded() throws {
        inferenceLock.lock()
        defer { inferenceLock.unlock() }
        try loadIfNeededLocked()
    }

    private static func loadIfNeededLocked() throws {
        guard cachedContext == nil else { return }
        guard let fileURL else { throw ExpenseModelError.modelUnavailable }
        llama_backend_init()
        var modelParams = llama_model_default_params()
        modelParams.n_gpu_layers = 99
        guard let model = llama_model_load_from_file(fileURL.path, modelParams) else { throw ExpenseModelError.modelLoadFailed }
        var contextParams = llama_context_default_params()
        contextParams.n_ctx = 1024
        contextParams.n_batch = 1024
        guard let context = llama_init_from_model(model, contextParams) else {
            llama_model_free(model)
            throw ExpenseModelError.modelLoadFailed
        }
        cachedModel = model
        cachedContext = context
    }
}
