import AppIntents
import Foundation

extension Notification.Name {
    static let garageOpenExpense = Notification.Name("garage.openExpense")
}

struct RegisterExpenseIntent: AppIntent {
    static var title: LocalizedStringResource = "Registrar gasto por voz"
    static var description = IntentDescription("Abre Garage escuchando un gasto para revisarlo antes de guardar.")
    static var openAppWhenRun = true

    @MainActor func perform() async throws -> some IntentResult {
        UserDefaults.standard.set(true, forKey: "garage.openExpenseRequested")
        NotificationCenter.default.post(name: .garageOpenExpense, object: nil)
        return .result()
    }
}

struct GarageShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: RegisterExpenseIntent(), phrases: ["Registrar gasto con \(.applicationName)",
                                                             "Cargar gasto en \(.applicationName)",
                                                             "Registra en \(.applicationName)",
                                                             "Regista en \(.applicationName)"],
                    shortTitle: "Registrar gasto", systemImageName: "mic.circle")
    }
}
