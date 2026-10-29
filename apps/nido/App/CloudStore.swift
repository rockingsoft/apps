import CloudKit
import CryptoKit
import Foundation
import Network

struct FamilyMember {
    let id: CKRecord.ID
    let userRecordName: String
    let payerName: String
    let updatedAt: Date
}

@MainActor final class CloudStore: ObservableObject {
    @Published var cars: [Car] = []
    @Published var plans: [ServicePlan] = []
    @Published var entries: [ServiceEntry] = []
    @Published var fuelEntries: [FuelEntry] = []
    @Published var expensePlaces: [ExpensePlace] = []
    @Published var familyMembers: [FamilyMember] = []
    @Published private(set) var localPayerName: String?
    @Published private(set) var activeMemberIDs = Set<String>()
    @Published private(set) var myUserRecordName: String?
    @Published var syncMessage: String?
    @Published var shareError: String?
    @Published var loading = false
    @Published private(set) var familyZoneID: CKRecordZone.ID?
    @Published private(set) var familyZoneSharedWithMe = false
    private var reloadRequested = false
    private let networkMonitor = NWPathMonitor()

    let container = CKContainer.default()
    private var privateDB: CKDatabase { container.privateCloudDatabase }
    private var sharedDB: CKDatabase { container.sharedCloudDatabase }
    private let familyZoneName = "garage-family-v1"
    private var snapshot: LocalSnapshot

