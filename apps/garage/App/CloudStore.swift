import CloudKit
import Foundation

@MainActor final class CloudStore: ObservableObject {
    @Published var cars: [Car] = []
    @Published var plans: [ServicePlan] = []
    @Published var entries: [ServiceEntry] = []
    @Published var errorMessage: String?
    @Published var loading = false

    let container = CKContainer.default()
    private var privateDB: CKDatabase { container.privateCloudDatabase }
    private var sharedDB: CKDatabase { container.sharedCloudDatabase }

    func database(for car: Car) -> CKDatabase { car.isSharedWithMe ? sharedDB : privateDB }

    func reload() async {
        loading = true
        defer { loading = false }
        do {
            let status = try await container.accountStatus()
            guard status == .available else { throw GarageError.iCloudUnavailable }
            var allCars: [Car] = []
            var allPlans: [ServicePlan] = []
            var allEntries: [ServiceEntry] = []
            for (database, shared) in [(privateDB, false), (sharedDB, true)] {
                let zones = try await database.allRecordZones()
                for zone in zones where zone.zoneID.zoneName.hasPrefix("garage-") {
                    let carRecords = try await records(type: "Car", zone: zone.zoneID, database: database)
                    let planRecords = try await records(type: "ServicePlan", zone: zone.zoneID, database: database)
                    let entryRecords = try await records(type: "ServiceEntry", zone: zone.zoneID, database: database)
                    allCars += carRecords.map { Car(id: $0.recordID, name: $0["name"] as? String ?? "Auto", plate: $0["plate"] as? String ?? "", odometer: $0["odometer"] as? Int ?? 0, updatedAt: $0["updatedAt"] as? Date ?? .distantPast, isSharedWithMe: shared) }
                    allPlans += planRecords.compactMap { record in
                        guard let car = allCars.last(where: { $0.id.zoneID == zone.zoneID }) else { return nil }
                        return ServicePlan(id: record.recordID, carID: car.id, title: record["title"] as? String ?? "Servicio", details: record["details"] as? String ?? "", intervalMonths: record["intervalMonths"] as? Int ?? 0, intervalKilometers: record["intervalKilometers"] as? Int ?? 0, lastDate: record["lastDate"] as? Date ?? .now, lastKilometers: record["lastKilometers"] as? Int ?? 0, noticeDays: record["noticeDays"] as? Int ?? 14, noticeKilometers: record["noticeKilometers"] as? Int ?? 500)
                    }
                    allEntries += entryRecords.compactMap { record in
                        guard let reference = record["plan"] as? CKRecord.Reference else { return nil }
                        return ServiceEntry(id: record.recordID, planID: reference.recordID, date: record["date"] as? Date ?? .now, kilometers: record["kilometers"] as? Int ?? 0, notes: record["notes"] as? String ?? "")
                    }
                }
            }
            cars = allCars.sorted { $0.name < $1.name }
            plans = allPlans
            entries = allEntries.sorted { $0.date > $1.date }
            await NotificationPlanner.schedule(cars: cars, plans: plans)
        } catch { errorMessage = error.localizedDescription }
    }

    private func records(type: String, zone: CKRecordZone.ID, database: CKDatabase) async throws -> [CKRecord] {
        var result: [CKRecord] = []
        var cursor: CKQueryOperation.Cursor?
        repeat {
            let page: (matchResults: [(CKRecord.ID, Result<CKRecord, Error>)], queryCursor: CKQueryOperation.Cursor?)
            if let cursor { page = try await database.records(continuingMatchFrom: cursor, resultsLimit: 200) }
            else { page = try await database.records(matching: CKQuery(recordType: type, predicate: NSPredicate(value: true)), inZoneWith: zone, resultsLimit: 200) }
            for (_, record) in page.matchResults { result.append(try record.get()) }
            cursor = page.queryCursor
        } while cursor != nil
        return result
    }

    func addCar(name: String, plate: String, odometer: Int) async {
        do {
            let zoneID = CKRecordZone.ID(zoneName: "garage-\(UUID().uuidString)", ownerName: CKCurrentUserDefaultName)
            _ = try await privateDB.save(CKRecordZone(zoneID: zoneID))
            let record = CKRecord(recordType: "Car", recordID: CKRecord.ID(recordName: "car", zoneID: zoneID))
            record["name"] = name as CKRecordValue
            record["plate"] = plate as CKRecordValue
            record["odometer"] = odometer as CKRecordValue
            record["updatedAt"] = Date() as CKRecordValue
            _ = try await privateDB.save(record)
            await reload()
        } catch { errorMessage = error.localizedDescription }
    }

    func updateOdometer(_ car: Car, kilometers: Int) async {
        do {
            let db = database(for: car)
            let record = try await db.record(for: car.id)
            record["odometer"] = kilometers as CKRecordValue
            record["updatedAt"] = Date() as CKRecordValue
            _ = try await db.save(record)
            await reload()
        } catch { errorMessage = error.localizedDescription }
    }

    func addPlan(car: Car, title: String, details: String, months: Int, kilometers: Int, lastDate: Date, lastKilometers: Int, noticeDays: Int, noticeKilometers: Int) async {
        do {
            let record = CKRecord(recordType: "ServicePlan", recordID: CKRecord.ID(recordName: UUID().uuidString, zoneID: car.id.zoneID))
            record["title"] = title as CKRecordValue
            record["details"] = details as CKRecordValue
            record["intervalMonths"] = months as CKRecordValue
            record["intervalKilometers"] = kilometers as CKRecordValue
            record["lastDate"] = lastDate as CKRecordValue
            record["lastKilometers"] = lastKilometers as CKRecordValue
            record["noticeDays"] = noticeDays as CKRecordValue
            record["noticeKilometers"] = noticeKilometers as CKRecordValue
            _ = try await database(for: car).save(record)
            await reload()
        } catch { errorMessage = error.localizedDescription }
    }

    func complete(_ plan: ServicePlan, car: Car, date: Date, kilometers: Int, notes: String) async {
        do {
            let db = database(for: car)
            let entry = CKRecord(recordType: "ServiceEntry", recordID: CKRecord.ID(recordName: UUID().uuidString, zoneID: car.id.zoneID))
            entry["plan"] = CKRecord.Reference(recordID: plan.id, action: .none)
            entry["date"] = date as CKRecordValue
            entry["kilometers"] = kilometers as CKRecordValue
            entry["notes"] = notes as CKRecordValue
            let record = try await db.record(for: plan.id)
            record["lastDate"] = date as CKRecordValue
            record["lastKilometers"] = kilometers as CKRecordValue
            let (results, _) = try await db.modifyRecords(saving: [entry, record], deleting: [], atomically: true)
            for (_, result) in results { _ = try result.get() }
            if kilometers > car.odometer { await updateOdometer(car, kilometers: kilometers) }
            else { await reload() }
        } catch { errorMessage = error.localizedDescription }
    }
}

enum GarageError: LocalizedError {
    case iCloudUnavailable
    var errorDescription: String? { "Iniciá sesión en iCloud para sincronizar y compartir tus autos." }
}
