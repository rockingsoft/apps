import Foundation

@main struct ExpenseCaptureTests {
    static func main() throws {
        let catalog = try FinanceSheetCatalog(budgetRows: [["Compras", "Alimentos", "1", "12"]],
                                             payerRows: [["Ana"], ["Luis"], ["Compartido"]],
                                             vehicleCategory: "Compras", sharedPayer: "Compartido")
        func input(amount: Decimal? = Decimal(string: "1234.56"), category: String? = "Compras", payer: String? = nil,
                   detail: String? = "  Almacén  ", date: String? = "2026-11-06") -> ExpenseInterpretation {
            ExpenseInterpretation(amount: amount, category: category, paidBy: payer, detail: detail, date: date)
        }
        let decoded = try JSONDecoder().decode(ExpenseInterpretation.self, from: Data("{\"amount\":1234.56,\"category\":\"Compras\",\"detail\":\"Almacén\"}".utf8))
        let decodedExpense = try decoded.expense(catalog: catalog, defaultPayer: "Ana")
        precondition(decodedExpense.amount == Decimal(string: "1234.56"), "Preserve precision from the interpretation JSON")
        let expense = try input().expense(catalog: catalog, defaultPayer: "Ana")
        precondition(expense.amount == Decimal(string: "1234.56"), "Preserve decimal amounts without form string conversion")
        precondition(expense.detail == "Almacén" && expense.paidBy == "Ana", "Use configured payer when dictation omits one")
        precondition(FamilyBudget.dateString(from: expense.date) == "2026-11-06", "Use the family calendar")
        let other = try input(payer: "Luis").expense(catalog: catalog, defaultPayer: "Ana")
        precondition(other.paidBy == "Luis", "Explicit payer wins over device owner")
        let shared = try input(payer: "Compartido").expense(catalog: catalog, defaultPayer: nil)
        precondition(shared.paidBy == "Compartido", "Allow explicit shared payer without a device profile")
        let now = ISO8601DateFormatter().date(from: "2026-11-06T02:30:00Z")!
        let today = try input(date: nil).expense(catalog: catalog, defaultPayer: "Ana", now: now)
        precondition(FamilyBudget.dateString(from: today.date) == "2026-11-05", "Absent date uses the Buenos Aires day")
        for invalid in [input(amount: nil), input(amount: 0), input(amount: -1), input(category: nil),
                        input(category: "Unknown"), input(payer: "Unknown"), input(detail: nil),
                        input(detail: " \n "), input(date: "2026-02-30"), input(date: "ayer")] {
            do {
                _ = try invalid.expense(catalog: catalog, defaultPayer: "Ana")
                preconditionFailure("Incomplete or unknown data must not be auto-saved")
            } catch ExpenseCaptureError.missing { }
        }
        do {
            _ = try input().expense(catalog: catalog, defaultPayer: nil)
            preconditionFailure("Do not invent a payer")
        } catch ExpenseCaptureError.missing { }
        print("Expense capture tests passed: precision, payers, dates and incomplete dictation")
    }
}
