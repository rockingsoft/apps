import SwiftUI
import UIKit

struct CarsView: View {
    @EnvironmentObject private var store: CloudStore
    @EnvironmentObject private var fuelMonitor: FuelVisitMonitor
    @State private var addCar = false
    @State private var carToDelete: Car?
    @State private var suggestedFuelCar: Car?
    var body: some View {
        NavigationStack {
            List {
                if let message = store.syncMessage {
                    Section { Label(message, systemImage: "icloud.slash").font(.footnote).foregroundStyle(.orange) }
                }
                if let suggestion = fuelMonitor.suggestion, !store.cars.isEmpty {
                    Section("Posible carga de nafta") {
                        Text("¿Cargaste en \(suggestion.stationName)? Elegí el auto para registrarla.")
                        ForEach(store.cars) { car in
                            Button(car.name) { suggestedFuelCar = car }
                        }
                        Button("No cargué nafta", role: .destructive) { fuelMonitor.clearSuggestion() }
                    }
                }
                ForEach(store.cars) { car in
                    NavigationLink(value: car) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(car.name).font(.headline)
                            Text("\(car.plate.uppercased()) · \(car.odometer) km").foregroundStyle(.secondary)
                            let due = store.plans.filter { $0.carID == car.id && $0.status(odometer: car.odometer) != .ok }.count
                            if due > 0 { Text("\(due) servicios pendientes").foregroundStyle(.orange).font(.caption) }
                            if !car.isSharedWithMe, let template = MaintenanceCatalog.template(for: car),
                               template.rules.contains(where: { rule in !store.plans.contains(where: { $0.carID == car.id && $0.templateRuleID == rule.id }) }) {
                                Text("Plan oficial sugerido disponible").foregroundStyle(.blue).font(.caption)
                            }
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button {
                            carToDelete = car
                        } label: {
                            Label(car.isSharedWithMe ? "Quitar" : "Eliminar", systemImage: "trash")
                        }
                        .tint(.red)
                    }
                }
                Section("Sugerencias de carga") {
                    Toggle("Avisarme al parar en una estación", isOn: Binding(
                        get: { fuelMonitor.enabled }, set: { enabled in
                            fuelMonitor.setEnabled(enabled)
                            if enabled { Task { await NotificationPlanner.requestPermission() } }
                        }
                    ))
                    Text("Garage usa visitas de iOS y busca estaciones cercanas. Si detecta una parada de al menos 5 minutos, puede sugerir una carga. La detección no es instantánea ni exacta.")
                        .font(.footnote).foregroundStyle(.secondary)
                    if fuelMonitor.enabled && fuelMonitor.authorization != .authorizedAlways {
                        Text("Para recibir avisos con Garage cerrada, permití ubicación ‘Siempre’ en Configuración.")
                            .font(.footnote).foregroundStyle(.orange)
                        Link("Abrir Configuración", destination: URL(string: UIApplication.openSettingsURLString)!)
                    }
                }
            }
            .navigationTitle("Mis autos")
            .navigationDestination(for: Car.self) { CarView(car: $0) }
            .toolbar { Button("Agregar", systemImage: "plus") { addCar = true } }
            .sheet(isPresented: $addCar) { AddCarView() }
            .sheet(item: $suggestedFuelCar) { car in FuelEntryView(car: car, suggestion: fuelMonitor.suggestion) }
            .alert("¿Eliminar este auto?", isPresented: Binding(
                get: { carToDelete != nil },
                set: { if !$0 { carToDelete = nil } }
            )) {
                if let car = carToDelete {
                    Button(car.isSharedWithMe ? "Quitar" : "Eliminar", role: .destructive) {
                        carToDelete = nil
                        Task { await store.deleteCar(car) }
                    }
                }
                Button("Cancelar", role: .cancel) { carToDelete = nil }
            } message: {
                if let car = carToDelete {
                    Text(car.isSharedWithMe
                         ? "Este auto dejará de aparecer en tu cuenta. El dueño conservará sus datos."
                         : "Se eliminarán el auto, su plan de servicios y su historial para todos los que lo comparten.")
                }
            }
            .overlay { if store.cars.isEmpty && !store.loading { ContentUnavailableView("Agregá tu primer auto", systemImage: "car", description: Text("Guardá sus services y recibí avisos cuando se acerquen.")) } }
            .refreshable { await store.reload() }
        }
    }
}

