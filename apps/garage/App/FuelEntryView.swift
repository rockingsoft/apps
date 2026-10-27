import SwiftUI

struct FuelEntryView: View {
    @EnvironmentObject private var store: CloudStore
    @EnvironmentObject private var finances: FinanceStore
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
    @State private var paidBy = "Sebastián"

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
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 12) {
                        Image(systemName: "fuelpump.fill")
                            .font(.title2).foregroundStyle(.tint)
                            .frame(width: 48, height: 48)
                            .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Nueva carga").font(.title2.bold())
                            Text(car.name).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("ESTACIÓN").font(.caption.bold()).foregroundStyle(.secondary)
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
                                Image(systemName: "mappin.circle.fill").foregroundStyle(.tint)
                                Text(stationName.isEmpty ? (locator.loading ? "Buscando cerca tuyo…" : "Elegir estación") : stationName)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if locator.loading { ProgressView() }
                                Image(systemName: "chevron.down").font(.caption.bold()).foregroundStyle(.secondary)
                            }
                            .padding(14)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                        }
                        if manualStation {
                            TextField("Nombre de la estación", text: $stationName)
                                .textInputAutocapitalization(.words)
                                .padding(14)
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                        }
                        if let locationMessage, stationName.isEmpty {
                            Text(locationMessage).font(.caption).foregroundStyle(.secondary)
                        }
                    }

                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("FECHA").font(.caption.bold()).foregroundStyle(.secondary)
                            DatePicker("Fecha", selection: $date, in: ...Date(), displayedComponents: .date)
                                .labelsHidden()
                        }
                        Spacer(minLength: 0)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("HORA").font(.caption.bold()).foregroundStyle(.secondary)
                            DatePicker("Hora", selection: $date, displayedComponents: .hourAndMinute)
                                .labelsHidden()
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))

                    VStack(alignment: .leading, spacing: 6) {
                        Text("KILOMETRAJE").font(.caption.bold()).foregroundStyle(.secondary)
                        HStack {
                            TextField("Kilómetros del tablero", text: $kilometersText)
                                .keyboardType(.numberPad)
                            Text("km").foregroundStyle(.secondary)
                        }
                        .font(.title3)
                    }
                    .padding(14)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))

                    HStack(spacing: 12) {
                        quantityField("LITROS", placeholder: "0", value: $litersText, suffix: "L")
                        quantityField("PRECIO / L", placeholder: "0", value: $priceText, suffix: "$")
                    }

                    HStack(alignment: .firstTextBaseline) {
                        Text("Total").font(.headline)
                        Spacer()
                        Text(total.map(currency) ?? "—")
                            .font(.title.bold()).contentTransition(.numericText())
                    }
                    .padding(18)
                    .foregroundStyle(.white)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 18))
                    Picker("Pagado por", selection: $paidBy) {
                        ForEach(FamilyBudget.payers, id: \.self) { Text($0) }
                    }
                    .padding(10)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                }
                .padding(16)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .disabled(saving)
            .navigationTitle("Cargar nafta")
            .navigationBarTitleDisplayMode(.inline)
            .task { if suggestion == nil { await detectStation() } }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() }.disabled(saving) }
            }
            .safeAreaInset(edge: .bottom) {
                Button(action: save) {
                    if saving { ProgressView().tint(.white) }
                    else { Text("Guardar carga").fontWeight(.semibold) }
                }
                .frame(maxWidth: .infinity, minHeight: 50)
                .foregroundStyle(.white)
                .background(canSave ? Color.accentColor : Color.gray, in: RoundedRectangle(cornerRadius: 14))
                .disabled(saving || !canSave)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.bar)
            }
            .interactiveDismissDisabled(saving)
        }
    }

    private func quantityField(_ title: String, placeholder: String, value: Binding<String>, suffix: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.bold()).foregroundStyle(.secondary)
            HStack {
                TextField(placeholder, text: value).keyboardType(.decimalPad)
                Text(suffix).foregroundStyle(.secondary)
            }
            .font(.title3)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private func save() {
        guard !saving, canSave, let kilometers, let liters, let price else { return }
        saving = true
        Task {
            let entryID = await store.addFuelEntry(car: car, date: date, kilometers: kilometers, liters: liters,
                                     pricePerLiter: price, stationName: stationName.trimmingCharacters(in: .whitespacesAndNewlines),
                                     latitude: latitude, longitude: longitude)
            if let entryID {
                let expense = FamilyExpense(id: "fuel-\(entryID)", date: date, category: "Auto",
                                            paidBy: paidBy, detail: "Nafta · \(stationName) · \(car.name)",
                                            amount: liters * price, row: nil)
                try? await finances.add(expense)
                if let latitude, let longitude {
                    await store.addExpensePlace(expense: expense, latitude: latitude, longitude: longitude)
                }
            }
            if suggestion != nil { FuelVisitMonitor.shared.clearSuggestion() }
            dismiss()
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
