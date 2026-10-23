import CoreLocation
import MapKit
import UIKit
import UserNotifications

struct FuelStationMatch {
    let name: String
    let coordinate: CLLocationCoordinate2D
    let distance: CLLocationDistance
}

struct FuelVisitSuggestion: Codable, Identifiable {
    let id: UUID
    let stationName: String
    let latitude: Double
    let longitude: Double
    let arrivedAt: Date

    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
}

enum FuelStationFinder {
    static func nearest(to location: CLLocation, within maximumDistance: CLLocationDistance = 150) async throws -> FuelStationMatch? {
        let request = MKLocalPointsOfInterestRequest(center: location.coordinate, radius: 350)
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: [.gasStation])
        let response = try await MKLocalSearch(request: request).start()
        return response.mapItems.compactMap { item -> FuelStationMatch? in
            guard let coordinate = item.placemark.location?.coordinate, let name = item.name else { return nil }
            let distance = location.distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
            guard distance <= maximumDistance else { return nil }
            return FuelStationMatch(name: brand(from: name), coordinate: coordinate, distance: distance)
        }.min(by: { $0.distance < $1.distance })
    }

    private static func brand(from name: String) -> String {
        let known = ["YPF", "Shell", "Axion", "Puma", "Gulf", "Petrobras"]
        return known.first(where: { name.localizedCaseInsensitiveContains($0) }) ?? name
    }
}

@MainActor final class FuelVisitMonitor: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
    static let shared = FuelVisitMonitor()
    private static let enabledKey = "garage.fuelVisitEnabled"
    private static let suggestionKey = "garage.fuelVisitSuggestion"
    private static let lastPromptKey = "garage.fuelVisitLastPrompt"

    @Published private(set) var enabled: Bool
    @Published private(set) var authorization: CLAuthorizationStatus
    @Published private(set) var suggestion: FuelVisitSuggestion?
    private let manager = CLLocationManager()

    private override init() {
        enabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        authorization = manager.authorizationStatus
        let saved = UserDefaults.standard.data(forKey: Self.suggestionKey).flatMap { try? JSONDecoder().decode(FuelVisitSuggestion.self, from: $0) }
        suggestion = saved.flatMap { Date().timeIntervalSince($0.arrivedAt) < 48 * 60 * 60 ? $0 : nil }
        super.init()
        manager.delegate = self
    }

    func startIfEnabled() {
        guard enabled, authorization == .authorizedAlways else { return }
        manager.startMonitoringVisits()
    }

    func setEnabled(_ value: Bool) {
        enabled = value
        UserDefaults.standard.set(value, forKey: Self.enabledKey)
        if value {
            if authorization == .authorizedAlways { manager.startMonitoringVisits() }
            else { manager.requestAlwaysAuthorization() }
        } else {
            manager.stopMonitoringVisits()
            clearSuggestion()
        }
    }

    func clearSuggestion() {
        suggestion = nil
        UserDefaults.standard.removeObject(forKey: Self.suggestionKey)
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorization = manager.authorizationStatus
        if enabled, authorization == .authorizedAlways { manager.startMonitoringVisits() }
        else { manager.stopMonitoringVisits() }
    }

    func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
        guard enabled, authorization == .authorizedAlways,
              visit.arrivalDate != .distantPast else { return }
        let end = visit.departureDate == .distantFuture ? Date() : visit.departureDate
        guard end.timeIntervalSince(visit.arrivalDate) >= 5 * 60 else { return }
        let location = CLLocation(latitude: visit.coordinate.latitude, longitude: visit.coordinate.longitude)
        Task { await offerFuelLog(near: location, arrivedAt: visit.arrivalDate, accuracy: visit.horizontalAccuracy) }
    }

    private func offerFuelLog(near location: CLLocation, arrivedAt: Date, accuracy: CLLocationAccuracy) async {
        guard accuracy > 0, accuracy <= 200 else { return }
        let lastPrompt = UserDefaults.standard.object(forKey: Self.lastPromptKey) as? Date ?? .distantPast
        guard Date().timeIntervalSince(lastPrompt) > 6 * 60 * 60 else { return }
        let backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Buscar estación de servicio")
        defer { if backgroundTask != .invalid { UIApplication.shared.endBackgroundTask(backgroundTask) } }
        guard let station = try? await FuelStationFinder.nearest(to: location, within: max(90, min(150, accuracy))) else { return }
        let found = FuelVisitSuggestion(id: UUID(), stationName: station.name,
                                        latitude: station.coordinate.latitude, longitude: station.coordinate.longitude,
                                        arrivedAt: arrivedAt)
        suggestion = found
        UserDefaults.standard.set(try? JSONEncoder().encode(found), forKey: Self.suggestionKey)
        UserDefaults.standard.set(Date(), forKey: Self.lastPromptKey)
        let content = UNMutableNotificationContent()
        content.title = "¿Cargaste nafta en \(station.name)?"
        content.body = "Abrí Garage para registrar kilómetros, litros y precio."
        content.sound = .default
        let request = UNNotificationRequest(identifier: "garage.fuel.\(found.id)", content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }
}

@MainActor final class CurrentFuelStation: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
    @Published private(set) var loading = false
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation, Error>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func search() async throws -> FuelStationMatch? {
        loading = true
        defer { loading = false }
        let location = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<CLLocation, Error>) in
            self.continuation = continuation
            if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }
            else if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted {
                self.continuation = nil
                continuation.resume(throwing: CLError(.denied))
            } else { manager.requestLocation() }
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 20_000_000_000)
                guard let self, let pending = self.continuation else { return }
                self.continuation = nil
                pending.resume(throwing: CLError(.locationUnknown))
            }
        }
        return try await FuelStationFinder.nearest(to: location)
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
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
