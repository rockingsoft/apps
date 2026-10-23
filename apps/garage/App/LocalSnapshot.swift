import CloudKit
import Foundation

struct RecordKey: Codable, Hashable {
    let name: String
    let zone: String
    let owner: String
    init(_ id: CKRecord.ID) {
        name = id.recordName
        zone = id.zoneID.zoneName
        owner = id.zoneID.ownerName
    }
    var id: CKRecord.ID { CKRecord.ID(recordName: name, zoneID: CKRecordZone.ID(zoneName: zone, ownerName: owner)) }
}

struct LocalSnapshot: Codable {
    struct PendingDeletion: Codable, Hashable {
        let car: RecordKey
        let sharedWithMe: Bool
    }
    struct PendingFuelDeletion: Codable, Hashable {
        let entry: RecordKey
        let sharedWithMe: Bool
    }
    struct CarData: Codable {
        let id: RecordKey
        var name: String
        var plate: String
        var odometer: Int
        var updatedAt: Date
        var shared: Bool
        init(_ car: Car) { id = RecordKey(car.id); name = car.name; plate = car.plate; odometer = car.odometer; updatedAt = car.updatedAt; shared = car.isSharedWithMe }
        var car: Car { Car(id: id.id, name: name, plate: plate, odometer: odometer, updatedAt: updatedAt, isSharedWithMe: shared) }
    }
    struct PlanData: Codable {
        let id: RecordKey
        let carID: RecordKey
        var title: String
        var details: String
        var intervalMonths: Int
        var intervalKilometers: Int
        var lastDate: Date
        var lastKilometers: Int
        var noticeDays: Int
        var noticeKilometers: Int
        var sourceURL: String?
        var templateRuleID: String?
        var baselineUnknown: Bool?
        init(_ plan: ServicePlan) {
            id = RecordKey(plan.id); carID = RecordKey(plan.carID); title = plan.title; details = plan.details
            intervalMonths = plan.intervalMonths; intervalKilometers = plan.intervalKilometers
            lastDate = plan.lastDate; lastKilometers = plan.lastKilometers
            noticeDays = plan.noticeDays; noticeKilometers = plan.noticeKilometers
            sourceURL = plan.sourceURL; templateRuleID = plan.templateRuleID
            baselineUnknown = plan.baselineUnknown
        }
        var plan: ServicePlan { ServicePlan(id: id.id, carID: carID.id, title: title, details: details, intervalMonths: intervalMonths, intervalKilometers: intervalKilometers, lastDate: lastDate, lastKilometers: lastKilometers, noticeDays: noticeDays, noticeKilometers: noticeKilometers, sourceURL: sourceURL, templateRuleID: templateRuleID, baselineUnknown: baselineUnknown ?? false) }
    }
    struct EntryData: Codable {
        let id: RecordKey
        let planID: RecordKey
        var date: Date
        var kilometers: Int
        var notes: String
        init(_ entry: ServiceEntry) { id = RecordKey(entry.id); planID = RecordKey(entry.planID); date = entry.date; kilometers = entry.kilometers; notes = entry.notes }
        var entry: ServiceEntry { ServiceEntry(id: id.id, planID: planID.id, date: date, kilometers: kilometers, notes: notes) }
    }
    struct FuelData: Codable {
        let id: RecordKey
        let carID: RecordKey
        var date: Date
        var kilometers: Int
        var liters: Decimal
        var pricePerLiter: Decimal
        var stationName: String
        var latitude: Double?
        var longitude: Double?
        init(_ entry: FuelEntry) {
            id = RecordKey(entry.id); carID = RecordKey(entry.carID); date = entry.date
            kilometers = entry.kilometers; liters = entry.liters; pricePerLiter = entry.pricePerLiter
            stationName = entry.stationName; latitude = entry.latitude; longitude = entry.longitude
        }
        var entry: FuelEntry {
            FuelEntry(id: id.id, carID: carID.id, date: date, kilometers: kilometers, liters: liters,
                      pricePerLiter: pricePerLiter, stationName: stationName, latitude: latitude, longitude: longitude)
        }
    }
    var cars: [CarData] = []
    var plans: [PlanData] = []
    var entries: [EntryData] = []
    var pendingCars: Set<RecordKey> = []
    var pendingPlans: Set<RecordKey> = []
    var pendingEntries: Set<RecordKey> = []
    // Optional so snapshots saved before deletion support was added still decode.
    var pendingDeletions: Set<PendingDeletion>? = nil
    // Optional so snapshots written before fuel logging still decode.
    var fuelEntries: [FuelData]? = nil
    var pendingFuelEntries: Set<RecordKey>? = nil
    var pendingFuelDeletions: Set<PendingFuelDeletion>? = nil

    static func load() -> LocalSnapshot {
        guard let data = UserDefaults.standard.data(forKey: "garage.localSnapshot"),
              let snapshot = try? JSONDecoder().decode(LocalSnapshot.self, from: data) else { return LocalSnapshot() }
        return snapshot
    }
    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: "garage.localSnapshot")
    }
}