struct AddCarView: View {
    private struct SuggestedPlan: Identifiable {
        let car: Car
        let template: MaintenanceTemplate
        var id: String { car.id.zoneID.zoneName }
    }

    @EnvironmentObject private var store: CloudStore
    @Environment(\.dismiss) private var dismiss
    @State private var plate = ""
    @State private var odometerText = ""
    @State private var brands: [CatalogOption] = []
    @State private var models: [CatalogOption] = []
    @State private var versions: [CatalogVersionGroup] = []
    @State private var years: [Int] = []
    @State private var brandID = 0
    @State private var modelID = 0
    @State private var versionID = 0
    @State private var year = 0
    @State private var yearFallbackText = ""
    @State private var yearLookupFailed = false
    @State private var catalogMessage: String?
    @State private var loadingBrands = false
    @State private var loadingModels = false
    @State private var loadingYears = false
    @State private var saving = false
    @State private var suggestedPlan: SuggestedPlan?

    private var selectedName: String {
        guard let brand = brands.first(where: { $0.id == brandID }),
              let model = models.first(where: { $0.id == modelID }),
              let version = versions.first(where: { $0.id == versionID }),
              (years.contains(year) || (yearLookupFailed && (1950...Calendar.current.component(.year, from: .now) + 1).contains(year))) else { return "" }
        return "\(brand.name) \(model.name) \(year) · \(version.name)"
    }

