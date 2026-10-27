import CoreLocation
import Charts
import Combine
import SwiftUI

struct FinanceDashboardView: View {
    @EnvironmentObject private var finances: FinanceStore
    @EnvironmentObject private var chatGPT: ChatGPTExpense
    @EnvironmentObject private var cars: CloudStore
    @EnvironmentObject private var expenseMonitor: ExpenseVisitMonitor
    @State private var showingExpense = false
    @State private var showingPayerProfile = false
    @State private var suggestedExpense: ExpenseVisitSuggestion?

    private var monthName: String { Date.now.formatted(.dateTime.month(.wide).year().locale(Locale(identifier: "es_AR"))).capitalized }
    private var planned: Decimal { finances.currentMonthBudgets.values.reduce(0, +) }
    private var remaining: Decimal { planned - finances.currentMonthTotal }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if finances.signedIn && cars.myPayerName == nil {
                        Button("Elegir mi nombre para los gastos") { showingPayerProfile = true }
                            .buttonStyle(.borderedProminent)
                    }
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
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        if finances.signedIn {
                            Button("Mi nombre en el presupuesto", systemImage: "person.crop.circle") { showingPayerProfile = true }
                            Button("Actualizar", systemImage: "arrow.clockwise") { Task { await finances.reload() } }
                            Button("Cerrar sesión de Google", systemImage: "rectangle.portrait.and.arrow.right") { finances.signOut() }
                        } else {
                            Button("Conectar Google", systemImage: "person.crop.circle.badge.checkmark") { Task { await finances.signIn() } }
                        }
                        if chatGPT.connected {
                            Text("ChatGPT: \(chatGPT.email ?? "conectado")")
                            Button("Desconectar ChatGPT", systemImage: "rectangle.portrait.and.arrow.right") {
                                Task { await chatGPT.disconnect() }
                            }
                        } else {
                            Button("Conectar ChatGPT", systemImage: "sparkles") { Task { await chatGPT.connect() } }
                                .disabled(chatGPT.connecting)
                        }
                        if finances.signedIn {
                            Toggle("Sugerencias por ubicación", isOn: Binding(
                                get: { expenseMonitor.enabled }, set: { expenseMonitor.setEnabled($0) }
                            ))
                        }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
                if finances.signedIn {
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
            .sheet(isPresented: $showingPayerProfile) { MyPayerProfileView() }
            .sheet(item: Binding(get: { chatGPT.browserURL.map { BrowserDestination(url: $0) } },
                                 set: { if $0 == nil { chatGPT.cancelConnect() } })) { destination in
                ChatGPTBrowser(url: destination.url)
                    .ignoresSafeArea()
            }
            .alert("ChatGPT", isPresented: Binding(get: { chatGPT.message != nil },
                                                    set: { if !$0 { chatGPT.message = nil } })) {
                Button("Aceptar") { chatGPT.message = nil }
            } message: {
                Text(chatGPT.message ?? "")
            }
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
    @EnvironmentObject private var cars: CloudStore
    @State private var editingExpense: FamilyExpense?
    @State private var deletingExpense: FamilyExpense?
    @State private var showingDeleteConfirmation = false
    @State private var busyID: String?
    @State private var errorMessage: String?

    var body: some View {
        List(finances.expenses) { expense in
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(expense.detail)
                    Text("\(expense.date.formatted(date: .abbreviated, time: .omitted)) · \(expense.category) · \(expense.paidBy)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if busyID == expense.id { ProgressView() }
                else { Text(FamilyBudget.money(expense.amount)).font(.subheadline.bold()) }
            }
            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                Button("Editar", systemImage: "pencil") {
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(180))
                        editingExpense = expense
                    }
                }
                    .tint(.blue)
                    .disabled(busyID != nil)
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button("Eliminar", systemImage: "trash") {
                    deletingExpense = expense
                    showingDeleteConfirmation = true
                }
                .tint(.red)
                .disabled(busyID != nil)
            }
        }
        .navigationTitle("Todos los gastos")
        .refreshable { await finances.reload() }
        .sheet(item: $editingExpense) { expense in ExpenseEditView(original: expense) }
        .confirmationDialog("Eliminar gasto", isPresented: $showingDeleteConfirmation, titleVisibility: .visible) {
            Button("Eliminar gasto", role: .destructive) {
                if let deletingExpense { Task { await delete(deletingExpense) } }
            }
            Button("Cancelar", role: .cancel) { deletingExpense = nil }
        } message: {
            if let deletingExpense {
                Text("Se quitará \(deletingExpense.detail) de la planilla familiar.\(deletingExpense.id.hasPrefix("fuel-") || deletingExpense.id.hasPrefix("service-") ? " El registro del auto seguirá disponible." : "")")
            }
        }
        .alert("No se pudo modificar el gasto", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) {
            Button("Aceptar") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    private func delete(_ expense: FamilyExpense) async {
        busyID = expense.id
        defer { busyID = nil; deletingExpense = nil }
        do {
            try await finances.delete(expense)
            await cars.deleteExpensePlace(for: expense)
        } catch { errorMessage = error.localizedDescription }
    }
}

