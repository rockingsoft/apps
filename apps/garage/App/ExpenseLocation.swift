import CloudKit
import CoreLocation
import Foundation
import UIKit
import UserNotifications

struct ExpensePlace: Identifiable, Hashable {
    let id: CKRecord.ID
    let expenseID: String
    let category: String
    let detail: String
    let latitude: Double
    let longitude: Double
    let recordedAt: Date
}

@MainActor final class CurrentExpenseLocation: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation, Error>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func capture() async throws -> CLLocation {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            switch manager.authorizationStatus {
            case .notDetermined: manager.requestWhenInUseAuthorization()
            case .authorizedAlways, .authorizedWhenInUse: manager.requestLocation()
            default:
                self.continuation = nil
                continuation.resume(throwing: CLError(.denied))
            }
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(20))
                guard let self, let pending = self.continuation else { return }
                self.continuation = nil
                pending.resume(throwing: CLError(.locationUnknown))
            }
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedAlways || manager.authorizationStatus == .authorizedWhenInUse {
            if continuation != nil { manager.requestLocation() }
        } else if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted {
            continuation?.resume(throwing: CLError(.denied))
            continuation = nil
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        continuation?.resume(returning: location)
        continuation = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
}

struct ExpenseVisitSuggestion: Codable, Identifiable {
    let id: UUID
    let category: String
    let detail: String
    let latitude: Double
    let longitude: Double
    let arrivedAt: Date
}

@MainActor final class ExpenseVisitMonitor: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
    static let shared = ExpenseVisitMonitor()
    @Published private(set) var enabled: Bool
    @Published private(set) var suggestion: ExpenseVisitSuggestion?
    @Published private(set) var authorization: CLAuthorizationStatus
    private let manager = CLLocationManager()
    private var places: [ExpensePlace] = []
    private let enabledKey = "garage.expenseVisitsEnabled"
    private let suggestionKey = "garage.expenseVisitSuggestion"
    private let lastPromptKey = "garage.expenseVisitLastPrompt"

    private override init() {
        enabled = UserDefaults.standard.bool(forKey: "garage.expenseVisitsEnabled")
        authorization = manager.authorizationStatus
        suggestion = UserDefaults.standard.data(forKey: "garage.expenseVisitSuggestion")
            .flatMap { try? JSONDecoder().decode(ExpenseVisitSuggestion.self, from: $0) }
        super.init()
        manager.delegate = self
        places = (LocalSnapshot.load().expensePlaces ?? []).map(\.place)
    }

    func updatePlaces(_ places: [ExpensePlace]) { self.places = places }

    func startIfEnabled() {
        guard enabled, authorization == .authorizedAlways else { return }
        manager.startMonitoringVisits()
    }

    func setEnabled(_ enabled: Bool) {
        self.enabled = enabled
        UserDefaults.standard.set(enabled, forKey: enabledKey)
        if enabled {
            if authorization == .authorizedAlways { manager.startMonitoringVisits() }
            else { manager.requestAlwaysAuthorization() }
        } else {
            manager.stopMonitoringVisits()
            clearSuggestion()
        }
    }

    func clearSuggestion() {
        suggestion = nil
        UserDefaults.standard.removeObject(forKey: suggestionKey)
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorization = manager.authorizationStatus
        if enabled && authorization == .authorizedAlways { manager.startMonitoringVisits() }
        else { manager.stopMonitoringVisits() }
    }

    func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
        guard enabled, authorization == .authorizedAlways, visit.arrivalDate != .distantPast,
              visit.horizontalAccuracy > 0, visit.horizontalAccuracy <= 200 else { return }
        let notificationID = "garage.expense.\(Int(visit.arrivalDate.timeIntervalSince1970)).\(Int(visit.coordinate.latitude * 1000)).\(Int(visit.coordinate.longitude * 1000))"
        if visit.departureDate != .distantFuture && visit.departureDate.timeIntervalSince(visit.arrivalDate) < 5 * 60 {
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [notificationID])
            if suggestion?.arrivedAt == visit.arrivalDate { clearSuggestion() }
            UserDefaults.standard.removeObject(forKey: lastPromptKey)
            return
        }
        let position = CLLocation(latitude: visit.coordinate.latitude, longitude: visit.coordinate.longitude)
        guard let nearest = places.map({ place in
            (place, position.distance(from: CLLocation(latitude: place.latitude, longitude: place.longitude)))
        }).filter({ $0.0.category != "Auto" && $0.1 <= max(100, visit.horizontalAccuracy) }).min(by: { $0.1 < $1.1 })?.0 else { return }
        let previous = UserDefaults.standard.object(forKey: lastPromptKey) as? Date ?? .distantPast
        guard Date().timeIntervalSince(previous) > 6 * 60 * 60 else { return }
        let found = ExpenseVisitSuggestion(id: UUID(), category: nearest.category, detail: nearest.detail,
                                           latitude: nearest.latitude, longitude: nearest.longitude,
                                           arrivedAt: visit.arrivalDate)
        suggestion = found
        UserDefaults.standard.set(try? JSONEncoder().encode(found), forKey: suggestionKey)
        UserDefaults.standard.set(Date(), forKey: lastPromptKey)
        let content = UNMutableNotificationContent()
        content.title = "¿Registramos un gasto acá?"
        content.body = "Garage reconoce este lugar por un gasto anterior. Revisá los datos antes de guardar."
        let delay = max(1, visit.arrivalDate.addingTimeInterval(5 * 60).timeIntervalSinceNow)
        let notification = UNNotificationRequest(identifier: notificationID, content: content,
                                                 trigger: UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false))
        UNUserNotificationCenter.current().add(notification)
    }
}