    var body: some View {
        NavigationStack {
            Form {
                if let catalogMessage {
                    Section {
                        Text(catalogMessage).font(.footnote).foregroundStyle(.orange)
                        Button("Reintentar") { Task { await retryCatalog() } }
                    }
                }
                Section("Auto") {
                        if loadingBrands { ProgressView("Cargando marcas…") }
                        Picker("Marca", selection: $brandID) {
                            Text("Seleccionar").tag(0)
                            ForEach(brands) { brand in Text(brand.name).tag(brand.id) }
                        }
                        if brandID != 0 {
                            if loadingModels { ProgressView("Cargando modelos…") }
                            Picker("Modelo", selection: $modelID) {
                                Text("Seleccionar").tag(0)
                                ForEach(models) { model in Text(model.name).tag(model.id) }
                            }
                        }
                        if modelID != 0 {
                            Picker("Versión", selection: $versionID) {
                                Text("Seleccionar").tag(0)
                                ForEach(versions) { version in Text(version.name).tag(version.id) }
                            }
                            if versionID != 0 {
                                if loadingYears { ProgressView("Cargando años…") }
                                if !years.isEmpty {
                                    Picker("Año", selection: $year) {
                                        Text("Seleccionar").tag(0)
                                        ForEach(years, id: \.self) { value in Text(String(value)).tag(value) }
                                    }
                                }
                                if yearLookupFailed {
                                    TextField("Otro año", text: $yearFallbackText)
                                        .keyboardType(.numberPad)
                                        .onChange(of: yearFallbackText) { _, text in year = Int(text) ?? 0 }
                                }
                            }
                        }
                }
                Section("Datos actuales") {
                    TextField("Patente", text: $plate)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .onChange(of: plate) { _, value in plate = value.uppercased() }
                    TextField("Kilometraje actual", text: $odometerText).keyboardType(.numberPad)
                }
            }
            .disabled(saving)
            .navigationTitle("Nuevo auto")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        guard !saving, let odometer = Int(odometerText), odometer >= 0 else { return }
                        let name = selectedName
                        guard !name.isEmpty else { return }
                        saving = true
                        Task {
                            let car = await store.addCar(name: name, plate: plate, odometer: odometer)
                            if let template = MaintenanceCatalog.template(for: car) {
                                suggestedPlan = SuggestedPlan(car: car, template: template)
                            }
                            else { dismiss() }
                        }
                    } label: {
                        if saving { ProgressView().accessibilityLabel("Guardando auto") }
                        else { Text("Guardar") }
                    }
                    .disabled(saving || selectedName.isEmpty || Int(odometerText).map { $0 < 0 } ?? true)
                }
            }
            .interactiveDismissDisabled(saving)
            .task { await loadBrands() }
            .onChange(of: brandID) { _, id in Task { await loadModels(brandID: id) } }
            .onChange(of: modelID) { _, id in Task { await loadVersions(modelID: id) } }
            .onChange(of: versionID) { _, id in Task { await loadYears(versionID: id) } }
            .sheet(item: $suggestedPlan, onDismiss: { dismiss() }) { suggested in
                MaintenanceTemplateView(car: suggested.car, template: suggested.template)
            }
        }
    }

    private func loadBrands() async {
        loadingBrands = true
        defer { loadingBrands = false }
        do { brands = try await VehicleCatalog.brands() }
        catch { catalogMessage = "No se pudo cargar ArgAutos. Intentá de nuevo más tarde." }
    }

    private func loadModels(brandID: Int) async {
        modelID = 0
        versionID = 0
        year = 0
        models = []
        versions = []
        years = []
        guard brandID != 0 else { return }
        loadingModels = true
        defer { loadingModels = false }
        do {
            let loaded = try await VehicleCatalog.models(brandID: brandID)
            guard self.brandID == brandID else { return }
            models = loaded
            catalogMessage = nil
        }
        catch { catalogMessage = "No se pudo cargar ArgAutos. Intentá de nuevo más tarde." }
    }

    private func loadVersions(modelID: Int) async {
        versionID = 0
        year = 0
        versions = []
        years = []
        guard modelID != 0 else { return }
        do {
            let loaded = try await VehicleCatalog.versions(modelID: modelID)
            guard self.modelID == modelID else { return }
            versions = CatalogVersionGroup.grouped(loaded)
            catalogMessage = nil
        } catch { catalogMessage = "No se pudieron cargar las versiones. Intentá de nuevo más tarde." }
    }

    private func loadYears(versionID: Int) async {
        year = 0
        years = []
        yearFallbackText = ""
        yearLookupFailed = false
        guard let version = versions.first(where: { $0.id == versionID }) else { return }
        years = version.knownYears
        catalogMessage = nil
        guard let baseVersionID = version.baseVersionID else { return }
        loadingYears = true
        defer { loadingYears = false }
        do {
            let loaded = try await VehicleCatalog.years(versionID: baseVersionID)
            guard self.versionID == versionID else { return }
            years = Array(Set(version.knownYears + loaded)).sorted(by: >)
            catalogMessage = nil
        } catch {
            guard self.versionID == versionID else { return }
            yearLookupFailed = true
            catalogMessage = "ArgAutos no pudo cargar los años. Ingresá el año o reintentá."
        }
    }

    private func retryCatalog() async {
        catalogMessage = nil
        if brands.isEmpty { await loadBrands() }
        else if models.isEmpty, brandID != 0 { await loadModels(brandID: brandID) }
        else if versions.isEmpty, modelID != 0 { await loadVersions(modelID: modelID) }
        else if (years.isEmpty || yearLookupFailed), versionID != 0 { await loadYears(versionID: versionID) }
    }
}

