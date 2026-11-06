import SwiftUI

struct QuickExpenseVoiceView: View {
    @EnvironmentObject private var finances: FinanceStore
    @EnvironmentObject private var chatGPT: ChatGPTExpense
    @EnvironmentObject private var cars: CloudStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var speech = ExpenseSpeechRecognizer()
    @State private var phase: VoiceFlowPhase = .listening
    @State private var started = false
    @State private var handlingTranscript = false
    @State private var interpretationTask: Task<Void, Never>?

    var body: some View {
        ExpenseVoiceFlowView(speech: speech, phase: $phase, onCancel: cancel,
                             onRetry: retry, automaticSave: true)
            .task { if finances.restored { await start() } }
            .onChange(of: finances.restored) { _, ready in
                if ready { Task { await start() } }
            }
            .onReceive(speech.$completedTranscript.compactMap { $0 }) { transcript in
                guard !handlingTranscript else { return }
                handlingTranscript = true
                phase = .processing
                interpretationTask = Task { await register(transcript) }
            }
            .onChange(of: speech.errorMessage) { _, message in
                if let message { phase = .failed(message) }
            }
            .onChange(of: speech.finishedWithoutTranscript) { _, finished in
                if finished { phase = .failed("No llegué a escuchar un gasto. Probá otra vez.") }
            }
            .onChange(of: speech.listening) { _, listening in
                if !listening, !speech.transcript.isEmpty, !handlingTranscript { phase = .processing }
            }
            .onDisappear {
                speech.cancel()
                // Once queued, allow the existing durable write to finish.
                if case .saving = phase {} else { interpretationTask?.cancel() }
            }
            .interactiveDismissDisabled()
    }

    private func start() async {
        guard !started else { return }
        started = true
        guard chatGPT.connected else {
            phase = .failed("Conectá ChatGPT desde el menú de Inicio y volvé a intentar.")
            return
        }
        guard finances.signedIn, finances.catalog != nil else {
            phase = .failed("Conectá Google Sheets y actualizá el presupuesto desde Inicio antes de dictar un gasto.")
            return
        }
        phase = .listening
        await speech.start()
    }

    private func retry() {
        interpretationTask?.cancel()
        speech.cancel()
        handlingTranscript = false
        started = false
        Task { await start() }
    }

    private func cancel() {
        if case .saving = phase { return }
        interpretationTask?.cancel()
        speech.cancel()
        dismiss()
    }

    private func register(_ transcript: String) async {
        do {
            guard let catalog = finances.catalog else { throw FinanceSheetError.invalidBudget }
            let result = try await chatGPT.interpret(transcript, catalog: catalog)
            try Task.checkCancellation()
            let expense = try result.expense(catalog: catalog, defaultPayer: cars.myPayerName)
            phase = .saving
            try await finances.add(expense)
            phase = .saved(expense, pending: finances.isPending(expense))
            ExpenseVoiceDiagnostics.shared.record("Control: gasto registrado o pendiente localmente")
        } catch {
            guard !Task.isCancelled else { return }
            phase = .failed(error.localizedDescription)
        }
    }
}
