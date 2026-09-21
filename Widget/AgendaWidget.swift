import SwiftUI
import WidgetKit

struct AgendaEntry: TimelineEntry {
    let date: Date
    let snapshot: AgendaSnapshot
}
struct AgendaProvider: TimelineProvider {
    func placeholder(in context: Context) -> AgendaEntry { .init(date: Date(), snapshot: .empty) }
    func getSnapshot(in context: Context, completion: @escaping (AgendaEntry) -> Void) {
        completion(.init(date: Date(), snapshot: AgendaCache.read()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<AgendaEntry>) -> Void) {
        Task { @MainActor in
            let service = EventKitService()
            var snapshot = AgendaCache.read()
            if service.calendarAllowed || service.remindersAllowed {
                let days = AgendaDates.monthDays(Date())
                let items = await service.load(from: days[0], to: Calendar.current.date(byAdding: .day, value: 1, to: days.last!)!)
                snapshot = .init(updated: Date(), items: items.filter { !AgendaCache.hiddenIDs.contains($0.calendarID) })
                AgendaCache.save(snapshot)
            }
            completion(Timeline(entries: [.init(date: Date(), snapshot: snapshot)], policy: .after(Date().addingTimeInterval(1800))))
        }
    }
}
struct AgendaWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: AgendaEntry
    var body: some View {
        Group {
            if family == .systemSmall { agenda(limit: 2) }
            else if family == .systemMedium {
                HStack(spacing: 0) {
                    MonthView(month: entry.date, selected: entry.date, items: entry.snapshot.items, compact: true)
                    agenda(limit: 3)
                }
            } else {
                VStack(spacing: 0) {
                    MonthView(month: entry.date, selected: entry.date, items: entry.snapshot.items, compact: true)
                    agenda(limit: family == .systemExtraLarge ? 6 : 3)
                }
            }
        }
        .containerBackground(Color(white: 0.125), for: .widget)
        .widgetURL(URL(string: "calendarwidget://today"))
    }
    private func agenda(limit: Int) -> some View {
        let items = entry.snapshot.items.filter { item in
            guard let start = item.start else { return item.reminder }
            return item.reminder || (item.end ?? start) >= Calendar.current.startOfDay(for: entry.date)
        }.prefix(limit)
        return VStack(alignment: .leading, spacing: 8) {
            DayHeading(date: entry.date)
            if entry.snapshot.updated == .distantPast {
                Text("Abrí Agenda y permití el acceso a tus calendarios y recordatorios.").font(.caption).foregroundStyle(.gray)
            } else if items.isEmpty {
                Text("Sin próximos eventos").font(.caption).foregroundStyle(.gray)
            } else {
                ForEach(Array(items)) { item in
                    VStack(alignment: .leading, spacing: 2) {
                        if let start = item.start, !Calendar.current.isDate(start, inSameDayAs: entry.date) {
                            Text(start.formatted(.dateTime.day().month(.abbreviated))).font(.system(size: 9)).foregroundStyle(.gray)
                        }
                        AgendaRow(item: item)
                    }
                }
            }
            Spacer(minLength: 0)
        }.padding(12).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
@main
struct AgendaWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "AgendaWidget", provider: AgendaProvider()) { AgendaWidgetView(entry: $0) }
            .configurationDisplayName("Calendario y recordatorios")
            .description("Tu mes y tu próxima agenda, en un solo lugar.")
            .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge])
            .contentMarginsDisabled()
    }
}
