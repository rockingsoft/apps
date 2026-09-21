import SwiftUI
import WidgetKit
import AppIntents

struct AgendaEntry: TimelineEntry {
    let date: Date
    let snapshot: AgendaSnapshot
    var showMonth = true
}
struct AgendaProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> AgendaEntry { .init(date: Date(), snapshot: .empty) }
    func snapshot(for configuration: AgendaConfiguration, in context: Context) async -> AgendaEntry {
        configured(AgendaCache.read(), configuration, at: Date())
    }
    @MainActor
    private func refreshedSnapshot() async -> AgendaSnapshot {
        let service = EventKitService()
        var snapshot = AgendaCache.read()
        if service.calendarAllowed || service.remindersAllowed {
            let days = AgendaDates.monthDays(Date())
            let loaded = await service.load(from: days[0], to: Calendar.current.date(byAdding: .day, value: 1, to: days.last!)!)
            let events = service.calendarAllowed && snapshot.calendarAccess == true
                ? loaded.filter { !$0.reminder } : snapshot.items.filter { !$0.reminder }
            let reminders = service.remindersAllowed && snapshot.remindersAccess == true
                ? loaded.filter { $0.reminder } : snapshot.items.filter { $0.reminder }
            snapshot.items = events + reminders
        }
        return snapshot
    }
    func timeline(for configuration: AgendaConfiguration, in context: Context) async -> Timeline<AgendaEntry> {
        let snapshot = await refreshedSnapshot()
        let now = Date()
        // Schedule known event boundaries so “next” and Join advance without
        // waiting for a fresh EventKit query. WidgetKit controls delivery timing.
        let horizon = now.addingTimeInterval(1800)
        let boundaries = snapshot.items.flatMap { [$0.start, $0.end].compactMap { $0 } }
            .filter { $0 > now && $0 < horizon }
        let dates = [now] + Array(Set(boundaries)).sorted()
        let entries = dates.map { configured(snapshot, configuration, at: $0) }
        return Timeline(entries: entries, policy: .after(horizon))
    }
    private func configured(_ snapshot: AgendaSnapshot, _ configuration: AgendaConfiguration, at date: Date) -> AgendaEntry {
        var result = snapshot
        let ids: Set<String>? = configuration.allCalendars ? nil : Set((configuration.calendars ?? []).map(\.id))
        result.items = WidgetAgendaData.filtered(snapshot.items, calendarIDs: ids, showTasks: configuration.showTasks, showAllDay: configuration.showAllDay)
        return .init(date: date, snapshot: result, showMonth: configuration.showMonth)
    }
}
struct WidgetMonthView: View {
    let date: Date
    let items: [AgendaItem]
    var small = false
    private let calendar = Calendar.current
    var body: some View {
        let days = WidgetAgendaData.monthDays(date)
        VStack(spacing: small ? 6 : 10) {
            HStack(spacing: 5) {
                Text(date.formatted(.dateTime.month(.wide)).capitalized).fontWeight(.bold)
                Text(date.formatted(.dateTime.year())).foregroundStyle(.red)
                Spacer(minLength: 0)
            }.font(.system(size: small ? 16 : 22)).lineLimit(1).minimumScaleFactor(0.75)
            HStack(spacing: 0) {
                ForEach(0..<7) { offset in
                    Text(calendar.shortStandaloneWeekdaySymbols[(calendar.firstWeekday - 1 + offset) % 7].uppercased())
                        .font(.system(size: 9, weight: .medium)).foregroundStyle(.gray).frame(maxWidth: .infinity)
                }
            }
            VStack(spacing: 0) {
                ForEach(0..<(days.count / 7), id: \.self) { week in
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
                if family == .systemSmall || !entry.showMonth { agenda }
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
                            .frame(height: geometry.size.height * 0.53)
                        agenda
                    }
                }
            }
        }
        .containerBackground(Color(white: 0.125), for: .widget)
        .widgetURL(URL(string: "calendarwidget://today"))
    }
    private var nextEvent: AgendaItem? { WidgetAgendaData.nextEvent(in: entry.snapshot.items, at: entry.date) }
    private var following: [AgendaItem] {
        entry.snapshot.items.filter { item in
            guard item.id != nextEvent?.id else { return false }
            if item.reminder { return item.start == nil || item.start! >= Calendar.current.startOfDay(for: entry.date) }
            return !item.allDay && (item.end ?? item.start ?? .distantPast) > entry.date
        }.sorted { ($0.start ?? .distantFuture) < ($1.start ?? .distantFuture) }
    }
    private var allDayItems: [AgendaItem] {
        entry.snapshot.items.filter { !$0.reminder && $0.allDay && $0.occurs(on: entry.date) }
    }
    private var agenda: some View {
        VStack(alignment: .leading, spacing: 10) {
            if entry.snapshot.calendarAccess != true && entry.snapshot.remindersAccess != true {
                Text("Conectá tu agenda").font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                Text("Habilitá Calendario y Recordatorios en Agenda.").font(.system(size: 12)).foregroundStyle(.gray)
            } else {
                ViewThatFits(in: .vertical) {
                    agendaContent(extra: 3)
                    agendaContent(extra: 2)
                    agendaContent(extra: 1)
                    agendaContent(extra: 0)
                }
            }
            Spacer(minLength: 0)
            Link(destination: URL(string: "calendarwidget://today")!) {
                HStack {
                    Text("Abrir agenda")
                    Spacer()
                    Image(systemName: "arrow.up.right")
                }.font(.system(size: 11, weight: .medium)).foregroundStyle(Color(white: 0.72))
            }.buttonStyle(.plain).accessibilityLabel("Abrir el calendario completo")
        }
        .padding(family == .systemSmall ? 12 : 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(white: 0.125))
    }
    private func agendaContent(extra: Int) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            if let event = nextEvent {
                eventRow(event, primary: true)
            } else if following.isEmpty {
                DayHeading(date: entry.date)
                Text("Sin próximos eventos").font(.system(size: 13)).foregroundStyle(.gray)
            }
            ForEach(Array(following.prefix(extra))) { item in eventRow(item, primary: false) }
            if !allDayItems.isEmpty && (extra > 0 || nextEvent == nil) {
                let titles = Array(Set(allDayItems.map(\.title))).sorted()
                Text("Todo el día · " + titles.joined(separator: " · "))
                    .font(.system(size: 10)).foregroundStyle(.gray).lineLimit(1)
                    .accessibilityLabel("Eventos de todo el día: " + titles.joined(separator: ", "))
            }
        }.fixedSize(horizontal: false, vertical: true)
    }
    private func eventRow(_ item: AgendaItem, primary: Bool) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            if primary {
                Text(item.start! <= entry.date ? "EN CURSO" : "PRÓXIMO EVENTO")
                    .font(.system(size: 9, weight: .bold)).tracking(0.7).foregroundStyle(.cyan)
            }
            HStack(alignment: .center, spacing: 10) {
                RoundedRectangle(cornerRadius: 2).fill(item.color).frame(width: 3)
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title).font(.system(size: primary ? 14 : 12, weight: .semibold))
                        .foregroundStyle(.white).lineLimit(primary ? 2 : 1)
                    HStack(spacing: 4) {
                        if item.reminder { Image(systemName: "checklist") }
                        if let start = item.start {
                            if !Calendar.current.isDate(start, inSameDayAs: entry.date) {
                                Text(start.formatted(.dateTime.day().month(.abbreviated)))
                            }
                            if !item.allDay { Text(start, style: .time) }
                        } else { Text("Sin fecha") }
                    }.font(.system(size: 11)).foregroundStyle(Color(white: 0.65))
                }
                Spacer(minLength: 0)
                if primary, family != .systemSmall, let url = item.meetingURL, MeetingLinks.isAllowed(url) {
                    Link(destination: url) {
                        Label("Unirse", systemImage: "video.fill")
                            .font(.system(size: 11, weight: .semibold)).padding(.horizontal, 9).padding(.vertical, 8)
                            .background(Color.blue, in: Capsule()).foregroundStyle(.white)
                    }.buttonStyle(.plain).accessibilityLabel("Unirse a \(item.title)")
                }
            }.fixedSize(horizontal: false, vertical: true)
        }
    }

}
@main
struct AgendaWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "AgendaWidget", intent: AgendaConfiguration.self, provider: AgendaProvider()) { AgendaWidgetView(entry: $0) }
            .configurationDisplayName("Calendario y recordatorios")
            .description("Tu mes y tu próxima agenda, en un solo lugar.")
            .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .systemExtraLarge])
            .contentMarginsDisabled()
    }
}
