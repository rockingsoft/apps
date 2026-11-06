import Foundation

@MainActor final class FinanceStore: ObservableObject {
    @Published private(set) var expenses: [FamilyExpense] = []
    @Published private(set) var budgets: [String: Decimal] = [:]
    @Published private(set) var monthlyIncome: Decimal = 0
    @Published private(set) var budgetDate: Date = .now
    @Published private(set) var catalog: FinanceSheetCatalog?

    var categories: [String] { catalog?.categoryNames ?? [] }
    var payers: [String] { catalog?.payers ?? [] }
    var vehicleCategory: String? { catalog?.vehicleCategory }
    var personalPayers: [String] { payers.filter { $0 != catalog?.sharedPayer } }
    @Published private(set) var loading = false
    @Published var message: String?
    @Published var signedIn = false
    @Published private(set) var restored = false
    @Published private(set) var pendingCount = 0

    private let google = GoogleSheetsAccess()
    private var pending: [FamilyExpense] = []
    private var reloadRequested = false

    init() {
        if let data = UserDefaults.standard.data(forKey: "garage.pendingExpenses"),
           let saved = try? JSONDecoder().decode([FamilyExpense].self, from: data) { pending = saved }
        pendingCount = pending.count
    }

    private func persistPending() {
        UserDefaults.standard.set(try? JSONEncoder().encode(pending), forKey: "garage.pendingExpenses")
        pendingCount = pending.count
    }

    func signIn() async {
        do {
            try await google.signIn()
            signedIn = true
            await reload()
        } catch {
            message = error.localizedDescription
        }
    }

    func restore() async {
        defer { restored = true }
        signedIn = await google.restore()
        if signedIn { await reload() }
    }

    func signOut() {
        google.signOut()
        signedIn = false
        expenses = []
        budgets = [:]
        monthlyIncome = 0
        catalog = nil
        ExpenseVisitMonitor.shared.configure(categories: [], vehicleCategory: nil)
    }

    func reload() async {
        guard signedIn else { return }
        if loading { reloadRequested = true; return }
        loading = true
        defer {
            loading = false
            if reloadRequested {
                reloadRequested = false
                Task { await self.reload() }
            }
        }
        do {
            let rows = try await google.values("'Registro de Gastos'!B4:G")
            let nextExpenses: [FamilyExpense] = rows.enumerated().compactMap { offset, row in
                guard row.count >= 5,
                      let serial = Double(row[0]), serial.isFinite, serial > 0, serial < 2958466,
                      let amount = Decimal(string: row[4], locale: Locale(identifier: "en_US_POSIX")),
                      !row[1].isEmpty else { return nil }
                return FamilyExpense(id: row.count > 5 && !row[5].isEmpty ? row[5] : "sheet-row-\(offset + 4)",
                                     date: FamilyBudget.date(from: serial), category: row[1],
                                     paidBy: row[2], detail: row[3], amount: amount, row: offset + 4)
            }.sorted { $0.date > $1.date }

            let nextCatalog = try await google.budgetCatalog()
            let period = try await google.values("NidoPeriodo")
            let income = try await google.values("NidoIngreso")
            guard let serial = period.first?.first.flatMap(Double.init), serial.isFinite, serial > 0, serial < 2958466,
                  let value = income.first?.first.flatMap({ Decimal(string: $0, locale: Locale(identifier: "en_US_POSIX")) }) else {
                throw FinanceSheetError.invalidBudget
            }
            expenses = nextExpenses
            catalog = nextCatalog
            ExpenseVisitMonitor.shared.configure(categories: nextCatalog.categoryNames, vehicleCategory: nextCatalog.vehicleCategory)
            budgets = nextCatalog.budgets
            budgetDate = FamilyBudget.date(from: serial)
            monthlyIncome = value
            message = nil
            await flushPending()
        } catch {
            message = error.localizedDescription
        }
    }

