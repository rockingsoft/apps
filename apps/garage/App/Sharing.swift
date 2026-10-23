import CloudKit
import SwiftUI
import UIKit

struct CarSharingSheet: UIViewControllerRepresentable {
    let car: Car
    let store: CloudStore

    func makeCoordinator() -> Coordinator { Coordinator(carName: car.name) }

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController { _, completion in
            Task {
                do {
                    let zoneID = car.id.zoneID
                    let shareID = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: zoneID)
                    let share: CKShare
                    if let existing = try? await store.container.privateCloudDatabase.record(for: shareID) as? CKShare {
                        share = existing
                    } else {
                        share = CKShare(recordZoneID: zoneID)
                        share[CKShare.SystemFieldKey.title] = car.name as CKRecordValue
                        let (results, _) = try await store.container.privateCloudDatabase.modifyRecords(saving: [share], deleting: [])
                        _ = try results[share.recordID]?.get()
                    }
                    completion(share, store.container, nil)
                } catch { completion(nil, nil, error) }
            }
        }
        controller.delegate = context.coordinator
        controller.availablePermissions = [.allowReadOnly, .allowReadWrite, .allowPrivate]
        return controller
    }

    func updateUIViewController(_ controller: UICloudSharingController, context: Context) {}

    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        let carName: String
        init(carName: String) { self.carName = carName }
        func itemTitle(for controller: UICloudSharingController) -> String? { carName }
        func cloudSharingController(_ controller: UICloudSharingController, failedToSaveShareWithError error: Error) {}
    }
}
