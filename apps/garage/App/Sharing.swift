import CloudKit
import SwiftUI
import UIKit

struct CarSharingSheet: View {
    let car: Car
    let store: CloudStore
    let onClose: () -> Void
    @State private var existingShare: CKShare?
    @State private var loading = true
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            Color.black.opacity(0.16).ignoresSafeArea()
            if loading {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("Preparando colaboración…").font(.subheadline)
                }
                .padding(24)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
            } else if let errorMessage {
                VStack(spacing: 12) {
                    Label("No se pudo invitar", systemImage: "icloud.slash").font(.headline)
                    Text(errorMessage).font(.subheadline).multilineTextAlignment(.center)
                    HStack {
                        Button("Cancelar", action: onClose)
                        Button("Reintentar") { Task { await loadShare() } }
                            .buttonStyle(.borderedProminent)
                    }
                }
                .padding(24)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
                .padding(24)
            } else {
                SharingController(car: car, store: store, existingShare: existingShare,
                                  onClose: onClose,
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
        controller.availablePermissions = [.allowPrivate, .allowReadWrite]
        let host = SharingHostController()
        host.view.backgroundColor = .clear
        host.onAppear = { [weak host] in
            guard let host, !host.didPresent else { return }
            host.didPresent = true
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
    var didPresent = false
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        onAppear?()
    }
}

struct CarAccessView: View {
    let car: Car
    let store: CloudStore
    @State private var share: CKShare?
    @State private var loading = false
    @State private var errorMessage: String?
    @State private var inviting = false
    @State private var participantToRemove: CKShare.Participant?
    @State private var removing = false

    private var database: CKDatabase {
        car.isSharedWithMe ? store.container.sharedCloudDatabase : store.container.privateCloudDatabase
    }

    private var guests: [CKShare.Participant] {
        share?.participants.filter { $0.role != .owner && $0.acceptanceStatus != .removed } ?? []
    }

    var body: some View {
        List {
            Section {
                LabeledContent("Auto", value: car.name)
                LabeledContent("Tu acceso", value: car.isSharedWithMe ? "Colaborador" : "Propietario")
            }

            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "icloud.slash")
                        .foregroundStyle(.orange)
                    Button("Reintentar") { Task { await loadShare() } }
                }
            } else if loading && share == nil {
                Section { ProgressView("Consultando iCloud…") }
            } else if share == nil {
                Section("Personas") {
                    Text(car.isSharedWithMe ? "No se pudo cargar la invitación." : "Solo vos tenés acceso a este auto.")
                        .foregroundStyle(.secondary)
                }
            } else {
                Section("Personas") {
                    if guests.isEmpty {
                        Text("Todavía no hay colaboradores.").foregroundStyle(.secondary)
                    }
                    ForEach(Array(guests.enumerated()), id: \.offset) { index, participant in
                        HStack(spacing: 12) {
                            Image(systemName: "person.crop.circle")
                                .font(.title2).foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(displayName(for: participant, index: index))
                                Text("\(status(for: participant)) · \(participant.permission == .readWrite ? "Puede editar" : "Solo lectura")")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if !car.isSharedWithMe {
                                Button("Quitar", systemImage: "person.crop.circle.badge.minus", role: .destructive) {
                                    participantToRemove = participant
                                }
                                .labelStyle(.iconOnly)
                                .disabled(removing)
                            }
                        }
                    }
                }
            }

            if !car.isSharedWithMe {
                Section {
                    Button("Invitar a colaborar", systemImage: "person.crop.circle.badge.plus") {
                        inviting = true
                    }
                    .disabled(!store.canShare(car) || loading || removing)
                    Text("Las personas invitadas pueden editar este auto, sus cargas y servicios. La invitación se envía desde Mensajes u otra app que elijas.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Acceso")
        .refreshable { await loadShare() }
        .task { await loadShare() }
        .overlay {
            if inviting {
                CarSharingSheet(car: car, store: store, onClose: {
                    inviting = false
                    Task { await loadShare() }
                })
            }
        }
        .alert("¿Quitar acceso?", isPresented: Binding(
            get: { participantToRemove != nil },
            set: { if !$0 { participantToRemove = nil } }
        )) {
            Button("Quitar", role: .destructive) {
                guard let participant = participantToRemove else { return }
                participantToRemove = nil
                Task { await remove(participant) }
            }
            Button("Cancelar", role: .cancel) { participantToRemove = nil }
        } message: {
            Text("Esa persona dejará de ver y editar este auto.")
        }
    }

    private func loadShare() async {
        loading = true
        defer { loading = false }
        errorMessage = nil
        let shareID = CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: car.id.zoneID)
        do {
            let record = try await database.record(for: shareID)
            guard let fetched = record as? CKShare else { throw ShareError.invalidShare }
            share = fetched
        } catch let error as CKError where error.code == .unknownItem && !car.isSharedWithMe {
            share = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func remove(_ participant: CKShare.Participant) async {
        guard !car.isSharedWithMe else { return }
        removing = true
        defer { removing = false }
        do {
            let record = try await database.record(for: CKRecord.ID(recordName: CKRecordNameZoneWideShare, zoneID: car.id.zoneID))
            guard let current = record as? CKShare,
                  let target = current.participants.first(where: { $0.participantID == participant.participantID }) else {
                throw ShareError.invalidShare
            }
            current.removeParticipant(target)
            _ = try await database.save(current)
            await loadShare()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func displayName(for participant: CKShare.Participant, index: Int) -> String {
        if let components = participant.userIdentity.nameComponents {
            let name = PersonNameComponentsFormatter.localizedString(from: components, style: .default)
            if !name.isEmpty { return name }
        }
        if let email = participant.userIdentity.lookupInfo?.emailAddress { return email }
        if let phone = participant.userIdentity.lookupInfo?.phoneNumber { return phone }
        return "Persona \(index + 1)"
    }

    private func status(for participant: CKShare.Participant) -> String {
        switch participant.acceptanceStatus {
        case .pending: "Invitación pendiente"
        case .accepted: "Aceptó la invitación"
        case .removed: "Sin acceso"
        default: "Estado no disponible"
        }
    }
}
