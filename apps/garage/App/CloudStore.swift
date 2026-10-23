import CloudKit
import Foundation

@MainActor final class CloudStore: ObservableObject {
    @Published var cars: [Car] = []
    @Published var plans: [ServicePlan] = []
    @Published var entries: [ServiceEntry] = []
    @Published var syncMessage: String?
    @Published var loading = false

    let container = CKContainer.default()
    private var privateDB: CKDatabase { container.privateCloudDatabase }
    private var sharedDB: CKDatabase { container.sharedCloudDatabase }
    private var snapshot: LocalSnapshot

    init() {
        let saved = LocalSnapshot.load()
        snapshot = saved
        cars = saved.cars.map(\.car)
        plans = saved.plans.map(\.plan)
        entries = saved.entries.map(\.entry)
    }

    func database(for car: Car) -> CKDatabase { car.isSharedWithMe ? sharedDB : privateDB }
    func canShare(_ car: Car) -> Bool { !snapshot.pendingCars.contains(RecordKey(car.id)) && syncMessage == nil }

    private func persist() {
        snapshot.cars = cars.map(LocalSnapshot.CarData.init)
        snapshot.plans = plans.map(LocalSnapshot.PlanData.init)
        snapshot.entries = entries.map(LocalSnapshot.EntryData.init)
        snapshot.save()
    }

