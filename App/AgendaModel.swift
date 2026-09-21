import SwiftUI
import EventKit
import WidgetKit

@MainActor
final class AgendaModel: ObservableObject {
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
        AgendaCache.save(.init(updated: Date(), items: visible, calendarAccess: calendarAllowed, remindersAccess: remindersAllowed))
        WidgetCenter.shared.reloadAllTimelines()
    }
    func move(_ offset: Int) {
        month = Calendar.current.date(byAdding: .month, value: offset, to: month)!
        selected = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: month))!
    }
    func today() { month = Date(); selected = Calendar.current.startOfDay(for: Date()) }
}
