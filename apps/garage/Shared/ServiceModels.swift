import Foundation
import CloudKit

struct Car: Identifiable, Hashable {
    let id: CKRecord.ID
    var name: String
    var plate: String
    var odometer: Int
    var updatedAt: Date
    var isSharedWithMe: Bool
}

struct ServicePlan: Identifiable, Hashable {
    let id: CKRecord.ID
    let carID: CKRecord.ID
    var title: String
    var details: String
    var intervalMonths: Int
    var intervalKilometers: Int
    var lastDate: Date
    var lastKilometers: Int
    var noticeDays: Int
    var noticeKilometers: Int
    var sourceURL: String? = nil
    var templateRuleID: String? = nil
    var baselineUnknown = false

    func status(odometer: Int, now: Date = .now) -> ServiceStatus {
        if baselineUnknown { return .overdue }
        let dueDate = intervalMonths > 0 ? Calendar.current.date(byAdding: .month, value: intervalMonths, to: lastDate) : nil
        let dueKM = intervalKilometers > 0 ? lastKilometers + intervalKilometers : nil
        let overdue = (dueDate.map { $0 <= now } ?? false) || (dueKM.map { $0 <= odometer } ?? false)
        let soon = (dueDate.map { $0 <= Calendar.current.date(byAdding: .day, value: noticeDays, to: now)! } ?? false) || (dueKM.map { $0 <= odometer + noticeKilometers } ?? false)
        return overdue ? .overdue : (soon ? .soon : .ok)
    }

    var nextDate: Date? { !baselineUnknown && intervalMonths > 0 ? Calendar.current.date(byAdding: .month, value: intervalMonths, to: lastDate) : nil }
    var nextKilometers: Int? { !baselineUnknown && intervalKilometers > 0 ? lastKilometers + intervalKilometers : nil }
}

enum ServiceStatus: String { case overdue = "Vencido", soon = "Próximo", ok = "Al día" }

struct ServiceEntry: Identifiable, Hashable {
    let id: CKRecord.ID
    let planID: CKRecord.ID
    var date: Date
    var kilometers: Int
    var notes: String
}

struct FuelEntry: Identifiable, Hashable {
    let id: CKRecord.ID
    let carID: CKRecord.ID
    var date: Date
    var kilometers: Int
    var liters: Decimal
    var pricePerLiter: Decimal
    var stationName: String
    var latitude: Double?
    var longitude: Double?

    var total: Decimal { liters * pricePerLiter }
    var totalDescription: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale(identifier: "es_AR")
        formatter.currencyCode = "ARS"
        return formatter.string(from: NSDecimalNumber(decimal: total)) ?? "$ \(total)"
    }
}
