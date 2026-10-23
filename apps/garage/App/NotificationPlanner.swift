import Foundation
import UserNotifications

@MainActor enum NotificationPlanner {
    static func requestPermission() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
    }

    static func schedule(cars: [Car], plans: [ServicePlan]) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix("garage.") })
        let authorized = await center.notificationSettings().authorizationStatus
        guard authorized == .authorized || authorized == .provisional else { return }
        for plan in plans.prefix(60) {
            guard let car = cars.first(where: { $0.id == plan.carID }) else { continue }
            let status = plan.status(odometer: car.odometer)
            let content = UNMutableNotificationContent()
            content.title = "\(car.name): \(plan.title)"
            content.body = plan.details.isEmpty ? "Revisá este servicio en Garage." : plan.details
            content.sound = .default
            if status != .ok {
                let key = "garage.alerted.\(plan.id.recordName).\(plan.lastDate.timeIntervalSince1970).\(plan.lastKilometers)"
                guard !UserDefaults.standard.bool(forKey: key) else { continue }
                let id = "garage.\(plan.id.recordName).due"
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
                do { try await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger)); UserDefaults.standard.set(true, forKey: key) } catch {}
            } else if let due = plan.nextDate, let notice = Calendar.current.date(byAdding: .day, value: -plan.noticeDays, to: due), notice > .now {
                let components = Calendar.current.dateComponents([.year, .month, .day], from: notice)
                var atNine = components
                atNine.hour = 9
                let trigger = UNCalendarNotificationTrigger(dateMatching: atNine, repeats: false)
                try? await center.add(UNNotificationRequest(identifier: "garage.\(plan.id.recordName).upcoming", content: content, trigger: trigger))
            }
        }
    }
}
