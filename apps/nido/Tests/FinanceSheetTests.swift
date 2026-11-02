import Foundation

@main struct FinanceSheetTests {
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        precondition(condition(), message)
    }

    static func main() throws {
        let initial = try FinanceSheetCatalog(
            budgetRows: [["Mascotas de prueba", "Alimento y veterinaria", "0", "0", "Fijo"],
                         ["Transporte familiar", "Vehículos", "1250.50", "15006", "Fijo"]],
            payerRows: [["Persona nueva"], ["Fondo familiar"], []],
            vehicleCategory: "Transporte familiar", sharedPayer: "Fondo familiar")
        require(initial.categoryNames == ["Mascotas de prueba", "Transporte familiar"], "Use exact spreadsheet names/order")
        require(initial.budgets["Mascotas de prueba"] == 0, "Zero-budget categories must remain selectable")
        require(initial.budgets["Transporte familiar"] == Decimal(string: "1250.50"), "Keep decimal budgets")
        require(initial.payers == ["Persona nueva", "Fondo familiar"], "Payers must come from the sheet")
        require(initial.voiceDefinitions.contains("Alimento y veterinaria"), "Voice descriptions must come from budget data")

        let changed = try FinanceSheetCatalog(
            budgetRows: [["Nueva categoría", "Descripción nueva", "800", "9600"],
                         ["Transporte familiar", "Vehículos", "1500", "18000"]],
            payerRows: [["Otra persona"], ["Fondo familiar"]],
            vehicleCategory: "Transporte familiar", sharedPayer: "Fondo familiar")
        require(!changed.categoryNames.contains("Mascotas de prueba"), "Removed categories must disappear after reload")
        require(changed.budgets["Nueva categoría"] == 800, "New categories need no app changes")
        require(changed.payers.first == "Otra persona", "Payer changes need no app changes")
        require(changed.voiceDefinitions.contains("Descripción nueva"), "Reload voice definitions too")

        for rows in [[], [["X", "", "#REF!", "0"]], [["X", "", "0", "0"], ["X", "", "1", "1"]]] as [[[String]]] {
            do {
                _ = try FinanceSheetCatalog(budgetRows: rows, payerRows: [["P"]], vehicleCategory: "X", sharedPayer: "P")
                preconditionFailure("Invalid or duplicate budget must not silently become zero or a built-in catalog")
            } catch FinanceSheetError.invalidBudget { }
        }

        let iso = ISO8601DateFormatter()
        let midnightUTC = iso.date(from: "2026-11-02T02:30:00Z")!
        require(FamilyBudget.dateString(from: midnightUTC) == "2026-11-01", "Voice today must use the same Buenos Aires day as stored expenses")
        require(FamilyBudget.serial(from: midnightUTC) == 46327, "Date must use the Buenos Aires calendar day")
        let date = FamilyBudget.date(from: 46327)
        let parts = FamilyBudget.calendar.dateComponents([.year, .month, .day], from: date)
        require(parts.year == 2026 && parts.month == 11 && parts.day == 1, "Decode the stored serial as November 1")
        require(FamilyBudget.serial(from: date) == 46327, "Round-trip a Sheets date without day drift")

        let payload: [SheetInputValue] = [.number(Decimal(FamilyBudget.serial(from: date))), .text("=literal, not a formula"), .number(Decimal(string: "1250.50")!)]
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(payload)) as! [Any]
        require(json[0] is NSNumber && (json[0] as! NSNumber).intValue == 46327, "Send a numeric date with RAW input")
        require(json[1] as? String == "=literal, not a formula", "Preserve user descriptions literally")
        require((json[2] as! NSNumber).decimalValue == Decimal(string: "1250.50"), "Send a numeric amount, independent of locale")
        let format = try JSONSerialization.jsonObject(with: JSONEncoder().encode(ExpenseSheetFormat(sheetID: 123, row: 8))) as! [String: Any]
        let request = ((format["requests"] as! [[String: Any]])[0]["repeatCell"] as! [String: Any])
        let range = request["range"] as! [String: Any]
        require(range["startRowIndex"] as? Int == 7 && range["endRowIndex"] as? Int == 8, "Format the exact written row")
        require(range["startColumnIndex"] as? Int == 1 && range["endColumnIndex"] as? Int == 2, "Format only the date column")
        require(request["fields"] as? String == "userEnteredFormat.numberFormat", "Preserve unrelated cell state")
        let edit = try JSONSerialization.jsonObject(with: JSONEncoder().encode(ExpenseSheetUpdate(values: payload, sheetID: 123, row: 8))) as! [String: Any]
        let editRequests = edit["requests"] as! [[String: Any]]
        require(editRequests.count == 2 && editRequests[1]["repeatCell"] != nil, "Edit values and date format atomically")
        let update = editRequests[0]["updateCells"] as! [String: Any]
        let updateRows = update["rows"] as! [[String: Any]]
        let cells = updateRows[0]["values"] as! [[String: Any]]
        require((cells[0]["userEnteredValue"] as! [String: Any])["numberValue"] as? Int == 46327, "Edited dates remain numeric")
        require((cells[1]["userEnteredValue"] as! [String: Any])["stringValue"] as? String == "=literal, not a formula", "Edits cannot turn user input into a formula")
        print("FinanceSheet tests passed: dynamic catalog, budgets, payers, voice definitions, invalid data, dates and typed writes")
    }
}