    init() {
        let saved = LocalSnapshot.load()
        snapshot = saved
        localPayerName = UserDefaults.standard.string(forKey: "garage.myPayerName")
        cars = saved.cars.map(\.car)
        plans = saved.plans.map(\.plan)
        entries = saved.entries.map(\.entry)
        fuelEntries = (saved.fuelEntries ?? []).map(\.entry)
        expensePlaces = (saved.expensePlaces ?? []).map(\.place)
        familyMembers = (saved.familyMembers ?? []).map(\.member)
        networkMonitor.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            Task { @MainActor [weak self] in
                guard let self, self.hasPendingChanges else { return }
                await self.reload()
            }
        }
        networkMonitor.start(queue: DispatchQueue(label: "garage.network"))
    }

    private var hasPendingChanges: Bool {
        !snapshot.pendingCars.isEmpty || !snapshot.pendingPlans.isEmpty || !snapshot.pendingEntries.isEmpty ||
        !(snapshot.pendingDeletions ?? []).isEmpty || !(snapshot.pendingFuelEntries ?? []).isEmpty ||
        !(snapshot.pendingFuelDeletions ?? []).isEmpty || !(snapshot.pendingExpensePlaces ?? []).isEmpty ||
        !(snapshot.pendingExpensePlaceDeletions ?? []).isEmpty ||
        !(snapshot.pendingFamilyMembers ?? []).isEmpty
    }

    func database(for car: Car) -> CKDatabase { car.isSharedWithMe ? sharedDB : privateDB }
    func canShare(_ car: Car) -> Bool { !snapshot.pendingCars.contains(RecordKey(car.id)) && syncMessage == nil }
    var canShareFamily: Bool { familyZoneID != nil && !familyZoneSharedWithMe && syncMessage == nil && !hasPendingChanges }
    var myPayerName: String? {
        if let myUserRecordName,
           let member = familyMembers.first(where: { $0.userRecordName == myUserRecordName }) {
            return member.payerName
        }
        return localPayerName
    }
    var activePayers: [String] {
        let available = FamilyBudget.payers.filter { name in
            name == "Común" || name == localPayerName ||
                familyMembers.contains { activeMemberIDs.contains($0.userRecordName) && $0.payerName == name }
        }
        return available.count == 1 ? FamilyBudget.payers : available
    }
    var familySpace: Car? {
        guard let familyZoneID else { return nil }
        return Car(id: CKRecord.ID(recordName: "family-space", zoneID: familyZoneID), name: "Nido familiar",
                   plate: "", odometer: 0, updatedAt: .now, isSharedWithMe: familyZoneSharedWithMe)
    }

    private func persist() {
        snapshot.cars = cars.map(LocalSnapshot.CarData.init)
        snapshot.plans = plans.map(LocalSnapshot.PlanData.init)
        snapshot.entries = entries.map(LocalSnapshot.EntryData.init)
        snapshot.fuelEntries = fuelEntries.map(LocalSnapshot.FuelData.init)
        snapshot.expensePlaces = expensePlaces.map(LocalSnapshot.ExpensePlaceData.init)
        snapshot.familyMembers = familyMembers.map(LocalSnapshot.FamilyMemberData.init)
        snapshot.save()
    }

    func reload() async {
        guard !loading else { reloadRequested = true; return }
        loading = true
        defer {
            loading = false
            if reloadRequested {
                reloadRequested = false
                Task { await self.reload() }
            }
        }
        do {
            let status = try await container.accountStatus()
            guard status == .available else { throw NidoError.iCloudUnavailable }
            try await prepareFamilyZone()
            await refreshFamilyParticipants()
            try await uploadPending()
            try await migrateLegacyZones()
            var remoteCars: [Car] = []
            var remotePlans: [ServicePlan] = []
            var remoteEntries: [ServiceEntry] = []
            var remoteFuelEntries: [FuelEntry] = []
            var remoteExpensePlaces: [ExpensePlace] = []
            var remoteFamilyMembers: [FamilyMember] = []
            var migrationMarkers = Set<String>()
            for (database, shared) in [(privateDB, false), (sharedDB, true)] {
                for zone in try await database.allRecordZones()
                    where (shared || zone.zoneID.zoneName.hasPrefix("garage-")) &&
                    (zone.zoneID.zoneName != familyZoneName || zone.zoneID == familyZoneID) {
                    let allRecords = try await records(in: zone.zoneID, database: database)
                    migrationMarkers.formUnion(allRecords.filter { $0.recordType == "LegacyMigration" }.map { $0.recordID.recordName })
                    let carRecords = allRecords.filter { $0.recordType == "Car" }
                    let planRecords = allRecords.filter { $0.recordType == "ServicePlan" }
                    let entryRecords = allRecords.filter { $0.recordType == "ServiceEntry" }
                    let fuelRecords = allRecords.filter { $0.recordType == "FuelEntry" }
                    let placeRecords = allRecords.filter { $0.recordType == "ExpensePlace" }
                    if zone.zoneID == familyZoneID {
                        remoteFamilyMembers += allRecords.filter { $0.recordType == "FamilyMember" }.compactMap { record in
                            guard let userRecordName = record["userRecordName"] as? String,
                                  let payerName = record["payerName"] as? String else { return nil }
                            return FamilyMember(id: record.recordID, userRecordName: userRecordName,
                                                payerName: payerName, updatedAt: record["updatedAt"] as? Date ?? .distantPast)
                        }
                    }
                    let zoneCars = carRecords.map { record in
                        let details = (record["detailsJSON"] as? String).flatMap { $0.data(using: .utf8) }
                            .flatMap { try? JSONDecoder().decode([CarDetail].self, from: $0) } ?? []
                        return Car(id: record.recordID, name: record["name"] as? String ?? "Auto",
                                   plate: record["plate"] as? String ?? "", odometer: record["odometer"] as? Int ?? 0,
                                   updatedAt: record["updatedAt"] as? Date ?? .distantPast,
                                   isSharedWithMe: shared, details: details)
                    }
                    remoteCars += zoneCars
                    remotePlans += planRecords.compactMap { record in
                        guard let car = (record["car"] as? CKRecord.Reference).flatMap({ ref in zoneCars.first { $0.id == ref.recordID } }) ?? zoneCars.first else { return nil }
                        return ServicePlan(id: record.recordID, carID: car.id, title: record["title"] as? String ?? "Servicio", details: record["details"] as? String ?? "", intervalMonths: record["intervalMonths"] as? Int ?? 0, intervalKilometers: record["intervalKilometers"] as? Int ?? 0, lastDate: record["lastDate"] as? Date ?? .now, lastKilometers: record["lastKilometers"] as? Int ?? 0, noticeDays: record["noticeDays"] as? Int ?? 14, noticeKilometers: record["noticeKilometers"] as? Int ?? 500, sourceURL: record["sourceURL"] as? String, templateRuleID: record["templateRuleID"] as? String, baselineUnknown: record["baselineUnknown"] as? Bool ?? false)
                    }
                    remoteEntries += entryRecords.compactMap { record in
                        guard let reference = record["plan"] as? CKRecord.Reference else { return nil }
                        return ServiceEntry(id: record.recordID, planID: reference.recordID, date: record["date"] as? Date ?? .now, kilometers: record["kilometers"] as? Int ?? 0, notes: record["notes"] as? String ?? "")
                    }
                    remoteFuelEntries += fuelRecords.compactMap { record in
                        guard let car = (record["car"] as? CKRecord.Reference).flatMap({ ref in zoneCars.first { $0.id == ref.recordID } }) ?? zoneCars.first,
                              let liters = Decimal(string: record["liters"] as? String ?? "", locale: Locale(identifier: "en_US_POSIX")),
                              let price = Decimal(string: record["pricePerLiter"] as? String ?? "", locale: Locale(identifier: "en_US_POSIX")) else { return nil }
                        return FuelEntry(id: record.recordID, carID: car.id, date: record["date"] as? Date ?? .now,
                                         kilometers: record["kilometers"] as? Int ?? 0, liters: liters,
                                         pricePerLiter: price, stationName: record["stationName"] as? String ?? "Estación",
                                         latitude: record["latitude"] as? Double, longitude: record["longitude"] as? Double)
                    }
                    remoteExpensePlaces += placeRecords.compactMap { record in
                        guard let expenseID = record["expenseID"] as? String,
                              let latitude = record["latitude"] as? Double,
                              let longitude = record["longitude"] as? Double else { return nil }
                        return ExpensePlace(id: record.recordID, expenseID: expenseID,
                                            category: record["category"] as? String ?? "",
                                            detail: record["detail"] as? String ?? "",
                                            latitude: latitude, longitude: longitude,
                                            recordedAt: record["recordedAt"] as? Date ?? .distantPast)
                    }
                }
            }
            let incompleteCars = Set(remoteCars.filter { $0.id.zoneID.zoneName == familyZoneName &&
                $0.id.recordName.hasPrefix("legacy-") && !migrationMarkers.contains("migration-\($0.id.recordName)") }
                .map(\.id))
            remoteCars.removeAll { incompleteCars.contains($0.id) }
            let incompletePlans = Set(remotePlans.filter { incompleteCars.contains($0.carID) }.map(\.id))
            remotePlans.removeAll { incompletePlans.contains($0.id) }
            remoteEntries.removeAll { incompletePlans.contains($0.planID) }
            remoteFuelEntries.removeAll { incompleteCars.contains($0.carID) }
            let migratedZones = Set(remoteCars.filter { $0.id.zoneID.zoneName != familyZoneName &&
                migrationMarkers.contains("migration-\(migratedRecordName($0.id))") }
                .map { $0.id.zoneID })
            remoteCars.removeAll { migratedZones.contains($0.id.zoneID) }
            remotePlans.removeAll { migratedZones.contains($0.id.zoneID) }
            remoteEntries.removeAll { migratedZones.contains($0.id.zoneID) }
            remoteFuelEntries.removeAll { migratedZones.contains($0.id.zoneID) }
            let pendingDeletedCars = Set((snapshot.pendingDeletions ?? []).map { $0.car.id })
            let deletedZones = Set((snapshot.pendingDeletions ?? []).filter { $0.car.zone != familyZoneName }.map { $0.car.id.zoneID })
            let deletedPlanIDs = Set(remotePlans.filter { pendingDeletedCars.contains($0.carID) }.map(\.id))
            let pendingCarIDs = Set(snapshot.pendingCars.map(\.id))
            let pendingPlanIDs = Set(snapshot.pendingPlans.map(\.id))
            let pendingEntryIDs = Set(snapshot.pendingEntries.map(\.id))
            let pendingFuelIDs = Set((snapshot.pendingFuelEntries ?? []).map(\.id))
            cars = (remoteCars.filter { !deletedZones.contains($0.id.zoneID) && !pendingDeletedCars.contains($0.id) && !pendingCarIDs.contains($0.id) } +
                    cars.filter { pendingCarIDs.contains($0.id) && !deletedZones.contains($0.id.zoneID) })
                .sorted { $0.name < $1.name }
            plans = remotePlans.filter { !deletedZones.contains($0.id.zoneID) && !pendingDeletedCars.contains($0.carID) && !pendingPlanIDs.contains($0.id) } +
                    plans.filter { pendingPlanIDs.contains($0.id) && !deletedZones.contains($0.id.zoneID) }
            entries = (remoteEntries.filter { !deletedZones.contains($0.id.zoneID) && !deletedPlanIDs.contains($0.planID) && !pendingEntryIDs.contains($0.id) } +
                       entries.filter { pendingEntryIDs.contains($0.id) && !deletedZones.contains($0.id.zoneID) })
                .sorted { $0.date > $1.date }
            let pendingFuelDeletionIDs = Set((snapshot.pendingFuelDeletions ?? []).map { $0.entry.id })
            fuelEntries = (remoteFuelEntries.filter {
                !deletedZones.contains($0.id.zoneID) && !pendingDeletedCars.contains($0.carID) && !pendingFuelDeletionIDs.contains($0.id) && !pendingFuelIDs.contains($0.id)
            } + fuelEntries.filter {
                pendingFuelIDs.contains($0.id) && !deletedZones.contains($0.id.zoneID) && !pendingFuelDeletionIDs.contains($0.id)
            }).sorted { $0.date > $1.date }
            let pendingPlaceIDs = Set((snapshot.pendingExpensePlaces ?? []).map(\.id))
            let deletedPlaceIDs = Set((snapshot.pendingExpensePlaceDeletions ?? []).map { $0.place.id })
            expensePlaces = remoteExpensePlaces.filter { !pendingPlaceIDs.contains($0.id) && !deletedPlaceIDs.contains($0.id) } +
                expensePlaces.filter { pendingPlaceIDs.contains($0.id) }
            let pendingMemberIDs = Set((snapshot.pendingFamilyMembers ?? []).map(\.id))
            familyMembers = remoteFamilyMembers.filter { !pendingMemberIDs.contains($0.id) } +
                familyMembers.filter { pendingMemberIDs.contains($0.id) }
            if let myUserRecordName,
               let profile = familyMembers.first(where: { $0.userRecordName == myUserRecordName }),
               localPayerName != profile.payerName {
                localPayerName = profile.payerName
                UserDefaults.standard.set(profile.payerName, forKey: "garage.myPayerName")
            }
            ExpenseVisitMonitor.shared.updatePlaces(expensePlaces)
            persist()
            syncMessage = nil
        } catch {
            syncMessage = syncDescription(error)
        }
        await NotificationPlanner.schedule(cars: cars, plans: plans)
    }

    private func records(in zone: CKRecordZone.ID, database: CKDatabase) async throws -> [CKRecord] {
        var result: [CKRecord.ID: CKRecord] = [:]
        var token: CKServerChangeToken?
        var moreComing: Bool
        repeat {
            let batch = try await database.recordZoneChanges(inZoneWith: zone, since: token)
            for (id, modification) in batch.modificationResultsByID {
                result[id] = try modification.get().record
            }
            for deletion in batch.deletions { result.removeValue(forKey: deletion.recordID) }
            token = batch.changeToken
            moreComing = batch.moreComing
        } while moreComing
        return Array(result.values)
    }

    private func prepareFamilyZone() async throws {
        let ownID = CKRecordZone.ID(zoneName: familyZoneName, ownerName: CKCurrentUserDefaultName)
        let ownZones = try await privateDB.allRecordZones()
        if let shared = try await sharedDB.allRecordZones().first(where: { $0.zoneID.zoneName == familyZoneName }) {
            familyZoneID = shared.zoneID
            familyZoneSharedWithMe = true
            return
        }
        if ownZones.contains(where: { $0.zoneID == ownID }) {
            familyZoneID = ownID
            familyZoneSharedWithMe = false
            return
        }
        _ = try await privateDB.save(CKRecordZone(zoneID: ownID))
        familyZoneID = ownID
        familyZoneSharedWithMe = false
    }

    private func migratedRecordName(_ id: CKRecord.ID) -> String {
        let source = "\(id.zoneID.ownerName)/\(id.zoneID.zoneName)/\(id.recordName)"
        let digest = SHA256.hash(data: Data(source.utf8)).map { String(format: "%02x", $0) }.joined()
        return "legacy-\(digest)"
    }

    private func migrateLegacyZones() async throws {
        guard let familyZoneID else { return }
        let destination = familyZoneSharedWithMe ? sharedDB : privateDB
        for source in [privateDB, sharedDB] {
            for zone in try await source.allRecordZones()
                where zone.zoneID.zoneName.hasPrefix("garage-") && zone.zoneID != familyZoneID {
                let oldRecords = try await records(in: zone.zoneID, database: source)
                for oldCar in oldRecords where oldCar.recordType == "Car" {
                let newCarID = CKRecord.ID(recordName: migratedRecordName(oldCar.recordID), zoneID: familyZoneID)
                let markerID = CKRecord.ID(recordName: "migration-\(newCarID.recordName)", zoneID: familyZoneID)
                if (try? await destination.record(for: markerID)) != nil { continue }
                if (try? await destination.record(for: newCarID)) == nil {
                    let newCar = CKRecord(recordType: "Car", recordID: newCarID)
                    for field in ["name", "plate", "odometer", "updatedAt"] { newCar[field] = oldCar[field] }
                    newCar["legacyZone"] = zone.zoneID.zoneName as CKRecordValue
                    _ = try await destination.save(newCar)
                }
                let sourceHasOneCar = oldRecords.filter { $0.recordType == "Car" }.count == 1
                let children = oldRecords.filter { record in
                    guard record.recordType == "ServicePlan" || record.recordType == "FuelEntry" else { return false }
                    return (record["car"] as? CKRecord.Reference)?.recordID == oldCar.recordID ||
                        (sourceHasOneCar && record["car"] == nil)
                }
                for record in children {
                    let newID = CKRecord.ID(recordName: migratedRecordName(record.recordID), zoneID: familyZoneID)
                    if (try? await destination.record(for: newID)) != nil { continue }
                    let copy = CKRecord(recordType: record.recordType, recordID: newID)
                    for key in record.allKeys() { copy[key] = record[key] }
                    copy["car"] = CKRecord.Reference(recordID: newCarID, action: .none)
                    _ = try await destination.save(copy)
                }
                let oldPlanIDs = Set(children.filter { $0.recordType == "ServicePlan" }.map(\.recordID))
                for record in oldRecords where record.recordType == "ServiceEntry" &&
                    oldPlanIDs.contains((record["plan"] as? CKRecord.Reference)?.recordID ?? oldCar.recordID) {
                    let newID = CKRecord.ID(recordName: migratedRecordName(record.recordID), zoneID: familyZoneID)
                    if (try? await destination.record(for: newID)) != nil { continue }
                    let copy = CKRecord(recordType: "ServiceEntry", recordID: newID)
                    for key in record.allKeys() { copy[key] = record[key] }
                    if let oldPlan = record["plan"] as? CKRecord.Reference {
                        copy["plan"] = CKRecord.Reference(recordID: CKRecord.ID(recordName: migratedRecordName(oldPlan.recordID), zoneID: familyZoneID), action: .none)
                    }
                    _ = try await destination.save(copy)
                }
                let marker = CKRecord(recordType: "LegacyMigration", recordID: markerID)
                marker["sourceZone"] = zone.zoneID.zoneName as CKRecordValue
                marker["sourceOwner"] = zone.zoneID.ownerName as CKRecordValue
                _ = try await destination.save(marker)
                }
            }
        }
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
        for deletion in (snapshot.pendingDeletions ?? []).sorted(by: { $0.car.zone < $1.car.zone }) {
            do {
                if deletion.car.zone == familyZoneName {
                    let database = deletion.sharedWithMe ? sharedDB : privateDB
                    let records = try await records(in: deletion.car.id.zoneID, database: database)
                    let planIDs = Set(records.filter { ($0["car"] as? CKRecord.Reference)?.recordID == deletion.car.id && $0.recordType == "ServicePlan" }.map(\.recordID))
                    let children = records.filter { ($0["car"] as? CKRecord.Reference)?.recordID == deletion.car.id ||
                        ( $0.recordType == "ServiceEntry" && planIDs.contains(($0["plan"] as? CKRecord.Reference)?.recordID ?? deletion.car.id)) }
                    for record in children { _ = try await database.deleteRecord(withID: record.recordID) }
                    _ = try await database.deleteRecord(withID: deletion.car.id)
                } else if deletion.sharedWithMe {
                    let shareID = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: deletion.car.id.zoneID)
                    _ = try await sharedDB.deleteRecord(withID: shareID)
                } else {
                    _ = try await privateDB.deleteRecordZone(withID: deletion.car.id.zoneID)
                }
            } catch let error as CKError where error.code == .zoneNotFound || error.code == .unknownItem {
                // The car only existed locally, or was already deleted in iCloud.
            }
            snapshot.pendingDeletions?.remove(deletion)
            persist()
        }
        for deletion in (snapshot.pendingFuelDeletions ?? []).sorted(by: { $0.entry.name < $1.entry.name }) {
            do {
                let database = deletion.sharedWithMe ? sharedDB : privateDB
                _ = try await database.deleteRecord(withID: deletion.entry.id)
            } catch let error as CKError where error.code == .unknownItem || error.code == .zoneNotFound {
                // The entry only existed locally, or was already removed.
            }
            snapshot.pendingFuelDeletions?.remove(deletion)
            persist()
        }
        for deletion in (snapshot.pendingExpensePlaceDeletions ?? []).sorted(by: { $0.place.name < $1.place.name }) {
            do {
                let database = deletion.sharedWithMe ? sharedDB : privateDB
                _ = try await database.deleteRecord(withID: deletion.place.id)
            } catch let error as CKError where error.code == .unknownItem || error.code == .zoneNotFound {
                // The place only existed locally, or was already removed.
            }
            snapshot.pendingExpensePlaceDeletions?.remove(deletion)
            persist()
        }
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
            record["detailsJSON"] = String(decoding: try JSONEncoder().encode(car.details), as: UTF8.self) as CKRecordValue
            _ = try await db.save(record)
            snapshot.pendingCars.remove(key)
            persist()
        }
        for key in snapshot.pendingPlans.sorted(by: { $0.name < $1.name }) {
            guard let plan = plans.first(where: { $0.id == key.id }), let car = cars.first(where: { $0.id == plan.carID }) else { continue }
            let db = database(for: car)
            let record = (try? await db.record(for: plan.id)) ?? CKRecord(recordType: "ServicePlan", recordID: plan.id)
            record["title"] = plan.title as CKRecordValue
            record["car"] = CKRecord.Reference(recordID: car.id, action: .none)
            record["details"] = plan.details as CKRecordValue
            record["intervalMonths"] = plan.intervalMonths as CKRecordValue
            record["intervalKilometers"] = plan.intervalKilometers as CKRecordValue
            record["lastDate"] = plan.lastDate as CKRecordValue
            record["lastKilometers"] = plan.lastKilometers as CKRecordValue
            record["noticeDays"] = plan.noticeDays as CKRecordValue
            record["noticeKilometers"] = plan.noticeKilometers as CKRecordValue
            if let sourceURL = plan.sourceURL { record["sourceURL"] = sourceURL as CKRecordValue }
            if let templateRuleID = plan.templateRuleID { record["templateRuleID"] = templateRuleID as CKRecordValue }
            record["baselineUnknown"] = plan.baselineUnknown as CKRecordValue
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
            record["car"] = CKRecord.Reference(recordID: car.id, action: .none)
            record["kilometers"] = entry.kilometers as CKRecordValue
            record["notes"] = entry.notes as CKRecordValue
            _ = try await db.save(record)
            snapshot.pendingEntries.remove(key)
            persist()
        }
        for key in (snapshot.pendingFuelEntries ?? []).sorted(by: { $0.name < $1.name }) {
            guard let entry = fuelEntries.first(where: { $0.id == key.id }),
                  let car = cars.first(where: { $0.id == entry.carID }) else { continue }
            let db = database(for: car)
            let record = (try? await db.record(for: entry.id)) ?? CKRecord(recordType: "FuelEntry", recordID: entry.id)
            record["date"] = entry.date as CKRecordValue
            record["car"] = CKRecord.Reference(recordID: car.id, action: .none)
            record["kilometers"] = entry.kilometers as CKRecordValue
            record["liters"] = NSDecimalNumber(decimal: entry.liters).stringValue as CKRecordValue
            record["pricePerLiter"] = NSDecimalNumber(decimal: entry.pricePerLiter).stringValue as CKRecordValue
            record["stationName"] = entry.stationName as CKRecordValue
            if let latitude = entry.latitude { record["latitude"] = latitude as CKRecordValue }
            if let longitude = entry.longitude { record["longitude"] = longitude as CKRecordValue }
            _ = try await db.save(record)
            snapshot.pendingFuelEntries?.remove(key)
            persist()
        }
        for key in (snapshot.pendingExpensePlaces ?? []).sorted(by: { $0.name < $1.name }) {
            guard let place = expensePlaces.first(where: { $0.id == key.id }) else { continue }
            let database = familyZoneSharedWithMe ? sharedDB : privateDB
            let record = (try? await database.record(for: place.id)) ?? CKRecord(recordType: "ExpensePlace", recordID: place.id)
            record["expenseID"] = place.expenseID as CKRecordValue
            record["category"] = place.category as CKRecordValue
            record["detail"] = place.detail as CKRecordValue
            record["latitude"] = place.latitude as CKRecordValue
            record["longitude"] = place.longitude as CKRecordValue
            record["recordedAt"] = place.recordedAt as CKRecordValue
            _ = try await database.save(record)
            snapshot.pendingExpensePlaces?.remove(key)
            persist()
        }
        for key in (snapshot.pendingFamilyMembers ?? []).sorted(by: { $0.name < $1.name }) {
            guard let member = familyMembers.first(where: { $0.id == key.id }) else { continue }
            let database = familyZoneSharedWithMe ? sharedDB : privateDB
            let record = (try? await database.record(for: member.id)) ?? CKRecord(recordType: "FamilyMember", recordID: member.id)
            record["userRecordName"] = member.userRecordName as CKRecordValue
            record["payerName"] = member.payerName as CKRecordValue
            record["updatedAt"] = member.updatedAt as CKRecordValue
            _ = try await database.save(record)
            snapshot.pendingFamilyMembers?.remove(key)
            persist()
        }
    }

    private func refreshFamilyParticipants() async {
        guard let myID = try? await container.userRecordID() else { return }
        myUserRecordName = myID.recordName
        activeMemberIDs = [myID.recordName]
        guard let familyZoneID else { return }
        let shareID = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: familyZoneID)
        let database = familyZoneSharedWithMe ? sharedDB : privateDB
        guard let share = try? await database.record(for: shareID) as? CKShare else { return }
        activeMemberIDs.formUnion(share.participants.filter { $0.role == .owner || $0.acceptanceStatus == .accepted }
            .compactMap { $0.userIdentity.userRecordID?.recordName })
    }

    func setMyPayerName(_ name: String) async {
        guard FamilyBudget.payers.contains(name), name != "Común" else { return }
        localPayerName = name
        UserDefaults.standard.set(name, forKey: "garage.myPayerName")
        guard let familyZoneID, let myUserRecordName else { return }
        let recordName = "member-" + SHA256.hash(data: Data(myUserRecordName.utf8)).map { String(format: "%02x", $0) }.joined()
        let id = CKRecord.ID(recordName: recordName, zoneID: familyZoneID)
        let member = FamilyMember(id: id, userRecordName: myUserRecordName, payerName: name, updatedAt: .now)
        familyMembers.removeAll { $0.id == id }
        familyMembers.append(member)
        snapshot.pendingFamilyMembers = (snapshot.pendingFamilyMembers ?? []).union([RecordKey(id)])
        await saveLocallyAndSync()
    }

    private func saveLocallyAndSync() async {
        persist()
        await NotificationPlanner.schedule(cars: cars, plans: plans)
        await reload()
    }

    func addCar(name: String, plate: String, odometer: Int) async -> Car {
        let zoneID = familyZoneID ?? CKRecordZone.ID(zoneName: familyZoneName, ownerName: CKCurrentUserDefaultName)
        let id = CKRecord.ID(recordName: UUID().uuidString, zoneID: zoneID)
        let car = Car(id: id, name: name, plate: plate.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(), odometer: odometer, updatedAt: .now, isSharedWithMe: familyZoneSharedWithMe)
        cars.append(car)
        snapshot.pendingCars.insert(RecordKey(id))
        await saveLocallyAndSync()
        return car
    }

    func deleteCar(_ car: Car) async {
        guard cars.contains(where: { $0.id == car.id }) else { return }
        let planIDs = Set(plans.filter { $0.carID == car.id }.map(\.id))
        let entryIDs = entries.filter { planIDs.contains($0.planID) }.map(\.id)
        let fuelIDs = fuelEntries.filter { $0.carID == car.id }.map(\.id)
        cars.removeAll { $0.id == car.id }
        plans.removeAll { planIDs.contains($0.id) }
        entries.removeAll { entryIDs.contains($0.id) }
        fuelEntries.removeAll { fuelIDs.contains($0.id) }
        snapshot.pendingCars.remove(RecordKey(car.id))
        snapshot.pendingPlans.subtract(planIDs.map(RecordKey.init))
        snapshot.pendingEntries.subtract(entryIDs.map(RecordKey.init))
        snapshot.pendingFuelEntries?.subtract(fuelIDs.map(RecordKey.init))
        snapshot.pendingFuelDeletions = (snapshot.pendingFuelDeletions ?? []).filter { !fuelIDs.contains($0.entry.id) }
        snapshot.pendingDeletions = (snapshot.pendingDeletions ?? []).union([
            LocalSnapshot.PendingDeletion(car: RecordKey(car.id), sharedWithMe: car.isSharedWithMe)
        ])
        await saveLocallyAndSync()
    }

    func updateOdometer(_ car: Car, kilometers: Int) async {
        guard let index = cars.firstIndex(where: { $0.id == car.id }) else { return }
        cars[index].odometer = kilometers
        cars[index].updatedAt = .now
        snapshot.pendingCars.insert(RecordKey(car.id))
        await saveLocallyAndSync()
    }

    func saveCarDetail(_ detail: CarDetail, for car: Car) async {
        guard let index = cars.firstIndex(where: { $0.id == car.id }) else { return }
        if let detailIndex = cars[index].details.firstIndex(where: { $0.id == detail.id }) {
            cars[index].details[detailIndex] = detail
        } else {
            cars[index].details.append(detail)
        }
        cars[index].updatedAt = .now
        snapshot.pendingCars.insert(RecordKey(car.id))
        await saveLocallyAndSync()
    }

    func deleteCarDetail(_ detail: CarDetail, from car: Car) async {
        guard let index = cars.firstIndex(where: { $0.id == car.id }) else { return }
        cars[index].details.removeAll { $0.id == detail.id }
        cars[index].updatedAt = .now
        snapshot.pendingCars.insert(RecordKey(car.id))
        await saveLocallyAndSync()
    }

    func addFuelEntry(car: Car, date: Date, kilometers: Int, liters: Decimal, pricePerLiter: Decimal,
                      stationName: String, latitude: Double?, longitude: Double?) async -> String? {
        guard cars.contains(where: { $0.id == car.id }) else { return nil }
        let id = CKRecord.ID(recordName: UUID().uuidString, zoneID: car.id.zoneID)
        fuelEntries.insert(FuelEntry(id: id, carID: car.id, date: date, kilometers: kilometers, liters: liters,
                                     pricePerLiter: pricePerLiter, stationName: stationName,
                                     latitude: latitude, longitude: longitude), at: 0)
        snapshot.pendingFuelEntries = (snapshot.pendingFuelEntries ?? []).union([RecordKey(id)])
        if kilometers > car.odometer, let index = cars.firstIndex(where: { $0.id == car.id }) {
            cars[index].odometer = kilometers
            cars[index].updatedAt = .now
            snapshot.pendingCars.insert(RecordKey(car.id))
        }
        await saveLocallyAndSync()
        return id.recordName
    }

    func addExpensePlace(expense: FamilyExpense, latitude: Double, longitude: Double) async {
        guard let zoneID = familyZoneID else { return }
        let id = CKRecord.ID(recordName: "expense-\(expense.id)", zoneID: zoneID)
        guard !expensePlaces.contains(where: { $0.id == id }) else { return }
        expensePlaces.append(ExpensePlace(id: id, expenseID: expense.id, category: expense.category,
                                          detail: expense.detail, latitude: latitude, longitude: longitude,
                                          recordedAt: expense.date))
        snapshot.pendingExpensePlaces = (snapshot.pendingExpensePlaces ?? []).union([RecordKey(id)])
        await saveLocallyAndSync()
    }

    func updateExpensePlace(for expense: FamilyExpense) async {
        guard let index = expensePlaces.firstIndex(where: { $0.expenseID == expense.id }) else { return }
        let old = expensePlaces[index]
        expensePlaces[index] = ExpensePlace(id: old.id, expenseID: old.expenseID,
                                            category: expense.category, detail: expense.detail,
                                            latitude: old.latitude, longitude: old.longitude,
                                            recordedAt: expense.date)
        snapshot.pendingExpensePlaces = (snapshot.pendingExpensePlaces ?? []).union([RecordKey(old.id)])
        ExpenseVisitMonitor.shared.updatePlaces(expensePlaces)
        await saveLocallyAndSync()
    }

    func deleteExpensePlace(for expense: FamilyExpense) async {
        guard let zoneID = familyZoneID, !expense.id.hasPrefix("sheet-row-") else { return }
        let id = CKRecord.ID(recordName: "expense-\(expense.id)", zoneID: zoneID)
        expensePlaces.removeAll { $0.id == id }
        snapshot.pendingExpensePlaces?.remove(RecordKey(id))
        snapshot.pendingExpensePlaceDeletions = (snapshot.pendingExpensePlaceDeletions ?? []).union([
            LocalSnapshot.PendingExpensePlaceDeletion(place: RecordKey(id), sharedWithMe: familyZoneSharedWithMe)
        ])
        ExpenseVisitMonitor.shared.updatePlaces(expensePlaces)
        await saveLocallyAndSync()
    }

    func deleteFuelEntry(_ entry: FuelEntry) async {
        guard fuelEntries.contains(where: { $0.id == entry.id }),
              let car = cars.first(where: { $0.id == entry.carID }) else { return }
        fuelEntries.removeAll { $0.id == entry.id }
        snapshot.pendingFuelEntries?.remove(RecordKey(entry.id))
        snapshot.pendingFuelDeletions = (snapshot.pendingFuelDeletions ?? []).union([
            LocalSnapshot.PendingFuelDeletion(entry: RecordKey(entry.id), sharedWithMe: car.isSharedWithMe)
        ])
        await saveLocallyAndSync()
    }

    func addPlan(car: Car, title: String, details: String, months: Int, kilometers: Int, lastDate: Date, lastKilometers: Int, noticeDays: Int, noticeKilometers: Int) async {
        let id = CKRecord.ID(recordName: UUID().uuidString, zoneID: car.id.zoneID)
        plans.append(ServicePlan(id: id, carID: car.id, title: title, details: details, intervalMonths: months, intervalKilometers: kilometers, lastDate: lastDate, lastKilometers: lastKilometers, noticeDays: noticeDays, noticeKilometers: noticeKilometers))
        snapshot.pendingPlans.insert(RecordKey(id))
        await saveLocallyAndSync()
    }

    func addMaintenanceSelections(_ selections: [MaintenanceSelection], sourceURL: URL, to car: Car) async {
        guard cars.contains(where: { $0.id == car.id }) else { return }
        var existing = Set(plans.filter { $0.carID == car.id }.compactMap(\.templateRuleID))
        var added = false
        for selection in selections where existing.insert(selection.rule.id).inserted {
            let id = CKRecord.ID(recordName: UUID().uuidString, zoneID: car.id.zoneID)
            let rule = selection.rule
            plans.append(ServicePlan(id: id, carID: car.id, title: rule.title, details: rule.details,
                                     intervalMonths: rule.intervalMonths, intervalKilometers: rule.intervalKilometers,
                                     lastDate: selection.lastDate, lastKilometers: selection.lastKilometers,
                                     noticeDays: 14, noticeKilometers: 500,
                                     sourceURL: (rule.sourceURL ?? sourceURL).absoluteString, templateRuleID: rule.id,
                                     baselineUnknown: selection.baselineUnknown))
            snapshot.pendingPlans.insert(RecordKey(id))
            added = true
        }
        if added { await saveLocallyAndSync() }
    }

    func complete(_ plan: ServicePlan, car: Car, date: Date, kilometers: Int, notes: String) async -> String {
        let id = CKRecord.ID(recordName: UUID().uuidString, zoneID: car.id.zoneID)
        entries.append(ServiceEntry(id: id, planID: plan.id, date: date, kilometers: kilometers, notes: notes))
        snapshot.pendingEntries.insert(RecordKey(id))
        if let index = plans.firstIndex(where: { $0.id == plan.id }) {
            plans[index].lastDate = date
            plans[index].lastKilometers = kilometers
            plans[index].baselineUnknown = false
            snapshot.pendingPlans.insert(RecordKey(plan.id))
        }
        if kilometers > car.odometer, let index = cars.firstIndex(where: { $0.id == car.id }) {
            cars[index].odometer = kilometers
            cars[index].updatedAt = .now
            snapshot.pendingCars.insert(RecordKey(car.id))
        }
        await saveLocallyAndSync()
        return id.recordName
    }
}

enum NidoError: LocalizedError {
    case iCloudUnavailable
    var errorDescription: String? { "Iniciá sesión en iCloud para sincronizar y compartir tus autos." }
}
