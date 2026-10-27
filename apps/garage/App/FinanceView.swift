import CoreLocation
import Charts
import SwiftUI

struct FinanceDashboardView: View {
    @EnvironmentObject private var finances: FinanceStore
    @EnvironmentObject private var cars: CloudStore
    @EnvironmentObject private var expenseMonitor: ExpenseVisitMonitor
    @State private var showingExpense = false
    @State private var suggestedExpense: ExpenseVisitSuggestion?

    private var monthName: String { Date.now.formatted(.dateTime.month(.wide).year().locale(Locale(identifier: "es_AR"))).capitalized }
    private var planned: Decimal { finances.currentMonthBudgets.values.reduce(0, +) }
    private var remaining: Decimal { planned - finances.currentMonthTotal }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let suggestion = expenseMonitor.suggestion {
                        Button {
                            suggestedExpense = suggestion
                            showingExpense = true
                        } label: {
                            Label("¿Gasto en \(suggestion.detail)? Revisar", systemImage: "mappin.circle")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    if finances.signedIn {
                        summary
                        spendingChart
                        categories
                        latest
                    } else {
                        ContentUnavailableView {
                            Label("Conectar presupuesto", systemImage: "chart.pie")
                        } description: {
                            Text("Iniciá sesión con una cuenta de Google que pueda editar la planilla familiar.")
                        } actions: {
                            Button("Conectar Google") { Task { await finances.signIn() } }
                                .buttonStyle(.borderedProminent)
                        }
                        .frame(minHeight: 300)
                    }
                    if let message = finances.message {
                        Label(message, systemImage: "exclamationmark.triangle")
                            .font(.footnote).foregroundStyle(.orange)
                    }
                    if finances.pendingCount > 0 {
                        Label("\(finances.pendingCount) gasto\(finances.pendingCount == 1 ? "" : "s") pendiente\(finances.pendingCount == 1 ? "" : "s") de sincronizar con la planilla", systemImage: "arrow.triangle.2.circlepath")
                            .font(.footnote).foregroundStyle(.orange)
                    }
                    if !cars.cars.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Autos", systemImage: "car.side.fill").font(.headline)
                            Text("\(cars.cars.count) auto\(cars.cars.count == 1 ? "" : "s") · \(cars.plans.filter { plan in cars.cars.contains { $0.id == plan.carID && plan.status(odometer: $0.odometer) != .ok } }.count) servicios para revisar")
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    }
                }
                .padding()
            }
            .navigationTitle(monthName)
            .toolbar {
                if finances.signedIn {
                    ToolbarItem(placement: .topBarLeading) {
                        Menu {
                            Button("Actualizar", systemImage: "arrow.clockwise") { Task { await finances.reload() } }
                            Button("Cerrar sesión de Google", systemImage: "rectangle.portrait.and.arrow.right") { finances.signOut() }
                            Toggle("Sugerencias por ubicación", isOn: Binding(
                                get: { expenseMonitor.enabled }, set: { expenseMonitor.setEnabled($0) }
                            ))
                        } label: { Image(systemName: "ellipsis.circle") }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Gasto", systemImage: "plus") { suggestedExpense = nil; showingExpense = true }
                    }
                }
                if let family = cars.familySpace {
                    ToolbarItem(placement: .topBarLeading) {
                        NavigationLink { CarAccessView(car: family, store: cars) } label: {
                            Label("Compartir Garage", systemImage: "person.2")
                        }
                    }
                }
            }
            .sheet(isPresented: $showingExpense) { ExpenseEditorView(suggestion: suggestedExpense) }
            .refreshable { await finances.reload() }
            .overlay { if finances.loading { ProgressView().controlSize(.large) } }
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Este mes").font(.headline)
            HStack(spacing: 10) {
                metric("Presupuesto", planned, "calendar")
                metric("Gastado", finances.currentMonthTotal, "creditcard")
            }
            HStack(spacing: 10) {
                metric("Disponible", remaining, "wallet.pass")
                metric("Ingreso previsto", finances.currentMonthIncome, "arrow.down.circle")
            }
        }
    }

    private func metric(_ title: String, _ value: Decimal, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon).foregroundStyle(.tint)
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(FamilyBudget.money(value)).font(.headline).minimumScaleFactor(0.65).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var categories: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Presupuesto por categoría").font(.headline)
            ForEach(FamilyBudget.categories.filter { finances.currentMonthBudgets[$0] != nil }, id: \.self) { category in
                let budget = finances.currentMonthBudgets[category] ?? 0
                let spent = finances.currentMonthExpenses.filter { $0.category == category }.reduce(Decimal.zero) { $0 + $1.amount }
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(category).font(.subheadline)
                        Spacer()
                        Text("\(FamilyBudget.money(spent)) / \(FamilyBudget.money(budget))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    GeometryReader { proxy in
                        Capsule().fill(.quaternary)
                            .overlay(alignment: .leading) {
                                Capsule().fill(spent > budget ? Color.orange : Color.accentColor)
                                    .frame(width: proxy.size.width * min(1, max(0, NSDecimalNumber(decimal: budget > 0 ? spent / budget : 0).doubleValue)))
                            }
                    }
                    .frame(height: 7)
                }
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var spendingChart: some View {
        let slices = FamilyBudget.categories.compactMap { category -> (String, Double)? in
            let spent = finances.currentMonthExpenses.filter { $0.category == category }.reduce(Decimal.zero) { $0 + $1.amount }
            return spent > 0 ? (category, NSDecimalNumber(decimal: spent).doubleValue) : nil
        }
        return VStack(alignment: .leading, spacing: 8) {
            Text("En qué se gastó").font(.headline)
            if slices.isEmpty {
                Text("El gráfico aparecerá cuando registres gastos este mes.")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                Chart(slices, id: \.0) { slice in
                    SectorMark(angle: .value("Monto", slice.1), innerRadius: .ratio(0.58))
                        .foregroundStyle(by: .value("Categoría", slice.0))
                }
                .chartLegend(position: .bottom, alignment: .leading)
                .frame(height: 270)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var latest: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Últimos gastos").font(.headline)
                Spacer()
                NavigationLink("Ver todos") { ExpenseHistoryView() }.font(.subheadline)
            }
            ForEach(finances.currentMonthExpenses.prefix(5)) { expense in
                HStack {
                    VStack(alignment: .leading) {
                        Text(expense.detail).lineLimit(1)
                        Text("\(expense.category) · \(expense.paidBy)").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(FamilyBudget.money(expense.amount)).font(.subheadline.bold())
                }
                if expense.id != finances.currentMonthExpenses.prefix(5).last?.id { Divider() }
            }
            if finances.currentMonthExpenses.isEmpty {
                Text("Todavía no hay gastos registrados este mes.").foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct ExpenseHistoryView: View {
    @EnvironmentObject private var finances: FinanceStore
    var body: some View {
        List(finances.expenses) { expense in
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(expense.detail)
                    Text("\(expense.date.formatted(date: .abbreviated, time: .omitted)) · \(expense.category) · \(expense.paidBy)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(FamilyBudget.money(expense.amount)).font(.subheadline.bold())
            }
        }
        .navigationTitle("Todos los gastos")
        .refreshable { await finances.reload() }
    }
}

struct ExpenseEditorView: View {
    @EnvironmentObject private var finances: FinanceStore
    @EnvironmentObject private var cars: CloudStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var speech = ExpenseSpeechRecognizer()
    @StateObject private var location = CurrentExpenseLocation()
    let suggestion: ExpenseVisitSuggestion?
    @State private var date = Date()
    @State private var category = "Super"
    @State private var paidBy = "Sebastián"
    @State private var detail = ""
    @State private var amount = ""
    @State private var saving = false
    @State private var interpreting = false
    @State private var downloadingModel = false
    @State private var rememberPlace = true
    @State private var error: String?

    init(suggestion: ExpenseVisitSuggestion? = nil) {
        self.suggestion = suggestion
        _category = State(initialValue: suggestion?.category ?? "Super")
        _detail = State(initialValue: suggestion?.detail ?? "")
        _date = State(initialValue: suggestion?.arrivedAt ?? .now)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Por voz") {
                    if !ExpenseModel.isDownloaded {
                        Button {
                            downloadingModel = true
                            Task {
                                do { try await ExpenseModel.download() }
                                catch { self.error = error.localizedDescription }
                                downloadingModel = false
                            }
                        } label: {
                            Label("Descargar IA local (1,1 GB)", systemImage: "arrow.down.circle")
                        }
                        .disabled(downloadingModel)
                        Text("La descarga se hace una vez por iPhone. La interpretación del gasto se ejecuta en el dispositivo.")
                            .font(.footnote).foregroundStyle(.secondary)
                    } else {
                        HStack {
                            Button {
                                if speech.listening { speech.stop() }
                                else { Task { await speech.start() } }
                            } label: {
                                Label(speech.listening ? "Detener" : "Dictar gasto", systemImage: speech.listening ? "stop.circle" : "mic")
                            }
                            Spacer()
                            if !speech.transcript.isEmpty {
                                Button("Interpretar") { Task { await interpret() } }
                                    .disabled(interpreting || speech.listening)
                            }
                        }
                        if !speech.transcript.isEmpty {
                            Text(speech.transcript).font(.subheadline)
                        }
                        if let message = speech.errorMessage { Text(message).font(.footnote).foregroundStyle(.orange) }
                    }
                    if interpreting || downloadingModel { ProgressView() }
                }
                Section("Revisar antes de guardar") {
                DatePicker("Fecha", selection: $date, displayedComponents: .date)
                Picker("Categoría", selection: $category) {
                    if category.isEmpty { Text("Elegir categoría").tag("") }
                    ForEach(FamilyBudget.categories, id: \.self) { Text($0) }
                }
                Picker("Pagado por", selection: $paidBy) {
                    if paidBy.isEmpty { Text("Elegir persona").tag("") }
                    ForEach(FamilyBudget.payers, id: \.self) { Text($0) }
                }
                TextField("Detalle", text: $detail)
                TextField("Monto en pesos", text: $amount).keyboardType(.decimalPad)
                Toggle("Recordar este lugar para futuras sugerencias", isOn: $rememberPlace)
                }
                if let error { Text(error).foregroundStyle(.red).font(.footnote) }
            }
            .navigationTitle("Nuevo gasto")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { Task { await save() } }
                        .disabled(saving || decimalAmount == nil || category.isEmpty || paidBy.isEmpty || detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .disabled(saving)
        }
    }

    private var decimalAmount: Decimal? {
        guard let value = Decimal(string: amount.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: "."), locale: Locale(identifier: "en_US_POSIX")), value > 0 else { return nil }
        return value
    }

    private func save() async {
        guard let decimalAmount else { return }
        saving = true
        let expense = FamilyExpense(id: UUID().uuidString, date: date, category: category,
                                    paidBy: paidBy, detail: detail, amount: decimalAmount, row: nil)
        let locationTask: Task<CLLocation?, Never>? = rememberPlace && suggestion == nil
            ? Task { try? await location.capture() } : nil
        do {
            try await finances.add(expense)
            if suggestion != nil { ExpenseVisitMonitor.shared.clearSuggestion() }
            dismiss()
            let captured = await locationTask?.value
            let coordinate = suggestion.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) } ?? captured?.coordinate
            if let coordinate {
                await cars.addExpensePlace(expense: expense, latitude: coordinate.latitude, longitude: coordinate.longitude)
            }
        } catch {
            self.error = error.localizedDescription
            saving = false
        }
    }

    private func interpret() async {
        interpreting = true
        defer { interpreting = false }
        do {
            let result = try await ExpenseModel.interpret(speech.transcript)
            amount = result.amount.map { NSDecimalNumber(decimal: $0).stringValue } ?? ""
            category = result.category.flatMap { FamilyBudget.categories.contains($0) ? $0 : nil } ?? ""
            paidBy = result.paidBy.flatMap { FamilyBudget.payers.contains($0) ? $0 : nil } ?? ""
            detail = result.detail ?? ""
            if let writtenDate = result.date {
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.timeZone = FamilyBudget.calendar.timeZone
                formatter.dateFormat = "yyyy-MM-dd"
                if let parsed = formatter.date(from: writtenDate) { date = parsed }
            }
            error = nil
        } catch { self.error = error.localizedDescription }
    }
}
