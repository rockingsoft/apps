import SwiftUI

struct FuelEntryView: View {
    @EnvironmentObject private var store: CloudStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var locator = CurrentFuelStation()

    let car: Car
    let suggestion: FuelVisitSuggestion?
    @State private var date = Date()
    @State private var kilometersText = ""
    @State private var litersText = ""
    @State private var priceText = ""
    @State private var stationName: String
    @State private var detectedStationName: String?
    @State private var latitude: Double?
    @State private var longitude: Double?
    @State private var locationMessage: String?
    @State private var saving = false

    init(car: Car, suggestion: FuelVisitSuggestion? = nil) {
        self.car = car
        self.suggestion = suggestion
        _stationName = State(initialValue: suggestion?.stationName ?? "")
        _detectedStationName = State(initialValue: suggestion?.stationName)
        _date = State(initialValue: suggestion?.arrivedAt ?? .now)
        _latitude = State(initialValue: suggestion?.latitude)
        _longitude = State(initialValue: suggestion?.longitude)
    }

    private func amount(_ text: String) -> Decimal? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        guard let decimal = Decimal(string: value, locale: Locale(identifier: "en_US_POSIX")), decimal > 0 else { return nil }
        return decimal
    }

    private var liters: Decimal? { amount(litersText) }
    private var price: Decimal? { amount(priceText) }
    private var total: Decimal? { liters.flatMap { l in price.map { l * $0 } } }
    private var kilometers: Int? { Int(kilometersText) }
    private var canSave: Bool {
        !stationName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        (kilometers.map { $0 >= 0 } ?? false) && liters != nil && price != nil
    }

    private func currency(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale(identifier: "es_AR")
        formatter.currencyCode = "ARS"
        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? "$ \(value)"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Estación") {
                    TextField("Marca o nombre", text: $stationName)
                        .textInputAutocapitalization(.words)
                        .onChange(of: stationName) { _, value in
                            if value != detectedStationName { latitude = nil; longitude = nil }
                        }
                    HStack {
                        ForEach(["YPF", "Shell", "Axion", "Puma"], id: \.self) { brand in
                            Button(brand) { detectedStationName = nil; stationName = brand; latitude = nil; longitude = nil }
                                .buttonStyle(.bordered)
                        }
                    }
                    .font(.caption)
                    Button {
                        Task {
                            do {
                                if let match = try await locator.search() {
                                    detectedStationName = match.name
                                    stationName = match.name
                                    latitude = match.coordinate.latitude
                                    longitude = match.coordinate.longitude
                                    locationMessage = "Encontré \(match.name). Podés cambiarlo a mano."
                                } else { locationMessage = "No encontré una estación cercana. Elegila a mano." }
                            } catch { locationMessage = "No pude obtener la ubicación. Elegí la estación a mano." }
                        }
                    } label: {
                        if locator.loading { ProgressView("Buscando estación…") }
                        else { Label("Detectar estación cercana", systemImage: "location") }
                    }
                    .disabled(locator.loading)
                    if let locationMessage { Text(locationMessage).font(.footnote).foregroundStyle(.secondary) }
                }

                Section("Carga") {
                    DatePicker("Fecha", selection: $date, in: ...Date(), displayedComponents: .date)
                    TextField("Kilómetros del tablero", text: $kilometersText).keyboardType(.numberPad)
                    TextField("Litros", text: $litersText).keyboardType(.decimalPad)
                    TextField("Precio por litro", text: $priceText).keyboardType(.decimalPad)
                    LabeledContent("Total", value: total.map(currency) ?? "—")
                        .fontWeight(.semibold)
                }
                Section {
                    Text("La carga se guarda en el historial de \(car.name). Si el kilometraje es mayor al actual, se actualiza el auto.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .disabled(saving)
            .navigationTitle("Cargar nafta")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        guard !saving, canSave, let kilometers, let liters, let price else { return }
                        saving = true
                        Task {
                            await store.addFuelEntry(car: car, date: date, kilometers: kilometers, liters: liters,
                                                     pricePerLiter: price, stationName: stationName.trimmingCharacters(in: .whitespacesAndNewlines),
                                                     latitude: latitude, longitude: longitude)
                            if suggestion != nil { FuelVisitMonitor.shared.clearSuggestion() }
                            dismiss()
                        }
                    } label: {
                        if saving { ProgressView().accessibilityLabel("Guardando carga") }
                        else { Text("Guardar") }
                    }
                    .disabled(saving || !canSave)
                }
            }
            .interactiveDismissDisabled(saving)
        }
    }
}
