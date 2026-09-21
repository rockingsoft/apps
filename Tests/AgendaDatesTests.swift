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
        let snapshot = AgendaSnapshot(updated: Date(), items: [item], calendarAccess: true, remindersAccess: false)
        let decoded = try! JSONDecoder().decode(AgendaSnapshot.self, from: JSONEncoder().encode(snapshot))
        precondition(decoded.calendarAccess == true && decoded.remindersAccess == false)
        let legacy = try! JSONDecoder().decode(AgendaSnapshot.self, from: Data("{\"updated\":0,\"items\":[]}".utf8))
        precondition(legacy.calendarAccess == nil && legacy.remindersAccess == nil)
        precondition(WidgetAgendaData.monthDays(date(2026, 9, 15), calendar: calendar).count == 35)
        precondition(WidgetAgendaData.monthDays(date(2026, 8, 15), calendar: calendar).count == 42)
        precondition(MeetingLinks.extract(from: "Join https://us02web.zoom.us/j/123456?pwd=abc")?.host == "us02web.zoom.us")
        precondition(MeetingLinks.extract(from: "<a href=\"https://meet.google.com/abc-defg-hij\">Meet</a>")?.host == "meet.google.com")
        precondition(MeetingLinks.extract(from: "https://zoom.us.evil.test/j/123") == nil)
        precondition(MeetingLinks.extract(from: "https://evilzoom.us/j/123") == nil)
        precondition(MeetingLinks.extract(from: "http://zoom.us/j/123") == nil)
        precondition(MeetingLinks.extract(from: "https://zoom.us/pricing") == nil)
        var event = item
        event.allDay = false
        event.start = date(2026, 9, 15, 12)
        event.end = date(2026, 9, 15, 13)
        event.meetingURL = URL(string: "https://meet.google.com/abc-defg-hij")
        reminder.start = date(2026, 9, 15, 11)
        let mixed = [item, event, reminder]
        precondition(WidgetAgendaData.filtered(mixed, calendarIDs: [], showTasks: false, showAllDay: true).isEmpty)
        precondition(WidgetAgendaData.filtered(mixed, calendarIDs: ["a"], showTasks: false, showAllDay: false) == [event])
        precondition(WidgetAgendaData.filtered(mixed, calendarIDs: [], showTasks: true, showAllDay: false) == [reminder])
        precondition(WidgetAgendaData.nextEvent(in: mixed, at: date(2026, 9, 15, 10)) == event)
        precondition(WidgetAgendaData.nextEvent(in: mixed, at: date(2026, 9, 15, 14)) == nil)
        var future = event
        future.id = "future"
        future.start = date(2026, 9, 15, 14)
        future.end = date(2026, 9, 15, 15)
        future.meetingURL = nil
        precondition(WidgetAgendaData.nextEvent(in: [event, future], at: date(2026, 9, 15, 12)) == event)
        precondition(WidgetAgendaData.nextEvent(in: [event, future], at: date(2026, 9, 15, 13)) == future)
        print("PASS: dates, snapshots, widget filters, next event selection, Zoom/Meet links and host validation")
    }
}
