import SwiftUI
import EventKit
import WidgetKit
import OSLog
#if os(macOS)
import AppKit
#else
import UIKit
#endif

@MainActor
final class AgendaModel: ObservableObject {
    private let logger = Logger(subsystem: "com.schoren.calendarwidget", category: "DeepLink")
    @Published var month = Date()
    @Published var selected = Calendar.current.startOfDay(for: Date())
    @Published var items: [AgendaItem] = []
    @Published var sources: [CalendarSource] = []
    @Published var hidden = AgendaCache.hiddenIDs
    @Published var calendarAllowed = false
    @Published var remindersAllowed = false
    @Published var loading = false
    @Published var error: String?
    let service = EventKitService()
    private var generation = 0
    var visible: [AgendaItem] { items.filter { !hidden.contains($0.calendarID) } }
    func refresh() async {
        generation += 1
        let request = generation
        loading = true
        calendarAllowed = service.calendarAllowed
        remindersAllowed = service.remindersAllowed
        sources = service.sources()
        let days = AgendaDates.monthDays(month)
        let start = min(days[0], Calendar.current.startOfDay(for: Date()))
        let end = max(Calendar.current.date(byAdding: .day, value: 30, to: Date())!, Calendar.current.date(byAdding: .day, value: 14, to: days.last!)!)
        let loaded = await service.load(from: start, to: end)
        guard request == generation else { return }
        items = loaded
        loading = false
        publish()
    }
    func request(_ reminders: Bool) async {
        do {
            if reminders { try await service.requestReminders() } else { try await service.requestCalendars() }
            await refresh()
        } catch { self.error = error.localizedDescription }
    }
    func complete(_ item: AgendaItem) {
        do { try service.complete(item); Task { await refresh() } }
        catch { self.error = error.localizedDescription }
    }
    func toggle(_ source: CalendarSource) {
        if hidden.contains(source.id) { hidden.remove(source.id) } else { hidden.insert(source.id) }
        AgendaCache.hiddenIDs = hidden
        publish()
    }
    private func publish() {
        AgendaCache.save(.init(updated: Date(), items: items, calendarAccess: calendarAllowed, remindersAccess: remindersAllowed, sources: sources))
        WidgetCenter.shared.reloadAllTimelines()
    }
    func move(_ offset: Int) {
        month = Calendar.current.date(byAdding: .month, value: offset, to: month)!
        selected = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: month))!
    }
    func open(_ url: URL) {
        let parameters = Dictionary(uniqueKeysWithValues: (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []).compactMap { item in
            item.value.map { (item.name, $0) }
        })
        if url.host == "join", let value = parameters["url"], let meetingURL = URL(string: value), MeetingLinks.isAllowed(meetingURL) {
            openExternal(meetingURL)
        } else if url.host == "event", let identifier = parameters["id"] {
            openCalendarEvent(
                identifier: identifier,
                title: parameters["title"] ?? "",
                calendarName: parameters["calendar"] ?? "",
                timestamp: Double(parameters["timestamp"] ?? "")
            )
        } else if url.host == "calendar" {
            openCalendar(timestamp: Double(parameters["timestamp"] ?? ""))
        } else if url.host == "day", let value = parameters["timestamp"], let timestamp = Double(value), timestamp.isFinite {
            let day = Date(timeIntervalSince1970: timestamp)
            month = day
            selected = Calendar.current.startOfDay(for: day)
        } else { today() }
    }
    private func openExternal(_ url: URL) {
        #if os(macOS)
        NSWorkspace.shared.open(url)
        NSApp.hide(nil)
        #else
        UIApplication.shared.open(url)
        #endif
    }
    private func openCalendar(timestamp: Double?) {
        #if os(macOS)
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") {
            NSWorkspace.shared.openApplication(at: appURL, configuration: .init())
        }
        #else
        let date = timestamp.map(Date.init(timeIntervalSince1970:)) ?? Date()
        openExternal(URL(string: "calshow:\(date.timeIntervalSinceReferenceDate)")!)
        #endif
    }
    private func appleScriptLiteral(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }
    private func openCalendarEvent(identifier: String, title: String, calendarName: String, timestamp: Double?) {
        #if os(macOS)
        guard let timestamp, timestamp.isFinite else { openCalendar(timestamp: timestamp); return }
        let date = Date(timeIntervalSince1970: timestamp)
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let escapedIdentifier = appleScriptLiteral(identifier)
        let escapedTitle = appleScriptLiteral(title)
        let escapedCalendar = appleScriptLiteral(calendarName)
        let seconds = (components.hour ?? 0) * 3600 + (components.minute ?? 0) * 60 + (components.second ?? 0)
        let source = """
        tell application "Calendar"
            set targetDate to current date
            set day of targetDate to 1
            set year of targetDate to \(components.year ?? 2001)
            set month of targetDate to \(components.month ?? 1)
            set day of targetDate to \(components.day ?? 1)
            set time of targetDate to \(seconds)
            set bestEvent to missing value
            set bestDifference to 999999999
            repeat with aCalendar in calendars
                if name of aCalendar is "\(escapedCalendar)" then
                    repeat with anEvent in events of aCalendar
                        try
                            if summary of anEvent is "\(escapedTitle)" then
                                set eventDifference to (start date of anEvent) - targetDate
                                if eventDifference < 0 then set eventDifference to -eventDifference
                                if eventDifference < bestDifference then
                                    set bestDifference to eventDifference
                                    set bestEvent to anEvent
                                end if
                            end if
                        end try
                    end repeat
                end if
            end repeat
            if bestEvent is missing value then
                repeat with aCalendar in calendars
                    repeat with anEvent in events of aCalendar
                        try
                            if uid of anEvent is "\(escapedIdentifier)" then
                                set eventDifference to (start date of anEvent) - targetDate
                                if eventDifference < 0 then set eventDifference to -eventDifference
                                if eventDifference < bestDifference then
                                    set bestDifference to eventDifference
                                    set bestEvent to anEvent
                                end if
                            end if
                        end try
                    end repeat
                end repeat
            end if
            if bestEvent is not missing value then
                show bestEvent
                activate
                return "FOUND"
            end if
            return "NOT_FOUND"
        end tell
        """
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error).stringValue
        logger.notice("Calendar event open result=\(result ?? "nil", privacy: .public) error=\(String(describing: error), privacy: .public)")
        if error != nil || result != "FOUND" { openCalendar(timestamp: timestamp) }
        else { NSApp.hide(nil) }
        #else
        openCalendar(timestamp: timestamp)
        #endif
    }
    func today() { month = Date(); selected = Calendar.current.startOfDay(for: Date()) }
}
