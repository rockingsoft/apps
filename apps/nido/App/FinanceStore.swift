import Foundation

struct FamilyExpense: Identifiable, Hashable, Codable {
    let id: String
    var date: Date
    var category: String
    var paidBy: String
    var detail: String
    var amount: Decimal
    var row: Int?
}

enum FamilyBudget {
    static let spreadsheetID = "1U0yGuLsn2UfWi309xsY7gW-_IJCd5nh1nJ1NQ6Ip654"
    static let categories = ["Hipoteca", "Servicios", "Impuestos", "Prepaga", "Super", "Salidas", "Auto", "Moto - Seguro ATM", "Seguro de vida - Zurich", "Colegio", "Suscripciones", "Delia - Empleada doméstica", "Adelanto Hipoteca (Extraordinario SAC)", "Vacaciones", "Reserva / Contingencias", "Devoluciones Familiares", "Bolucompras", "Bolucompras Misha"]
    static let payers = ["Sebastián", "Misha", "Común"]
    static let calendar: Calendar = {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "America/Argentina/Buenos_Aires")!
        return value
    }()

    static func date(from serial: Double) -> Date {
        let origin = calendar.date(from: DateComponents(year: 1899, month: 12, day: 30))!
        return calendar.date(byAdding: .day, value: Int(serial), to: origin) ?? origin
    }

    static func serial(from date: Date) -> Int {
        let origin = calendar.date(from: DateComponents(year: 1899, month: 12, day: 30))!
        let day = calendar.startOfDay(for: date)
        return calendar.dateComponents([.day], from: origin, to: day).day ?? 0
    }

    static func money(_ amount: Decimal) -> String {
        amount.formatted(.currency(code: "ARS").locale(Locale(identifier: "es_AR")))
    }
}