struct CarView: View {
    @EnvironmentObject private var store: CloudStore
    let car: Car
    @State private var addPlan = false
    @State private var addFuel = false
    @State private var templateToReview: MaintenanceTemplate?
    @State private var share = false
    @State private var editOdometer = false
    @State private var kilometers = 0
    private var current: Car { store.cars.first(where: { $0.id == car.id }) ?? car }
    private var recentFuelEntries: [FuelEntry] {
        store.fuelEntries.filter { $0.carID == car.id }.sorted { $0.date > $1.date }
    }
    private var availableTemplate: MaintenanceTemplate? {
        guard !current.isSharedWithMe, let template = MaintenanceCatalog.template(for: current) else { return nil }
        let existing = Set(store.plans.filter { $0.carID == current.id }.compactMap(\.templateRuleID))
        let available = template.excluding(existing)
        return available.rules.isEmpty ? nil : available
    }
    var body: some View {
        List {
            Section {
                LabeledContent("Patente", value: current.plate.uppercased())
                Button("Kilometraje: \(current.odometer) km") { kilometers = current.odometer; editOdometer = true }
            }
            Section("Cargas de nafta") {
                ForEach(recentFuelEntries.prefix(3)) { entry in FuelEntryRow(entry: entry) }
                if recentFuelEntries.count > 3 {
                    NavigationLink("Ver más") { FuelHistoryView(car: current) }
                }
                Button("Registrar carga", systemImage: "fuelpump") { addFuel = true }
            }
            Section("Plan de servicios") {
                if availableTemplate != nil {
                    Button("Revisar plan oficial sugerido", systemImage: "checklist") {
                        templateToReview = availableTemplate
                    }
                }
                ForEach(store.plans.filter { $0.carID == car.id }.sorted { $0.status(odometer: current.odometer).rawValue < $1.status(odometer: current.odometer).rawValue }) { plan in
                    NavigationLink { PlanView(plan: plan, car: current) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack { Text(plan.title).font(.headline); Spacer(); Text(plan.status(odometer: current.odometer).rawValue).foregroundStyle(plan.status(odometer: current.odometer) == .ok ? .green : .orange) }
                            if let date = plan.nextDate { Text("Próximo: \(date.formatted(date: .abbreviated, time: .omitted))").font(.caption) }
                            if let km = plan.nextKilometers { Text("A los \(km) km").font(.caption) }
                        }
                    }
                }
                Button("Agregar servicio", systemImage: "plus") { addPlan = true }
            }
        }
        .navigationTitle(current.name)
        .toolbar { if !current.isSharedWithMe { Button("Compartir", systemImage: "person.crop.circle.badge.plus") { share = true }.disabled(!store.canShare(current)) } }
        .sheet(isPresented: $addPlan) { AddPlanView(car: current) }
        .sheet(isPresented: $addFuel) { FuelEntryView(car: current) }
        .sheet(item: $templateToReview) { template in MaintenanceTemplateView(car: current, template: template) }
        .sheet(isPresented: $share) { CarSharingSheet(car: current, store: store) }
        .alert("Actualizar kilometraje", isPresented: $editOdometer) {
            TextField("Kilómetros", value: $kilometers, format: .number).keyboardType(.numberPad)
            Button("Guardar") { Task { await store.updateOdometer(current, kilometers: kilometers) } }
            Button("Cancelar", role: .cancel) {}
        } message: { Text("Las alertas por kilometraje se recalculan con esta lectura.") }
    }
}

private struct FuelEntryRow: View {
    let entry: FuelEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(entry.stationName).font(.headline)
                Spacer()
                Text(entry.totalDescription)
            }
            Text("\(entry.date.formatted(date: .abbreviated, time: .omitted)) · \(entry.kilometers.formatted()) km · \(NSDecimalNumber(decimal: entry.liters).stringValue) L")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct FuelHistoryView: View {
    @EnvironmentObject private var store: CloudStore
    let car: Car
    var body: some View {
        List {
            ForEach(store.fuelEntries.filter { $0.carID == car.id }.sorted { $0.date > $1.date }) { entry in
                FuelEntryRow(entry: entry)
            }
        }
        .navigationTitle("Cargas de nafta")
    }
}

