import CloudKit
import SwiftUI
import UIKit

final class ShareSceneDelegate: UIResponder, UIWindowSceneDelegate {
    func windowScene(_ windowScene: UIWindowScene, userDidAcceptCloudKitShareWith metadata: CKShare.Metadata) {
        accept(metadata)
    }

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        if let metadata = connectionOptions.cloudKitShareMetadata { accept(metadata) }
    }

    private func accept(_ metadata: CKShare.Metadata) {
        CKContainer.default().accept(metadata) { _, _ in }
    }
}

final class ShareAcceptanceDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        FuelVisitMonitor.shared.startIfEnabled()
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
    @StateObject private var fuelMonitor = FuelVisitMonitor.shared
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            CarsView()
                .environmentObject(store)
                .environmentObject(fuelMonitor)
                .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await store.reload() } } }
                .task {
                    await store.reload()
                    await NotificationPlanner.requestPermission()
                    await NotificationPlanner.schedule(cars: store.cars, plans: store.plans)
                }
        }
    }
}
