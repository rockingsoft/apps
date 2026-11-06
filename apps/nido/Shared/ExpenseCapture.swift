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

struct ExpenseInterpretation: Decodable {
    let amount: Decimal?
    let category: String?
    let paidBy: String?
    let detail: String?
    let date: String?
}

extension ExpenseInterpretation {
    func expense(catalog: FinanceSheetCatalog, defaultPayer: String?, now: Date = .now) throws -> FamilyExpense {
        guard let amount, amount > 0 else { throw ExpenseCaptureError.missing("Decí también el importe del gasto.") }
        guard let category, catalog.categoryNames.contains(category) else {
            throw ExpenseCaptureError.missing("No pude identificar la categoría. Volvé a dictar el gasto con más detalle.")
        }
        // An explicitly returned unknown payer must not silently become the device owner.
        guard let payer = paidBy ?? defaultPayer, catalog.payers.contains(payer) else {
            throw ExpenseCaptureError.missing("Decí quién pagó o elegí tu nombre desde Inicio.")
        }
        guard let detail = detail?.trimmingCharacters(in: .whitespacesAndNewlines), !detail.isEmpty else {
            throw ExpenseCaptureError.missing("Decí en qué fue el gasto.")
        }
        var expenseDate = now
        if let date {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = FamilyBudget.calendar.timeZone
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.isLenient = false
            guard let parsed = formatter.date(from: date), formatter.string(from: parsed) == date else {
                throw ExpenseCaptureError.missing("No pude identificar la fecha. Volvé a dictar el gasto indicando cuándo fue.")
            }
            expenseDate = parsed
        }
        return FamilyExpense(id: UUID().uuidString, date: expenseDate, category: category,
                             paidBy: payer, detail: detail, amount: amount, row: nil)
    }
}

enum ExpenseCaptureError: LocalizedError {
    case missing(String)
    var errorDescription: String? {
        switch self { case .missing(let message): message }
    }
}
