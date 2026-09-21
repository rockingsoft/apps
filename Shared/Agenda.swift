import Foundation
import SwiftUI

struct AgendaItem: Codable, Identifiable, Hashable {
    var id: String
    var title: String
    var start: Date?
    var end: Date?
    var allDay: Bool
    var reminder: Bool
    var calendarID: String
    var calendarName: String
    var red: Double
    var green: Double
    var blue: Double
    var color: Color { Color(red: red, green: green, blue: blue) }
    func occurs(on day: Date, calendar: Calendar = .current) -> Bool {
        guard let start else { return false }
        let lower = calendar.startOfDay(for: day)
        let upper = calendar.date(byAdding: .day, value: 1, to: lower)!
        return start < upper && (end.map { $0 > lower && $0 > start } ?? false || start >= lower)
    }
}

struct CalendarSource: Identifiable, Hashable {
    let id: String
    let title: String
    let reminder: Bool
}

struct AgendaSnapshot: Codable {
    var updated: Date
    var items: [AgendaItem]
    static let empty = AgendaSnapshot(updated: .distantPast, items: [])
}

enum AgendaDates {
    static func monthDays(_ date: Date, calendar: Calendar = .current) -> [Date] {
        let first = calendar.date(from: calendar.dateComponents([.year, .month], from: date))!
        let offset = (calendar.component(.weekday, from: first) - calendar.firstWeekday + 7) % 7
        let start = calendar.date(byAdding: .day, value: -offset, to: first)!
        return (0..<42).map { calendar.date(byAdding: .day, value: $0, to: start)! }
    }
    static func title(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return "HOY" }
        if Calendar.current.isDateInTomorrow(date) { return "MAÑANA" }
        return date.formatted(.dateTime.weekday(.wide)).uppercased()
    }
}

enum AgendaCache {
    static let group = Bundle.main.object(forInfoDictionaryKey: "AgendaAppGroup") as? String ?? "group.com.schoren.calendarwidget"
    static var defaults: UserDefaults { UserDefaults(suiteName: group) ?? .standard }
    static var hiddenIDs: Set<String> {
        get { Set(defaults.stringArray(forKey: "hiddenSources") ?? []) }
        set { defaults.set(Array(newValue), forKey: "hiddenSources") }
    }
    static var url: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)?.appendingPathComponent("agenda.json")
    }
    static func save(_ snapshot: AgendaSnapshot) {
        guard let url, let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
    static func read() -> AgendaSnapshot {
        guard let url, let data = try? Data(contentsOf: url), let value = try? JSONDecoder().decode(AgendaSnapshot.self, from: data) else { return .empty }
        return value
    }
}