    func add(_ expense: FamilyExpense) async throws {
        if expenses.contains(where: { $0.id == expense.id }) || pending.contains(where: { $0.id == expense.id }) { return }
        guard expense.amount > 0,
              categories.contains(expense.category),
              payers.contains(expense.paidBy),
              !expense.detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw FinanceError.invalidExpense
        }
        pending.append(expense)
        persistPending()
        do {
            try await write(expense)
            pending.removeAll { $0.id == expense.id }
            persistPending()
            await reload()
        } catch {
            message = "El gasto quedó pendiente en este iPhone: \(error.localizedDescription)"
        }
    }

    func isPending(_ expense: FamilyExpense) -> Bool {
        pending.contains { $0.id == expense.id }
    }

    func update(_ original: FamilyExpense, with edited: FamilyExpense) async throws {
        try validate(edited)
        guard edited.id == original.id else { throw FinanceError.invalidExpense }
        let row = try await verifiedRow(for: original)
        try await google.updateExpense(sheetValues(for: edited), row: row)
        pending.removeAll { $0.id == original.id }
        persistPending()
        if let index = expenses.firstIndex(where: { $0.id == original.id }) {
            var saved = edited
            saved.row = row
            expenses[index] = saved
            expenses.sort { $0.date > $1.date }
        }
        await reload()
    }

    func delete(_ expense: FamilyExpense) async throws {
        let row = try await verifiedRow(for: expense)
        try await google.clear("'Registro de Gastos'!B\(row):G\(row)")
        pending.removeAll { $0.id == expense.id }
        persistPending()
        expenses.removeAll { $0.id == expense.id }
        await reload()
    }

    private func validate(_ expense: FamilyExpense) throws {
        guard expense.amount > 0,
              categories.contains(expense.category),
              payers.contains(expense.paidBy),
              !expense.detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw FinanceError.invalidExpense
        }
    }

    private func sheetValues(for expense: FamilyExpense) -> [SheetInputValue] {
        [.number(Decimal(FamilyBudget.serial(from: expense.date))), .text(expense.category), .text(expense.paidBy),
         .text(expense.detail), .number(expense.amount), .text(expense.id)]
    }

    private func verifiedRow(for expense: FamilyExpense) async throws -> Int {
        let rows = try await google.values("'Registro de Gastos'!B4:G")
        let matches = rows.enumerated().filter { offset, values in
            let rowNumber = offset + 4
            let stableID = values.count > 5 ? values[5] : ""
            return stableID == expense.id ||
                (stableID.isEmpty && expense.id == "sheet-row-\(rowNumber)" && expense.row == rowNumber)
        }
        guard matches.count == 1, let match = matches.first else { throw FinanceError.expenseMissing }
        let values = match.element
        guard values.count >= 5,
              let serial = Double(values[0]), serial.isFinite, serial > 0, serial < 2958466,
              let amount = Decimal(string: values[4], locale: Locale(identifier: "en_US_POSIX")),
              Int(serial) == FamilyBudget.serial(from: expense.date),
              values[1] == expense.category,
              values[2] == expense.paidBy,
              values[3] == expense.detail,
              amount == expense.amount else { throw FinanceError.expenseChanged }
        return match.offset + 4
    }

    private func flushPending() async {
        for expense in pending {
            do {
                try await write(expense)
                if !expenses.contains(where: { $0.id == expense.id }) {
                    expenses.append(expense)
                    expenses.sort { $0.date > $1.date }
                }
                pending.removeAll { $0.id == expense.id }
                persistPending()
            } catch {
                message = "Hay gastos pendientes: \(error.localizedDescription)"
                break
            }
        }
    }

    private func write(_ expense: FamilyExpense) async throws {
        // Column G is a stable client ID. A read before retry avoids duplicate rows after an ambiguous response.
        let rows = try await google.values("'Registro de Gastos'!G4:G")
        if let index = rows.firstIndex(where: { $0.first == expense.id }) {
            try await google.formatExpenseDate(row: index + 4)
            return
        }
        try validate(expense)
        try await google.appendExpense(sheetValues(for: expense))
    }

    var currentMonthExpenses: [FamilyExpense] {
        expenses.filter { FamilyBudget.calendar.isDate($0.date, equalTo: budgetDate, toGranularity: .month) }
    }

    var currentMonthTotal: Decimal { currentMonthExpenses.reduce(0) { $0 + $1.amount } }

    var currentMonthBudgets: [String: Decimal] { budgets }

    var currentMonthIncome: Decimal { monthlyIncome }
}

private enum FinanceError: LocalizedError {
    case invalidExpense, expenseMissing, expenseChanged
    var errorDescription: String? {
        switch self {
        case .invalidExpense: "Revisá monto, categoría, pagador y detalle antes de guardar."
        case .expenseMissing: "Este gasto ya no está en la planilla. Actualizá la lista."
        case .expenseChanged: "El gasto cambió en la planilla desde que lo abriste. Actualizá la lista antes de editarlo."
        }
    }
}