struct AddPlanView: View {
    @EnvironmentObject private var store: CloudStore
    @Environment(\.dismiss) private var dismiss
    let car: Car
    @State private var title = ""
    @State private var details = ""
    @State private var months = 12
    @State private var intervalKM = 10000
    @State private var lastDate = Date()
    @State private var lastKM = 0
    @State private var noticeDays = 14
    @State private var noticeKM = 500
    @State private var saving = false
    var body: some View {
        NavigationStack {
            Form {
                Section("Servicio") {
                    TextField("Nombre (ej. Cambio de aceite)", text: $title)
                    TextField("Detalle: marca, tipo, viscosidad, piezas…", text: $details, axis: .vertical).lineLimit(3...6)
                }
                Section("Frecuencia") {
                    Stepper("Cada \(months) meses", value: $months, in: 0...120)
                    TextField("Cada km (0 para desactivar)", value: $intervalKM, format: .number).keyboardType(.numberPad)
                    Text("Se vence cuando se cumple cualquiera de los dos criterios.").font(.footnote).foregroundStyle(.secondary)
                }
                Section("Último service") {
                    DatePicker("Fecha", selection: $lastDate, displayedComponents: .date)
                    TextField("Kilometraje", value: $lastKM, format: .number).keyboardType(.numberPad)
                }
                Section("Avisar antes") {
                    Stepper("\(noticeDays) días", value: $noticeDays, in: 0...90)
                    TextField("Kilómetros", value: $noticeKM, format: .number).keyboardType(.numberPad)
                }
            }
            .disabled(saving)
            .navigationTitle("Nuevo servicio")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        guard !saving, !title.isEmpty, months != 0 || intervalKM != 0 else { return }
                        saving = true
                        Task { await store.addPlan(car: car, title: title, details: details, months: months, kilometers: intervalKM, lastDate: lastDate, lastKilometers: lastKM, noticeDays: noticeDays, noticeKilometers: noticeKM); dismiss() }
                    } label: {
                        if saving { ProgressView().accessibilityLabel("Guardando servicio") }
                        else { Text("Guardar") }
                    }
                    .disabled(saving || title.isEmpty || (months == 0 && intervalKM == 0))
                }
            }
            .interactiveDismissDisabled(saving)
        }
        .onAppear { lastKM = car.odometer }
    }
}

struct PlanView: View {
    @EnvironmentObject private var store: CloudStore
    let plan: ServicePlan
    let car: Car
    @State private var complete = false
    var body: some View {
        List {
            Section("Qué hacer") { Text(plan.details.isEmpty ? "Sin detalles cargados" : plan.details) }
            if let sourceURL = plan.sourceURL.flatMap(URL.init(string:)) {
                Section("Fuente") { Link("Ver plan oficial", destination: sourceURL) }
            }
            Section("Próximo vencimiento") {
                if plan.baselineUnknown {
                    Text("Pendiente de revisión: todavía no hay una última realización registrada para calcular el siguiente vencimiento.")
                        .foregroundStyle(.orange)
                }
                if let date = plan.nextDate { LabeledContent("Fecha", value: date.formatted(date: .abbreviated, time: .omitted)) }
                if let km = plan.nextKilometers { LabeledContent("Kilometraje", value: "\(km) km") }
            }
            Section("Historial") {
                ForEach(store.entries.filter { $0.planID == plan.id }) { entry in
                    VStack(alignment: .leading) {
                        Text(entry.date.formatted(date: .abbreviated, time: .omitted)).font(.headline)
                        Text("\(entry.kilometers) km")
                        if !entry.notes.isEmpty { Text(entry.notes).foregroundStyle(.secondary) }
                    }
                }
            }
        }
        .navigationTitle(plan.title)
        .toolbar { Button("Registrar service") { complete = true } }
        .sheet(isPresented: $complete) { CompleteServiceView(plan: plan, car: car) }
    }
}

struct CompleteServiceView: View {
    @EnvironmentObject private var store: CloudStore
    @Environment(\.dismiss) private var dismiss
    let plan: ServicePlan
    let car: Car
    @State private var date = Date()
    @State private var kilometers = 0
    @State private var notes = ""
    @State private var saving = false
    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Fecha", selection: $date, displayedComponents: .date)
                TextField("Kilometraje", value: $kilometers, format: .number).keyboardType(.numberPad)
                TextField("Notas, repuestos, taller…", text: $notes, axis: .vertical)
            }
            .disabled(saving)
            .navigationTitle("Registrar service")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        guard !saving else { return }
                        saving = true
                        Task { await store.complete(plan, car: car, date: date, kilometers: kilometers, notes: notes); dismiss() }
                    } label: {
                        if saving { ProgressView().accessibilityLabel("Guardando service") }
                        else { Text("Guardar") }
                    }
                    .disabled(saving)
                }
            }
            .interactiveDismissDisabled(saving)
        }
        .onAppear { kilometers = car.odometer }
    }
}
