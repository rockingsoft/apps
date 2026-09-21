import EventKit
import Foundation

@MainActor
final class EventKitService {
    let store = EKEventStore()
    var calendarAllowed: Bool { EKEventStore.authorizationStatus(for: .event) == .fullAccess }
    var remindersAllowed: Bool { EKEventStore.authorizationStatus(for: .reminder) == .fullAccess }
    func requestCalendars() async throws { _ = try await store.requestFullAccessToEvents() }
    func requestReminders() async throws { _ = try await store.requestFullAccessToReminders() }
    func sources() -> [CalendarSource] {
        let events = calendarAllowed ? store.calendars(for: .event) : []
        let reminders = remindersAllowed ? store.calendars(for: .reminder) : []
        return (events + reminders).map { .init(id: $0.calendarIdentifier, title: $0.title, reminder: $0.allowedEntityTypes.contains(.reminder)) }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }
    func load(from start: Date, to end: Date) async -> [AgendaItem] {
        var result: [AgendaItem] = []
        if calendarAllowed {
            result += store.events(matching: store.predicateForEvents(withStart: start, end: end, calendars: nil)).map {
                item($0, start: $0.startDate, end: $0.endDate, allDay: $0.isAllDay, reminder: false)
            }
        }
        if remindersAllowed {
            let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
            let reminders: [EKReminder] = await withCheckedContinuation { continuation in
                store.fetchReminders(matching: predicate) { continuation.resume(returning: $0 ?? []) }
            }
            result += reminders.map { reminder in
                let components = reminder.dueDateComponents
                let date = components.flatMap { ($0.calendar ?? Calendar.current).date(from: $0) }
                return item(reminder, start: date, end: nil, allDay: components?.hour == nil, reminder: true)
            }.filter { $0.start == nil || $0.start! < end }
        }
        return result.sorted {
            if $0.start != $1.start { return ($0.start ?? .distantFuture) < ($1.start ?? .distantFuture) }
            if $0.allDay != $1.allDay { return $0.allDay }
            return $0.title < $1.title
        }
    }
    func complete(_ item: AgendaItem) throws {
        guard item.reminder, let reminder = store.calendarItem(withIdentifier: item.id) as? EKReminder else { return }
        reminder.isCompleted = true
        try store.save(reminder, commit: true)
    }
    private func item(_ value: EKCalendarItem, start: Date?, end: Date?, allDay: Bool, reminder: Bool) -> AgendaItem {
        let rgb = value.calendar.cgColor?.converted(to: CGColorSpace(name: CGColorSpace.sRGB)!, intent: .defaultIntent, options: nil)?.components ?? [0.4, 0.8, 0.9, 1]
        return .init(id: reminder ? value.calendarItemIdentifier : "\(value.calendarItemIdentifier)-\(start?.timeIntervalSince1970 ?? 0)", title: value.title ?? "Sin título", start: start, end: end, allDay: allDay, reminder: reminder, calendarID: value.calendar.calendarIdentifier, calendarName: value.calendar.title, red: Double(rgb[0]), green: Double(rgb[1]), blue: Double(rgb[2]), meetingURL: reminder ? nil : MeetingLinks.extract(from: [value.url?.absoluteString, value.location, value.notes].compactMap { $0 }.joined(separator: "\n")), externalIdentifier: reminder ? nil : value.calendarItemExternalIdentifier, calendarItemIdentifier: reminder ? nil : value.calendarItemIdentifier)
    }
}