    func reload() async {
        guard !loading else { return }
        loading = true
        defer { loading = false }
        do {
            let status = try await container.accountStatus()
            guard status == .available else { throw GarageError.iCloudUnavailable }
            try await uploadPending()
            var remoteCars: [Car] = []
            var remotePlans: [ServicePlan] = []
            var remoteEntries: [ServiceEntry] = []
            for (database, shared) in [(privateDB, false), (sharedDB, true)] {
                for zone in try await database.allRecordZones() where zone.zoneID.zoneName.hasPrefix("garage-") {
                    let carRecords = try await records(type: "Car", zone: zone.zoneID, database: database)
                    let planRecords = try await records(type: "ServicePlan", zone: zone.zoneID, database: database)
                    let entryRecords = try await records(type: "ServiceEntry", zone: zone.zoneID, database: database)
                    let zoneCars = carRecords.map { Car(id: $0.recordID, name: $0["name"] as? String ?? "Auto", plate: $0["plate"] as? String ?? "", odometer: $0["odometer"] as? Int ?? 0, updatedAt: $0["updatedAt"] as? Date ?? .distantPast, isSharedWithMe: shared) }
                    remoteCars += zoneCars
                    remotePlans += planRecords.compactMap { record in
                        guard let car = zoneCars.first else { return nil }
                        return ServicePlan(id: record.recordID, carID: car.id, title: record["title"] as? String ?? "Servicio", details: record["details"] as? String ?? "", intervalMonths: record["intervalMonths"] as? Int ?? 0, intervalKilometers: record["intervalKilometers"] as? Int ?? 0, lastDate: record["lastDate"] as? Date ?? .now, lastKilometers: record["lastKilometers"] as? Int ?? 0, noticeDays: record["noticeDays"] as? Int ?? 14, noticeKilometers: record["noticeKilometers"] as? Int ?? 500)
                    }
                    remoteEntries += entryRecords.compactMap { record in
                        guard let reference = record["plan"] as? CKRecord.Reference else { return nil }
                        return ServiceEntry(id: record.recordID, planID: reference.recordID, date: record["date"] as? Date ?? .now, kilometers: record["kilometers"] as? Int ?? 0, notes: record["notes"] as? String ?? "")
                    }
                }
            }
            cars = remoteCars.sorted { $0.name < $1.name }
            plans = remotePlans
            entries = remoteEntries.sorted { $0.date > $1.date }
            persist()
            syncMessage = nil
        } catch {
            syncMessage = syncDescription(error)
        }
        await NotificationPlanner.schedule(cars: cars, plans: plans)
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

    private func syncDescription(_ error: Error) -> String {
        if let ck = error as? CKError {
            switch ck.code {
            case .networkUnavailable, .networkFailure: return "iCloud no está disponible. Los cambios quedan en este iPhone y se sincronizarán al recuperar conexión."
            case .notAuthenticated: return "Iniciá sesión en iCloud para sincronizar. Los cambios quedan en este iPhone."
            default: return "Los cambios quedan en este iPhone. iCloud: \(ck.localizedDescription)"
            }
        }
        return "Los cambios quedan en este iPhone. \(error.localizedDescription)"
    }

    private func uploadPending() async throws {
        for key in snapshot.pendingCars.sorted(by: { $0.name < $1.name }) {
            guard let car = cars.first(where: { $0.id == key.id }) else { continue }
            let db = database(for: car)
            if !car.isSharedWithMe {
                if (try? await db.recordZone(for: car.id.zoneID)) == nil {
                    _ = try await db.save(CKRecordZone(zoneID: car.id.zoneID))
                }
            }
            let record = (try? await db.record(for: car.id)) ?? CKRecord(recordType: "Car", recordID: car.id)
            record["name"] = car.name as CKRecordValue
            record["plate"] = car.plate as CKRecordValue
            record["odometer"] = car.odometer as CKRecordValue
            record["updatedAt"] = car.updatedAt as CKRecordValue
            _ = try await db.save(record)
            snapshot.pendingCars.remove(key)
            persist()
        }
        for key in snapshot.pendingPlans.sorted(by: { $0.name < $1.name }) {
            guard let plan = plans.first(where: { $0.id == key.id }), let car = cars.first(where: { $0.id == plan.carID }) else { continue }
            let db = database(for: car)
            let record = (try? await db.record(for: plan.id)) ?? CKRecord(recordType: "ServicePlan", recordID: plan.id)
            record["title"] = plan.title as CKRecordValue
            record["details"] = plan.details as CKRecordValue
            record["intervalMonths"] = plan.intervalMonths as CKRecordValue
            record["intervalKilometers"] = plan.intervalKilometers as CKRecordValue
            record["lastDate"] = plan.lastDate as CKRecordValue
            record["lastKilometers"] = plan.lastKilometers as CKRecordValue
            record["noticeDays"] = plan.noticeDays as CKRecordValue
            record["noticeKilometers"] = plan.noticeKilometers as CKRecordValue
            _ = try await db.save(record)
            snapshot.pendingPlans.remove(key)
            persist()
        }
        for key in snapshot.pendingEntries.sorted(by: { $0.name < $1.name }) {
            guard let entry = entries.first(where: { $0.id == key.id }),
                  let plan = plans.first(where: { $0.id == entry.planID }),
                  let car = cars.first(where: { $0.id == plan.carID }) else { continue }
            let db = database(for: car)
            let record = (try? await db.record(for: entry.id)) ?? CKRecord(recordType: "ServiceEntry", recordID: entry.id)
            record["plan"] = CKRecord.Reference(recordID: plan.id, action: .none)
            record["date"] = entry.date as CKRecordValue
            record["kilometers"] = entry.kilometers as CKRecordValue
            record["notes"] = entry.notes as CKRecordValue
            _ = try await db.save(record)
            snapshot.pendingEntries.remove(key)
            persist()
        }
    }

    private func saveLocallyAndSync() async {
        persist()
        await NotificationPlanner.schedule(cars: cars, plans: plans)
        await reload()
    }

    func addCar(name: String, plate: String, odometer: Int) async {
        let zoneID = CKRecordZone.ID(zoneName: "garage-\(UUID().uuidString)", ownerName: CKCurrentUserDefaultName)
        let id = CKRecord.ID(recordName: "car", zoneID: zoneID)
        cars.append(Car(id: id, name: name, plate: plate, odometer: odometer, updatedAt: .now, isSharedWithMe: false))
        snapshot.pendingCars.insert(RecordKey(id))
        await saveLocallyAndSync()
    }

    func updateOdometer(_ car: Car, kilometers: Int) async {
        guard let index = cars.firstIndex(where: { $0.id == car.id }) else { return }
        cars[index].odometer = kilometers
        cars[index].updatedAt = .now
        snapshot.pendingCars.insert(RecordKey(car.id))
        await saveLocallyAndSync()
    }

    func addPlan(car: Car, title: String, details: String, months: Int, kilometers: Int, lastDate: Date, lastKilometers: Int, noticeDays: Int, noticeKilometers: Int) async {
        let id = CKRecord.ID(recordName: UUID().uuidString, zoneID: car.id.zoneID)
        plans.append(ServicePlan(id: id, carID: car.id, title: title, details: details, intervalMonths: months, intervalKilometers: kilometers, lastDate: lastDate, lastKilometers: lastKilometers, noticeDays: noticeDays, noticeKilometers: noticeKilometers))
        snapshot.pendingPlans.insert(RecordKey(id))
        await saveLocallyAndSync()
    }

    func complete(_ plan: ServicePlan, car: Car, date: Date, kilometers: Int, notes: String) async {
        let id = CKRecord.ID(recordName: UUID().uuidString, zoneID: car.id.zoneID)
        entries.append(ServiceEntry(id: id, planID: plan.id, date: date, kilometers: kilometers, notes: notes))
        snapshot.pendingEntries.insert(RecordKey(id))
        if let index = plans.firstIndex(where: { $0.id == plan.id }) {
            plans[index].lastDate = date
            plans[index].lastKilometers = kilometers
            snapshot.pendingPlans.insert(RecordKey(plan.id))
        }
        if kilometers > car.odometer, let index = cars.firstIndex(where: { $0.id == car.id }) {
            cars[index].odometer = kilometers
            cars[index].updatedAt = .now
            snapshot.pendingCars.insert(RecordKey(car.id))
        }
        await saveLocallyAndSync()
    }
}

enum GarageError: LocalizedError {
    case iCloudUnavailable
    var errorDescription: String? { "Iniciá sesión en iCloud para sincronizar y compartir tus autos." }
}
