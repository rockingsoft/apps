import Foundation

enum FamilyBudget {
    static let spreadsheetID = "1U0yGuLsn2UfWi309xsY7gW-_IJCd5nh1nJ1NQ6Ip654"
    static let calendar: Calendar = {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "America/Argentina/Buenos_Aires")!
        return value
    }()

    static func date(from serial: Double) -> Date {
        let origin = calendar.date(from: DateComponents(year: 1899, month: 12, day: 30))!
        return calendar.date(byAdding: .day, value: Int(serial), to: origin)!
    }

    static func serial(from date: Date) -> Int {
        let origin = calendar.date(from: DateComponents(year: 1899, month: 12, day: 30))!
        return calendar.dateComponents([.day], from: origin, to: calendar.startOfDay(for: date)).day!
    }

    static func dateString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    static func money(_ amount: Decimal) -> String {
        amount.formatted(.currency(code: "ARS").locale(Locale(identifier: "es_AR")))
    }
}

struct BudgetCategory: Equatable {
    let name: String
    let description: String
    let monthlyBudget: Decimal
    let annualBudget: Decimal
}

struct FinanceSheetCatalog {
    let categories: [BudgetCategory]
    let payers: [String]
    let vehicleCategory: String
    let sharedPayer: String

    init(budgetRows: [[String]], payerRows: [[String]], vehicleCategory: String, sharedPayer: String) throws {
        var categories: [BudgetCategory] = []
        var seen = Set<String>()
        for row in budgetRows where row.contains(where: { !$0.isEmpty }) {
            guard row.count >= 4, !row[0].isEmpty, seen.insert(row[0]).inserted,
                  let monthly = Decimal(string: row[2], locale: Locale(identifier: "en_US_POSIX")),
                  let annual = Decimal(string: row[3], locale: Locale(identifier: "en_US_POSIX")) else {
                throw FinanceSheetError.invalidBudget
            }
            categories.append(BudgetCategory(name: row[0], description: row[1], monthlyBudget: monthly, annualBudget: annual))
        }
        var payers: [String] = []
        for row in payerRows {
            if let name = row.first, !name.isEmpty, !payers.contains(name) { payers.append(name) }
        }
        guard !categories.isEmpty, !payers.isEmpty,
              categories.contains(where: { $0.name == vehicleCategory }), payers.contains(sharedPayer) else {
            throw FinanceSheetError.invalidBudget
        }
        self.categories = categories
        self.payers = payers
        self.vehicleCategory = vehicleCategory
        self.sharedPayer = sharedPayer
    }

    var categoryNames: [String] { categories.map(\.name) }
    var budgets: [String: Decimal] { Dictionary(uniqueKeysWithValues: categories.map { ($0.name, $0.monthlyBudget) }) }
    var voiceDefinitions: String { categories.map { "\($0.name): \($0.description)" }.joined(separator: ". ") }
}

enum FinanceSheetError: LocalizedError {
    case invalidBudget
    var errorDescription: String? {
        "No se pudo leer el presupuesto de la planilla. Revisá las categorías, importes y pagadores y volvé a actualizar."
    }
}

// RAW writes keep dates/amounts numeric and prevent locale parsing or formula execution in descriptions.
enum SheetInputValue: Encodable {
    case text(String)
    case number(Decimal)

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .text(let text): try container.encode(text)
        case .number(let number): try container.encode(number)
        }
    }
}

struct ExpenseSheetFormat: Encodable {
    let requests: [Request]
    struct Request: Encodable { let repeatCell: RepeatCell }
    struct RepeatCell: Encodable {
        let range: Range
        let cell = Cell()
        let fields = "userEnteredFormat.numberFormat"
    }
    struct Range: Encodable {
        let sheetId: Int
        let startRowIndex: Int
        let endRowIndex: Int
        let startColumnIndex = 1
        let endColumnIndex = 2
    }
    struct Cell: Encodable { let userEnteredFormat = Format() }
    struct Format: Encodable { let numberFormat = NumberFormat() }
    struct NumberFormat: Encodable {
        let type = "DATE"
        let pattern = "dd/mm/yyyy"
    }
    init(sheetID: Int, row: Int) {
        requests = [Request(repeatCell: RepeatCell(range: Range(sheetId: sheetID, startRowIndex: row - 1, endRowIndex: row)))]
    }
}

struct ExpenseSheetUpdate: Encodable {
    let requests: [Request]
    struct Request: Encodable {
        let updateCells: UpdateCells?
        let repeatCell: ExpenseSheetFormat.RepeatCell?
    }
    struct UpdateCells: Encodable {
        let start: Start
        let rows: [Row]
        let fields = "userEnteredValue"
    }
    struct Start: Encodable { let sheetId: Int; let rowIndex: Int; let columnIndex = 1 }
    struct Row: Encodable { let values: [Cell] }
    struct Cell: Encodable { let userEnteredValue: EnteredValue }
    struct EnteredValue: Encodable {
        let stringValue: String?
        let numberValue: Decimal?
        init(_ value: SheetInputValue) {
            switch value {
            case .text(let text): stringValue = text; numberValue = nil
            case .number(let number): stringValue = nil; numberValue = number
            }
        }
    }
    init(values: [SheetInputValue], sheetID: Int, row: Int) {
        let update = UpdateCells(start: Start(sheetId: sheetID, rowIndex: row - 1),
                                 rows: [Row(values: values.map { Cell(userEnteredValue: EnteredValue($0)) })])
        requests = [Request(updateCells: update, repeatCell: nil),
                    Request(updateCells: nil, repeatCell: ExpenseSheetFormat(sheetID: sheetID, row: row).requests[0].repeatCell)]
    }
}
