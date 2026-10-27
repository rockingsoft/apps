import CloudKit
import AppIntents
import SwiftUI
import UIKit

extension Notification.Name {
    static let garageShareAccepted = Notification.Name("garage.shareAccepted")
    static let garageShareAcceptanceFailed = Notification.Name("garage.shareAcceptanceFailed")
}

final class ShareSceneDelegate: UIResponder, UIWindowSceneDelegate {
    func windowScene(_ windowScene: UIWindowScene, userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
        accept(metadata)
    }

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        if let metadata = connectionOptions.cloudKitShareMetadata { accept(metadata) }
    }

    private func accept(_ metadata: CKShare.Metadata) {
        CKContainer.default().accept(metadata) { _, error in
            DispatchQueue.main.async {
                if let error {
                    NotificationCenter.default.post(name: .garageShareAcceptanceFailed, object: error.localizedDescription)
                } else {
                    UserDefaults.standard.set(true, forKey: "garage.shareAcceptedNeedsReload")
                    NotificationCenter.default.post(name: .garageShareAccepted, object: nil)
                }
            }
        }
    }
}

final class ShareAcceptanceDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        FuelVisitMonitor.shared.startIfEnabled()
        ExpenseVisitMonitor.shared.startIfEnabled()
        return true
    }

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = ShareSceneDelegate.self
        return configuration
    }
}

@main struct GarageApp: App {
    @UIApplicationDelegateAdaptor(ShareAcceptanceDelegate.self) private var shareDelegate
    @StateObject private var store = CloudStore()
    @StateObject private var finances = FinanceStore()
    @StateObject private var chatGPT = ChatGPTExpense()
    @StateObject private var fuelMonitor = FuelVisitMonitor.shared
    @StateObject private var expenseMonitor = ExpenseVisitMonitor.shared
    @Environment(\.scenePhase) private var scenePhase
    init() {
        GarageShortcuts.updateAppShortcutParameters()
    }
    var body: some Scene {
        WindowGroup {
            CarsView()
                .environmentObject(store)
                .environmentObject(finances)
                .environmentObject(chatGPT)
                .environmentObject(fuelMonitor)
                .environmentObject(expenseMonitor)
                .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await store.reload() } } }
                .onReceive(NotificationCenter.default.publisher(for: .garageShareAccepted)) { _ in
                    Task {
                        await store.reload()
                        UserDefaults.standard.removeObject(forKey: "garage.shareAcceptedNeedsReload")
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .garageShareAcceptanceFailed)) { notification in
                    store.shareError = notification.object as? String ?? "No se pudo aceptar la invitación."
                }
                .task {
                    await finances.restore()
                    await store.reload()
                    if UserDefaults.standard.bool(forKey: "garage.shareAcceptedNeedsReload") {
                        await store.reload()
                        UserDefaults.standard.removeObject(forKey: "garage.shareAcceptedNeedsReload")
                    }
                    await NotificationPlanner.requestPermission()
                    await NotificationPlanner.schedule(cars: store.cars, plans: store.plans)
                }
        }
    }
}