@MainActor final class FinanceStore: ObservableObject {
    @Published private(set) var expenses: [FamilyExpense] = []
    @Published private(set) var budgets: [String: Decimal] = [:]
    @Published private(set) var monthlyIncome: Decimal = 0
    @Published private(set) var semiannualBonus: Decimal = 0
    @Published private(set) var loading = false
    @Published var message: String?
    @Published var signedIn = false
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
        signedIn = await google.restore()
        if signedIn { await reload() }
    }

    func signOut() {
        google.signOut()
        signedIn = false
        expenses = []
        budgets = [:]
        monthlyIncome = 0
        semiannualBonus = 0
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
            let rows = try await google.values("'Registro de Gastos'!B4:G1000")
            expenses = rows.enumerated().compactMap { offset, row in
                guard row.count >= 5,
                      let serial = Double(row[0]),
                      let amount = Decimal(string: row[4], locale: Locale(identifier: "en_US_POSIX")),
                      !row[1].isEmpty else { return nil }
                return FamilyExpense(id: row.count > 5 && !row[5].isEmpty ? row[5] : "sheet-row-\(offset + 4)",
                                     date: FamilyBudget.date(from: serial), category: row[1],
                                     paidBy: row[2], detail: row[3], amount: amount, row: offset + 4)
            }.sorted { $0.date > $1.date }

            let budgetRows = try await google.values("'Control Mensual'!B12:D34")
            var nextBudgets: [String: Decimal] = [:]
            for row in budgetRows where row.count > 2 {
                if let amount = Decimal(string: row[2], locale: Locale(identifier: "en_US_POSIX")),
                   FamilyBudget.categories.contains(row[0]) { nextBudgets[row[0]] = amount }
            }
            budgets = nextBudgets
            let incomeRows = try await google.values("'Presupuesto y Balance'!D8")
            monthlyIncome = Decimal(string: incomeRows.first?.first ?? "0", locale: Locale(identifier: "en_US_POSIX")) ?? 0
            let bonusRows = try await google.values("'Presupuesto y Balance'!D7")
            semiannualBonus = Decimal(string: bonusRows.first?.first ?? "0", locale: Locale(identifier: "en_US_POSIX")) ?? 0
            message = nil
            await flushPending()
        } catch {
            message = error.localizedDescription
        }
    }

    func add(_ expense: FamilyExpense) async throws {
        if expenses.contains(where: { $0.id == expense.id }) || pending.contains(where: { $0.id == expense.id }) { return }
        guard expense.amount > 0,
              FamilyBudget.categories.contains(expense.category),
              FamilyBudget.payers.contains(expense.paidBy),
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

    func update(_ original: FamilyExpense, with edited: FamilyExpense) async throws {
        try validate(edited)
        guard edited.id == original.id else { throw FinanceError.invalidExpense }
        let row = try await verifiedRow(for: original)
        try await google.update(sheetValues(for: edited), in: "'Registro de Gastos'!B\(row):G\(row)")
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
              FamilyBudget.categories.contains(expense.category),
              FamilyBudget.payers.contains(expense.paidBy),
              !expense.detail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw FinanceError.invalidExpense
        }
    }

    private func sheetValues(for expense: FamilyExpense) -> [String] {
        [String(FamilyBudget.serial(from: expense.date)), expense.category, expense.paidBy,
         expense.detail, NSDecimalNumber(decimal: expense.amount).stringValue, expense.id]
    }

    private func verifiedRow(for expense: FamilyExpense) async throws -> Int {
        let rows = try await google.values("'Registro de Gastos'!B4:G1000")
        let matches = rows.enumerated().filter { offset, values in
            let rowNumber = offset + 4
            let stableID = values.count > 5 ? values[5] : ""
            return stableID == expense.id ||
                (stableID.isEmpty && expense.id == "sheet-row-\(rowNumber)" && expense.row == rowNumber)
        }
        guard matches.count == 1, let match = matches.first else { throw FinanceError.expenseMissing }
        let values = match.element
        guard values.count >= 5,
              let serial = Double(values[0]),
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
            } catch { break }
        }
    }

    private func write(_ expense: FamilyExpense) async throws {
        // Column G is a stable client ID. A read before retry avoids duplicate rows after an ambiguous response.
        let rows = try await google.values("'Registro de Gastos'!G4:G1000")
        if rows.contains(where: { $0.first == expense.id }) { return }
        let dates = try await google.values("'Registro de Gastos'!B4:B1000")
        guard dates.count < 997 else { throw FinanceError.sheetFull }
        try await google.append([String(FamilyBudget.serial(from: expense.date)), expense.category,
                                 expense.paidBy, expense.detail,
                                 NSDecimalNumber(decimal: expense.amount).stringValue, expense.id],
                                to: "'Registro de Gastos'!B:G")
    }

    var currentMonthExpenses: [FamilyExpense] {
        expenses.filter { FamilyBudget.calendar.isDate($0.date, equalTo: .now, toGranularity: .month) }
    }

    var currentMonthTotal: Decimal { currentMonthExpenses.reduce(0) { $0 + $1.amount } }

    var currentMonthBudgets: [String: Decimal] {
        var result = budgets
        let month = FamilyBudget.calendar.component(.month, from: .now)
        if month != 6 && month != 12 { result["Adelanto Hipoteca (Extraordinario SAC)"] = 0 }
        return result
    }

    var currentMonthIncome: Decimal {
        let month = FamilyBudget.calendar.component(.month, from: .now)
        return monthlyIncome + ((month == 6 || month == 12) ? semiannualBonus / 2 : 0)
    }
}

private enum FinanceError: LocalizedError {
    case invalidExpense, sheetFull, expenseMissing, expenseChanged
    var errorDescription: String? {
        switch self {
        case .invalidExpense: "Revisá monto, categoría, pagador y detalle antes de guardar."
        case .sheetFull: "La planilla llegó a la fila 1000. Hay que extender sus fórmulas antes de agregar más gastos."
        case .expenseMissing: "Este gasto ya no está en la planilla. Actualizá la lista."
        case .expenseChanged: "El gasto cambió en la planilla desde que lo abriste. Actualizá la lista antes de editarlo."
        }
    }
}
