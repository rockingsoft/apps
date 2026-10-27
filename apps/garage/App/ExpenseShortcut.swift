import AppIntents
import Foundation

extension Notification.Name {
    static let garageOpenExpense = Notification.Name("garage.openExpense")
}

struct RegisterExpenseIntent: AppIntent {
    static var title: LocalizedStringResource = "Registrar gasto por voz"
    static var description = IntentDescription("Pide el gasto a Siri y abre Garage para revisarlo antes de guardar.")
    static var openAppWhenRun = true
    @Parameter(title: "Gasto", requestValueDialog: "¿Qué gasto querés registrar?")
    var spokenExpense: String

    static var parameterSummary: some ParameterSummary {
        Summary("Registrar \(\.$spokenExpense) en Garage")
    }

    @MainActor func perform() async throws -> some IntentResult {
        UserDefaults.standard.set(spokenExpense, forKey: "garage.shortcutExpenseText")
        UserDefaults.standard.set(true, forKey: "garage.openExpenseRequested")
        NotificationCenter.default.post(name: .garageOpenExpense, object: nil)
        return .result()
    }
}

struct GarageShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: RegisterExpenseIntent(), phrases: ["Registrar gasto con \(.applicationName)",
                                                             "Cargar gasto en \(.applicationName)"],
                    shortTitle: "Registrar gasto", systemImageName: "mic.circle")
    }
}