private struct ExpenseEditView: View {
    @EnvironmentObject private var finances: FinanceStore
    @EnvironmentObject private var cars: CloudStore
    @Environment(\.dismiss) private var dismiss
    let original: FamilyExpense
    @State private var date: Date
    @State private var category: String
    @State private var paidBy: String
    @State private var detail: String
    @State private var amount: String
    @State private var saving = false
    @State private var errorMessage: String?

    init(original: FamilyExpense) {
        self.original = original
        _date = State(initialValue: original.date)
        _category = State(initialValue: original.category)
        _paidBy = State(initialValue: original.paidBy)
        _detail = State(initialValue: original.detail)
        _amount = State(initialValue: NSDecimalNumber(decimal: original.amount).stringValue)
    }

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Fecha", selection: $date, displayedComponents: .date)
                Picker("Categoría", selection: $category) {
                    ForEach(FamilyBudget.categories, id: \.self) { Text($0) }
                }
                Picker("Pagado por", selection: $paidBy) {
                    ForEach(FamilyBudget.payers, id: \.self) { Text($0) }
                }
                TextField("Detalle", text: $detail)
                TextField("Monto en pesos", text: $amount).keyboardType(.decimalPad)
                if original.id.hasPrefix("fuel-") || original.id.hasPrefix("service-") {
                    Text("Este cambio modifica el presupuesto. El registro del auto se conserva.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let errorMessage { Text(errorMessage).font(.footnote).foregroundStyle(.red) }
            }
            .navigationTitle("Editar gasto")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { dismiss() }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { Task { await save() } }
                        .disabled(saving || parsedAmount == nil || detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .disabled(saving)
        }
    }

    private var parsedAmount: Decimal? {
        guard let value = Decimal(string: amount.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: "."),
                                  locale: Locale(identifier: "en_US_POSIX")), value > 0 else { return nil }
        return value
    }

    private func save() async {
        guard let parsedAmount else { return }
        saving = true
        defer { saving = false }
        var edited = original
        edited.date = date
        edited.category = category
        edited.paidBy = paidBy
        edited.detail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        edited.amount = parsedAmount
        do {
            try await finances.update(original, with: edited)
            await cars.updateExpensePlace(for: edited)
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }
}

private struct BrowserDestination: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

private enum VoiceFlowPhase {
    case listening
    case processing
    case failed(String)
}

