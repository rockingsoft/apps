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
            // The app owns the cache. An extension with partial authorization must
            // never replace the app's full snapshot with an empty result.
            if service.calendarAllowed || service.remindersAllowed {
                let days = AgendaDates.monthDays(Date())
                let loaded = await service.load(from: days[0], to: Calendar.current.date(byAdding: .day, value: 1, to: days.last!)!)
                let events = service.calendarAllowed && snapshot.calendarAccess == true
                    ? loaded.filter { !$0.reminder } : snapshot.items.filter { !$0.reminder }
                let reminders = service.remindersAllowed && snapshot.remindersAccess == true
                    ? loaded.filter { $0.reminder } : snapshot.items.filter { $0.reminder }
                snapshot.items = (events + reminders).filter { !AgendaCache.hiddenIDs.contains($0.calendarID) }
            }
            completion(Timeline(entries: [.init(date: Date(), snapshot: snapshot)], policy: .after(Date().addingTimeInterval(1800))))
        }
    }
}
struct WidgetMonthView: View {
    let date: Date
    let items: [AgendaItem]
    var small = false
    private let calendar = Calendar.current
    var body: some View {
        let days = AgendaDates.monthDays(date)
        VStack(spacing: small ? 5 : 8) {
            HStack(spacing: 5) {
                Text(date.formatted(.dateTime.month(.wide)).capitalized).fontWeight(.bold)
                Text(date.formatted(.dateTime.year())).foregroundStyle(.red)
                Spacer(minLength: 0)
            }.font(.system(size: small ? 16 : 24)).lineLimit(1).minimumScaleFactor(0.75)
            HStack(spacing: 0) {
                ForEach(0..<7) { offset in
                    Text(calendar.shortStandaloneWeekdaySymbols[(calendar.firstWeekday - 1 + offset) % 7].uppercased())
                        .font(.system(size: 9, weight: .medium)).foregroundStyle(.gray).frame(maxWidth: .infinity)
                }
            }
            VStack(spacing: 0) {
                ForEach(0..<6) { week in
                    HStack(spacing: 0) {
                        ForEach(0..<7) { weekday in
                            let day = days[week * 7 + weekday]
                            let today = calendar.isDateInToday(day)
                            VStack(spacing: 1) {
                                Text(day.formatted(.dateTime.day()))
                                    .font(.system(size: small ? 10 : 12, weight: today ? .semibold : .regular))
                                    .foregroundStyle(today ? .white : calendar.isDate(day, equalTo: date, toGranularity: .month) ? Color(white: 0.12) : .gray)
                                    .frame(width: small ? 17 : 21, height: small ? 14 : 18)
                                    .background { if today { Circle().fill(Color.blue) } }
                                HStack(spacing: 2) {
                                    ForEach(Array(items.filter { $0.occurs(on: day) }.prefix(4).enumerated()), id: \.offset) { _, item in
                                        Circle().fill(item.color).frame(width: 3, height: 3)
                                    }
                                }.frame(height: 3)
                            }.frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }.frame(maxHeight: .infinity)
                }
            }
        }
        .padding(.horizontal, small ? 10 : 16).padding(.vertical, small ? 10 : 12)
        .foregroundStyle(Color(white: 0.12)).background(Color(white: 0.965))
        .environment(\.colorScheme, .light)
    }
}

struct AgendaWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: AgendaEntry
    var body: some View {
        GeometryReader { geometry in
            Group {
                if family == .systemSmall { agenda }
                else if family == .systemMedium {
                    HStack(spacing: 0) {
                        WidgetMonthView(date: entry.date, items: entry.snapshot.items, small: true)
                            .frame(width: geometry.size.width * 0.51)
                        agenda
                    }
                } else if family == .systemExtraLarge {
                    HStack(spacing: 0) {
                        WidgetMonthView(date: entry.date, items: entry.snapshot.items)
                            .frame(width: geometry.size.width * 0.48)
                        agenda
                    }
                } else {
                    VStack(spacing: 0) {
                        WidgetMonthView(date: entry.date, items: entry.snapshot.items)
                            .frame(height: geometry.size.height * 0.56)
                        agenda
                    }
                }
            }
        }
        .containerBackground(Color(white: 0.125), for: .widget)
        .widgetURL(URL(string: "calendarwidget://today"))
    }
    private var upcoming: [AgendaItem] {
        entry.snapshot.items.filter { item in
            guard let start = item.start else { return item.reminder }
            if item.reminder { return start >= Calendar.current.startOfDay(for: entry.date) }
            return (item.end ?? start) > entry.date || (item.allDay && item.occurs(on: entry.date))
        }.sorted { ($0.start ?? .distantFuture) < ($1.start ?? .distantFuture) }
    }
    private var agenda: some View {
        VStack(alignment: .leading, spacing: 6) {
            if entry.snapshot.calendarAccess != true && entry.snapshot.remindersAccess != true {
                Text("Conectá tu agenda").font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                Text("Abrí Agenda y habilitá Calendario y Recordatorios.")
                    .font(.system(size: 12)).foregroundStyle(Color(white: 0.7))
                Text("Abrir Agenda ↗").font(.system(size: 12, weight: .semibold)).foregroundStyle(.cyan)
            } else if upcoming.isEmpty {
                DayHeading(date: entry.date)
                Text("Sin próximos eventos ni recordatorios").font(.system(size: 12)).foregroundStyle(.gray)
            } else {
                ViewThatFits(in: .vertical) {
                    rows(limit: 6)
                    rows(limit: 5)
                    rows(limit: 4)
                    rows(limit: 3)
                    rows(limit: 2)
                    rows(limit: 1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(white: 0.125))
    }
    private func rows(limit: Int) -> some View {
        let items = Array(upcoming.prefix(limit))
        return VStack(alignment: .leading, spacing: 7) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                let day = item.start.map { Calendar.current.startOfDay(for: $0) }
                let previous = index > 0 ? items[index - 1].start.map { Calendar.current.startOfDay(for: $0) } : nil
                if index == 0 || day != previous {
                    if let day { DayHeading(date: day) }
                    else { Text("SIN FECHA").font(.system(size: 10, weight: .bold)).foregroundStyle(.gray) }
                }
                HStack(alignment: .top, spacing: 7) {
                    Image(systemName: item.reminder ? "circle" : "circle.fill")
                        .font(.system(size: item.reminder ? 12 : 9)).foregroundStyle(item.color).padding(.top, 3)
                    VStack(alignment: .leading, spacing: 1) {
                        if !item.allDay, let start = item.start {
                            HStack(spacing: 3) {
                                Text(start, style: .time)
                                if let end = item.end { Text("–"); Text(end, style: .time) }
                            }.font(.system(size: 10, weight: .medium)).foregroundStyle(Color(white: 0.68))
                        }
                        Text(item.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                            .padding(.horizontal, item.allDay && !item.reminder ? 4 : 0)
                            .background(item.allDay && !item.reminder ? item.color.opacity(0.65) : .clear, in: RoundedRectangle(cornerRadius: 3))
                    }
                    Spacer(minLength: 0)
                }.foregroundStyle(.white)
            }
        }.fixedSize(horizontal: false, vertical: true)
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
