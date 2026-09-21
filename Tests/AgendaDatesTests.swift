import Foundation

@main
struct AgendaDatesTests {
    static func main() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Argentina/Buenos_Aires")!
        calendar.firstWeekday = 2
        func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0) -> Date {
            calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
        }
        let days = AgendaDates.monthDays(date(2026, 9, 15), calendar: calendar)
        precondition(days.count == 42)
        precondition(days.first == date(2026, 8, 31))
        precondition(days.last == date(2026, 10, 11))
        let leap = AgendaDates.monthDays(date(2024, 2, 15), calendar: calendar)
        precondition(leap.contains(date(2024, 2, 29)))
        let item = AgendaItem(id: "1", title: "Trip", start: date(2026, 9, 14), end: date(2026, 9, 17), allDay: true, reminder: false, calendarID: "a", calendarName: "A", red: 1, green: 0, blue: 0)
        precondition(item.occurs(on: date(2026, 9, 14), calendar: calendar))
        precondition(item.occurs(on: date(2026, 9, 16), calendar: calendar))
        precondition(!item.occurs(on: date(2026, 9, 17), calendar: calendar))
        precondition(!item.occurs(on: date(2026, 9, 13), calendar: calendar))
        var reminder = item
        reminder.reminder = true
        reminder.start = date(2026, 9, 15, 18)
        reminder.end = nil
        precondition(reminder.occurs(on: date(2026, 9, 15), calendar: calendar))
        precondition(!reminder.occurs(on: date(2026, 9, 16), calendar: calendar))
        reminder.start = nil
        precondition(!reminder.occurs(on: date(2026, 9, 15), calendar: calendar))
        let encoded = try! JSONEncoder().encode(item)
        precondition(try! JSONDecoder().decode(AgendaItem.self, from: encoded) == item)
        print("PASS: month boundaries, leap year, multi-day exclusivity, reminders, snapshot round-trip")
    }
}