private struct ExpenseVoiceFlowView: View {
    @ObservedObject var speech: ExpenseSpeechRecognizer
    @Binding var phase: VoiceFlowPhase
    let onCancel: () -> Void
    let onRetry: () -> Void
    @State private var pulsing = false

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.07, green: 0.12, blue: 0.24),
                                    Color(red: 0.04, green: 0.06, blue: 0.12)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    Button("Cancelar", action: onCancel)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.8))
                        .padding(20)
                }
                Spacer()
                ZStack {
                    Circle()
                        .fill(.cyan.opacity(0.1))
                        .frame(width: 280, height: 280)
                        .scaleEffect(pulsing ? 1.13 : 0.85)
                        .opacity(pulsing ? 0.3 : 0.75)
                    Circle()
                        .fill(.cyan.opacity(0.17))
                        .frame(width: 215, height: 215)
                        .scaleEffect(pulsing ? 0.94 : 1.07)
                    Circle()
                        .fill(LinearGradient(colors: [.cyan.opacity(0.85), .blue.opacity(0.9)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 155, height: 155)
                        .shadow(color: .cyan.opacity(0.4), radius: 32)
                    if case .processing = phase {
                        ProgressView().tint(.white).scaleEffect(1.6)
                    } else {
                        Image(systemName: "waveform")
                            .font(.system(size: 45, weight: .medium))
                            .foregroundStyle(.white)
                            .symbolEffect(.variableColor.iterative, options: .repeating)
                    }
                }
                .accessibilityHidden(true)
                .padding(.bottom, 46)
                Text(title)
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.68))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 34)
                    .padding(.top, 12)
                if case .failed = phase {
                    Button("Volver a intentar", action: onRetry)
                        .buttonStyle(.borderedProminent)
                        .tint(.cyan)
                        .padding(.top, 30)
                }
                Spacer()
                if case .listening = phase {
                    Text(speech.listening ? "Se envía al terminar de hablar" : "Preparando el micrófono…")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.48))
                        .padding(.bottom, 30)
                }
            }
        }
        .onAppear { pulsing = true }
        .animation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true), value: pulsing)
        .interactiveDismissDisabled()
    }

    private var title: String {
        switch phase {
        case .listening: speech.listening ? "Escuchando" : "Preparando"
        case .processing: "Preparando tu gasto"
        case .failed: "No se pudo completar"
        }
    }

    private var subtitle: String {
        switch phase {
        case .listening: "Decí el gasto en una frase. Garage terminará cuando hagas una pausa."
        case .processing: "Estamos completando los datos para que los revises."
        case .failed(let message): message
        }
    }
}

struct ExpenseEditorView: View {
    @EnvironmentObject private var finances: FinanceStore
    @EnvironmentObject private var chatGPT: ChatGPTExpense
    @EnvironmentObject private var cars: CloudStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var speech = ExpenseSpeechRecognizer()
    @ObservedObject private var diagnostics = ExpenseVoiceDiagnostics.shared
    @StateObject private var location = CurrentExpenseLocation()
    let suggestion: ExpenseVisitSuggestion?
    let startListening: Bool
    @State private var date = Date()
    @State private var category = "Super"
    @State private var paidBy = ""
    @State private var showingPayerProfile = false
    @State private var detail = ""
    @State private var amount = ""
    @State private var saving = false
    @State private var interpreting = false
    @State private var showingVoiceFlow = false
    @State private var voicePhase: VoiceFlowPhase = .listening
    @State private var interpretationTask: Task<Void, Never>?
    @State private var rememberPlace = true
    @State private var error: String?

