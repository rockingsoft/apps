import CloudKit
import SwiftUI
import UIKit

struct CarSharingSheet: View {
    @Environment(\.dismiss) private var dismiss
    let car: Car
    let store: CloudStore
    @State private var existingShare: CKShare?
    @State private var loading = true
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if loading {
                ProgressView("Preparando invitación…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage {
                ContentUnavailableView {
                    Label("No se pudo compartir", systemImage: "icloud.slash")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("Reintentar") { Task { await loadShare() } }
                }
            } else {
                SharingController(car: car, store: store, existingShare: existingShare,
                                  onClose: { dismiss() },
                                  onError: { errorMessage = $0.localizedDescription })
            }
        }
        .task { await loadShare() }
    }

    private func loadShare() async {
        loading = true
        errorMessage = nil
        let shareID = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: car.id.zoneID)
        do {
            let record = try await store.container.privateCloudDatabase.record(for: shareID)
            guard let share = record as? CKShare else { throw ShareError.invalidShare }
            existingShare = share
        } catch let error as CKError where error.code == .unknownItem {
            existingShare = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        loading = false
    }
}

private enum ShareError: LocalizedError {
    case invalidShare
    var errorDescription: String? { "iCloud devolvió una invitación inválida. Intentá de nuevo." }
}

private struct SharingController: UIViewControllerRepresentable {
    let car: Car
    let store: CloudStore
    let existingShare: CKShare?
    let onClose: () -> Void
    let onError: (Error) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(carName: car.name, onClose: onClose, onError: onError) }

    func makeUIViewController(context: Context) -> SharingHostController {
        let controller: UICloudSharingController
        if let existingShare {
            controller = UICloudSharingController(share: existingShare, container: store.container)
        } else {
            controller = UICloudSharingController { _, completion in
                Task {
                    do {
                        let share = CKShare(recordZoneID: car.id.zoneID)
                        share[CKShare.SystemFieldKey.title] = car.name as CKRecordValue
                        let saved = try await store.container.privateCloudDatabase.save(share)
                        guard let savedShare = saved as? CKShare else { throw ShareError.invalidShare }
                        completion(savedShare, store.container, nil)
                    } catch {
                        completion(nil, nil, error)
                    }
                }
            }
        }
        controller.delegate = context.coordinator
        controller.availablePermissions = [.allowReadOnly, .allowReadWrite, .allowPrivate]
        let host = SharingHostController()
        host.onAppear = { [weak host] in
            guard let host, host.presentedViewController == nil else { return }
            if let popover = controller.popoverPresentationController {
                popover.sourceView = host.view
                popover.sourceRect = host.view.bounds
            }
            host.present(controller, animated: true) {
                controller.presentationController?.delegate = context.coordinator
            }
        }
        return host
    }

    func updateUIViewController(_ controller: SharingHostController, context: Context) {}

    final class Coordinator: NSObject, UICloudSharingControllerDelegate, UIAdaptivePresentationControllerDelegate {
        let carName: String
        let onClose: () -> Void
        let onError: (Error) -> Void
        init(carName: String, onClose: @escaping () -> Void, onError: @escaping (Error) -> Void) {
            self.carName = carName
            self.onClose = onClose
            self.onError = onError
        }
        func itemTitle(for controller: UICloudSharingController) -> String? { carName }
        func presentationControllerDidDismiss(_ presentationController: UIPresentationController) { onClose() }
        func cloudSharingController(_ controller: UICloudSharingController, failedToSaveShareWithError error: Error) {
            onError(error)
        }
    }
}

private final class SharingHostController: UIViewController {
    var onAppear: (() -> Void)?
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        onAppear?()
    }
}
