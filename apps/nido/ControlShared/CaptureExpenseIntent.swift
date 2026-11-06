import AppIntents
import Foundation

extension Notification.Name {
    static let nidoCaptureExpense = Notification.Name("nido.captureExpense")
}

struct CaptureExpenseIntent: AppIntent {
    static var title: LocalizedStringResource = "Dictar gasto en Nido"
    static var description = IntentDescription("Abre el micrófono de Nido y registra el gasto al terminar de hablar.")
    static var openAppWhenRun = true

    @MainActor func perform() async throws -> some IntentResult {
        // With openAppWhenRun, this shared intent executes in the containing app.
        UserDefaults.standard.set(true, forKey: "nido.captureExpenseRequested")
        NotificationCenter.default.post(name: .nidoCaptureExpense, object: nil)
        return .result()
    }
}