    init(suggestion: ExpenseVisitSuggestion? = nil, startListening: Bool = false) {
        self.suggestion = suggestion
        self.startListening = startListening
        _category = State(initialValue: suggestion?.category ?? "Super")
        _detail = State(initialValue: suggestion?.detail ?? "")
        _date = State(initialValue: suggestion?.arrivedAt ?? .now)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Por voz") {
                    if !chatGPT.connected {
                        Text("Conectá ChatGPT desde el menú ⋯ de Inicio para dictar gastos.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Button {
                        beginVoiceFlow()
                    } label: {
                        Label("Hablar", systemImage: "mic.fill")
                            .frame(maxWidth: .infinity, minHeight: 42)
                    }
                    .disabled(!chatGPT.connected || interpreting)
                }
                Section("Revisar antes de guardar") {
                DatePicker("Fecha", selection: $date, displayedComponents: .date)
                Picker("Categoría", selection: $category) {
                    if category.isEmpty { Text("Elegir categoría").tag("") }
                    ForEach(FamilyBudget.categories, id: \.self) { Text($0) }
                }
                Picker("Pagado por", selection: $paidBy) {
                    if paidBy.isEmpty { Text("Elegir persona").tag("") }
                    ForEach(cars.activePayers, id: \.self) { Text($0) }
                }
                if cars.myPayerName == nil {
                    Button("Elegir mi nombre para los gastos") { showingPayerProfile = true }
                }
                TextField("Detalle", text: $detail)
                TextField("Monto en pesos", text: $amount).keyboardType(.decimalPad)
                Toggle("Recordar este lugar para futuras sugerencias", isOn: $rememberPlace)
                }
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
            .onAppear { if paidBy.isEmpty { paidBy = cars.myPayerName ?? "" } }
            .task {
                guard startListening else { return }
                try? await Task.sleep(for: .milliseconds(700))
                guard !Task.isCancelled else { return }
                beginVoiceFlow()
            }
            .onChange(of: cars.myPayerName) { _, name in
                if paidBy.isEmpty, let name { paidBy = name }
            }
            .sheet(isPresented: $showingPayerProfile) { MyPayerProfileView() }
            .fullScreenCover(isPresented: $showingVoiceFlow) {
                ExpenseVoiceFlowView(speech: speech, phase: $voicePhase,
                                     onCancel: cancelVoiceFlow, onRetry: retryVoiceFlow)
            }
            .onReceive(speech.$completedTranscript.compactMap { $0 }) { spoken in
                guard showingVoiceFlow else { return }
                diagnostics.record("Formulario: texto recibido")
                voicePhase = .processing
                if chatGPT.connected { interpretationTask = Task { await interpret(spoken) } }
                else { voicePhase = .failed("Conectá ChatGPT desde el menú de Inicio y volvé a intentar.") }
            }
            .onChange(of: speech.errorMessage) { _, message in
                if showingVoiceFlow, let message { voicePhase = .failed(message) }
            }
            .onChange(of: speech.listening) { _, listening in
                if showingVoiceFlow, !listening, !speech.transcript.isEmpty { voicePhase = .processing }
            }
            .onChange(of: speech.finishedWithoutTranscript) { _, finished in
                if showingVoiceFlow, finished { voicePhase = .failed("No llegué a escuchar un gasto. Probá otra vez.") }
            }
        }
    }

    private func beginVoiceFlow() {
        error = nil
        voicePhase = .listening
        showingVoiceFlow = true
        Task { await speech.start() }
    }

    private func retryVoiceFlow() {
        interpretationTask?.cancel()
        interpretationTask = nil
        speech.cancel()
        voicePhase = .listening
        Task { await speech.start() }
    }

    private func cancelVoiceFlow() {
        interpretationTask?.cancel()
        interpretationTask = nil
        speech.cancel()
        showingVoiceFlow = false
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

    private func interpret(_ spoken: String) async {
        diagnostics.record("Formulario: iniciando interpretación")
        interpreting = true
        defer { interpreting = false }
        do {
            let result = try await chatGPT.interpret(spoken)
            try Task.checkCancellation()
            amount = result.amount.map { NSDecimalNumber(decimal: $0).stringValue } ?? ""
            category = result.category.flatMap { FamilyBudget.categories.contains($0) ? $0 : nil } ?? ""
            if let payer = result.paidBy, cars.activePayers.contains(payer) { paidBy = payer }
            detail = result.detail ?? ""
            if let writtenDate = result.date {
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.timeZone = FamilyBudget.calendar.timeZone
                formatter.dateFormat = "yyyy-MM-dd"
                if let parsed = formatter.date(from: writtenDate) { date = parsed }
            }
            error = nil
            diagnostics.record("Formulario: campos actualizados")
            showingVoiceFlow = false
        } catch {
            guard !Task.isCancelled, showingVoiceFlow else { return }
            voicePhase = .failed(error.localizedDescription)
            diagnostics.record("Formulario: error \(type(of: error))")
        }
    }
}

struct MyPayerProfileView: View {
    @EnvironmentObject private var cars: CloudStore
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(FamilyBudget.payers.filter { $0 != "Común" }, id: \.self) { name in
                        Button {
                            Task { await cars.setMyPayerName(name); dismiss() }
                        } label: {
                            HStack {
                                Text(name)
                                Spacer()
                                if cars.myPayerName == name { Image(systemName: "checkmark") }
                            }
                        }
                    }
                } header: {
                    Text("Tu nombre en la planilla")
                } footer: {
                    Text("Los nombres disponibles corresponden a la columna Pagado por de la planilla familiar. Cada integrante elige el suyo una vez.")
                }
            }
            .navigationTitle("Identificarme")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cerrar") { dismiss() } } }
        }
    }
}
