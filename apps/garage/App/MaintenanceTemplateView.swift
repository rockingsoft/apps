import SwiftUI

struct MaintenanceTemplateView: View {
    private struct Draft: Identifiable {
        let rule: MaintenanceRule
        var id: String { rule.id }
        var selected: Bool
        var lastDate = Date()
        var lastKilometers = ""
    }

    @EnvironmentObject private var store: CloudStore
    @Environment(\.dismiss) private var dismiss
    let car: Car
    let template: MaintenanceTemplate
    @State private var drafts: [Draft]
    @State private var confirmed = false
    @State private var saving = false

    init(car: Car, template: MaintenanceTemplate) {
        self.car = car
        self.template = template
        _drafts = State(initialValue: template.rules.map { Draft(rule: $0, selected: $0.initiallySelected) })
    }

    private var canSave: Bool {
        let selected = drafts.filter(\.selected)
        return confirmed && !selected.isEmpty && selected.allSatisfy { draft in
            draft.lastDate <= .now && (
                draft.rule.intervalKilometers == 0 ||
                (Int(draft.lastKilometers).map { (0...car.odometer).contains($0) } ?? false)
            )
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(template.applicability)
                    Text("Este plan es una base. Revisá el manual de tu versión y el historial antes de activarlo; no incluye una marca ni viscosidad de aceite.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Text("Las revisiones adicionales son opcionales. Marcá solo las que quieras seguir; algunas indican inspeccionar y cambiar únicamente si hace falta.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Link(template.sourceName, destination: template.sourceURL)
                } header: { Text("Fuente oficial") }

                ForEach($drafts) { $draft in
                    Section {
                        Toggle("Agregar al plan", isOn: $draft.selected)
                        Text(draft.rule.details).font(.footnote).foregroundStyle(.secondary)
                        if let sourceName = draft.rule.sourceName, let sourceURL = draft.rule.sourceURL {
                            Link(sourceName, destination: sourceURL).font(.footnote)
                        }
                        if draft.selected {
                            Text(intervalDescription(draft.rule)).font(.footnote)
                            DatePicker("Última vez", selection: $draft.lastDate, in: ...Date(), displayedComponents: .date)
                            if draft.rule.intervalKilometers > 0 {
                                TextField("Km cuando se hizo", text: $draft.lastKilometers)
                                    .keyboardType(.numberPad)
                            }
                        }
                    } header: { Text(draft.rule.title) }
                }

                Section {
                    Toggle("Confirmé las fechas y kilometrajes", isOn: $confirmed)
                    Text("Las próximas alertas se calculan desde la última vez que se hizo cada trabajo.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .disabled(saving)
            .navigationTitle(template.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        guard !saving, canSave else { return }
                        let selections = drafts.filter(\.selected).map { draft in
                            MaintenanceSelection(rule: draft.rule, lastDate: draft.lastDate,
                                                 lastKilometers: Int(draft.lastKilometers) ?? car.odometer)
                        }
                        saving = true
                        Task {
                            await store.addMaintenanceSelections(selections, sourceURL: template.sourceURL, to: car)
                            dismiss()
                        }
                    } label: {
                        if saving { ProgressView().accessibilityLabel("Agregando plan") }
                        else { Text("Agregar") }
                    }
                    .disabled(saving || !canSave)
                }
            }
            .interactiveDismissDisabled(saving)
        }
    }

    private func intervalDescription(_ rule: MaintenanceRule) -> String {
        if rule.intervalMonths > 0 && rule.intervalKilometers > 0 {
            return "Cada \(rule.intervalKilometers.formatted()) km o \(rule.intervalMonths) meses, lo que ocurra primero."
        }
        if rule.intervalMonths > 0 { return "Cada \(rule.intervalMonths) meses." }
        return "Cada \(rule.intervalKilometers.formatted()) km."
    }
}
