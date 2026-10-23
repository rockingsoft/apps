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
    @State private var latitude: Double?
    @State private var longitude: Double?
    @State private var locationMessage: String?
    @State private var manualStation = false
    @State private var stationWasChosen = false
    @State private var saving = false

    init(car: Car, suggestion: FuelVisitSuggestion? = nil) {
        self.car = car
        self.suggestion = suggestion
        _stationName = State(initialValue: suggestion?.stationName ?? "")
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
                    Menu {
                        Button("Detectar por ubicación", systemImage: "location") {
                            stationWasChosen = false
                            Task { await detectStation() }
                        }
                        ForEach(["YPF", "Shell", "Axion", "Puma", "Gulf", "Petrobras"], id: \.self) { brand in
                            Button(brand) { chooseStation(brand) }
                        }
                        Button("Otra estación…", systemImage: "pencil") {
                            manualStation = true
                            stationWasChosen = true
                            stationName = ""
                            latitude = nil
                            longitude = nil
                        }
                    } label: {
                        HStack {
                            Text("Estación")
                            Spacer()
                            if locator.loading { ProgressView() }
                            Text(stationName.isEmpty ? (locator.loading ? "Buscando…" : "Elegir") : stationName)
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.up.chevron.down").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if manualStation {
                        TextField("Nombre de la estación", text: $stationName)
                            .textInputAutocapitalization(.words)
                    }
                    if let locationMessage, stationName.isEmpty {
                        Text(locationMessage).font(.caption).foregroundStyle(.secondary)
                    }
                }

                Section("Carga") {
                    DatePicker("Fecha", selection: $date, in: ...Date(), displayedComponents: .date)
                    TextField("Kilómetros del tablero", text: $kilometersText).keyboardType(.numberPad)
                    TextField("Litros", text: $litersText).keyboardType(.decimalPad)
                    TextField("Precio por litro", text: $priceText).keyboardType(.decimalPad)
                    LabeledContent("Total", value: total.map(currency) ?? "—")
                        .fontWeight(.semibold)
                }
            }
            .disabled(saving)
            .navigationTitle("Cargar nafta")
            .task { if suggestion == nil { await detectStation() } }
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

    private func chooseStation(_ name: String) {
        stationWasChosen = true
        manualStation = false
        stationName = name
        latitude = nil
        longitude = nil
        locationMessage = nil
    }

    private func detectStation() async {
        do {
            if let match = try await locator.search() {
                guard !stationWasChosen else { return }
                stationName = match.name
                latitude = match.coordinate.latitude
                longitude = match.coordinate.longitude
                manualStation = false
                locationMessage = nil
            } else if stationName.isEmpty {
                locationMessage = "No encontré una estación cercana. Elegila de la lista."
            }
        } catch {
            if stationName.isEmpty { locationMessage = "No pude obtener la ubicación. Elegí la estación de la lista." }
        }
    }
}
