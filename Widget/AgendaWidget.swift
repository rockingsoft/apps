import SwiftUI
import WidgetKit
import AppIntents

struct AgendaEntry: TimelineEntry {
    let date: Date
    let snapshot: AgendaSnapshot
    var showMonth = true
    var selectedDay: Date = Date()
    var selectionKey = "preview"
}
struct AgendaProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> AgendaEntry { .init(date: Date(), snapshot: .empty) }
    func snapshot(for configuration: AgendaConfiguration, in context: Context) async -> AgendaEntry {
        configured(AgendaCache.read(), configuration, at: Date())
    }
    func timeline(for configuration: AgendaConfiguration, in context: Context) async -> Timeline<AgendaEntry> {
        // Interactive navigation must be instant. EventKit refreshes belong to the
        // host app; every click redraws from its shared snapshot.
        let snapshot = AgendaCache.read()
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
        return .init(date: date, snapshot: result, showMonth: configuration.showMonth, selectedDay: configuration.selectedDate(now: date), selectionKey: configuration.selectionKey)
    }
}
struct WidgetMonthView: View {
    let date: Date
    let items: [AgendaItem]
    var small = false
    var dark = false
    var selectionKey = "preview"
    private let calendar = Calendar.current
    private func month(_ offset: Int) -> Date {
        let first = calendar.date(from: calendar.dateComponents([.year, .month], from: date))!
        return calendar.date(byAdding: .month, value: offset, to: first)!
    }
    var body: some View {
        let days = WidgetAgendaData.monthDays(date)
        VStack(spacing: small ? 4 : 6) {
            HStack(spacing: 5) {
                Text(date.formatted(.dateTime.month(.wide)).capitalized).fontWeight(.bold)
                if !small { Text(date.formatted(.dateTime.year())).foregroundStyle(.red) }
                Spacer(minLength: 0)
                Button(intent: SelectWidgetDay(date: month(-1), key: selectionKey)) {
                    Image(systemName: "chevron.left").font(.system(size: 11, weight: .semibold))
                        .frame(width: small ? 16 : 22, height: 24).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel("Mes anterior")
                Button(intent: SelectWidgetDay(date: nil, key: selectionKey)) {
                    Text("Hoy").font(.system(size: 10, weight: .medium)).foregroundStyle(.blue)
                        .padding(4).contentShape(Rectangle())
                }.buttonStyle(.plain)
                Button(intent: SelectWidgetDay(date: month(1), key: selectionKey)) {
                    Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold))
                        .frame(width: small ? 16 : 22, height: 24).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel("Mes siguiente")
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
                            Button(intent: SelectWidgetDay(date: day, key: selectionKey)) {
                            VStack(spacing: 1) {
                                Text(day.formatted(.dateTime.day()))
                                    .font(.system(size: small ? 10 : 12, weight: today ? .semibold : .regular))
                                    .foregroundStyle(today ? .white : calendar.isDate(day, equalTo: date, toGranularity: .month) ? (dark ? .white : Color(white: 0.12)) : .gray)
                                    .frame(width: small ? 17 : 20, height: small ? 11 : 16)
                                    .background {
                                        if today { Circle().fill(Color.blue) }
                                        else if calendar.isDate(day, inSameDayAs: date) { Circle().fill(Color.blue.opacity(0.18)) }
                                    }
                                HStack(spacing: 2) {
                                    ForEach(Array(items.filter { $0.occurs(on: day) }.prefix(4).enumerated()), id: \.offset) { _, item in
                                        Circle().fill(item.color).frame(width: 3, height: 3)
                                    }
                                }.frame(height: 3)
                            }.frame(maxWidth: .infinity, maxHeight: .infinity).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                                .accessibilityLabel(day.formatted(date: .complete, time: .omitted))
                                .accessibilityAddTraits(calendar.isDate(day, inSameDayAs: date) ? .isSelected : [])
                        }
                    }.frame(height: small ? 15 : 20)
                }
            }
            .frame(height: CGFloat(days.count / 7) * (small ? 15 : 20), alignment: .top)
        }
        .padding(.horizontal, small ? 10 : 16).padding(.vertical, 7)
        .foregroundStyle(dark ? .white : Color(white: 0.12))
        .background(dark ? Color(white: 0.125) : Color(white: 0.965))
        .environment(\.colorScheme, dark ? .dark : .light)
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
                        WidgetMonthView(date: entry.selectedDay, items: entry.snapshot.items, small: true, dark: mediumMonthIsDark, selectionKey: entry.selectionKey)
                            .frame(width: geometry.size.width * 0.51)
                        agenda
                    }
                } else if family == .systemExtraLarge {
                    HStack(spacing: 0) {
                        WidgetMonthView(date: entry.selectedDay, items: entry.snapshot.items, selectionKey: entry.selectionKey)
                            .frame(width: geometry.size.width * 0.48)
                        agenda
                    }
                } else {
                    VStack(spacing: 0) {
                        WidgetMonthView(date: entry.selectedDay, items: entry.snapshot.items, selectionKey: entry.selectionKey)
                            .frame(height: geometry.size.height * 0.53)
                        agenda
                    }
                }
            }
        }
        .containerBackground(Color(white: 0.125), for: .widget)
        .widgetURL(family == .systemSmall ? calendarURL : nil)
    }
    private var mediumMonthIsDark: Bool {
        #if os(iOS)
        true
        #else
        false
        #endif
    }
    private var calendarURL: URL { deepLink(host: "calendar", values: ["timestamp": String(entry.selectedDay.timeIntervalSince1970)]) }
    private func deepLink(host: String, values: [String: String]) -> URL {
        var components = URLComponents()
        components.scheme = "calendarwidget"
        components.host = host
        components.queryItems = values.map { URLQueryItem(name: $0.key, value: $0.value) }
        return components.url!
    }
    private var dayItems: [AgendaItem] { entry.snapshot.items.filter { $0.occurs(on: entry.selectedDay) } }
    private var nextEvent: AgendaItem? {
        let events = dayItems.filter { !$0.reminder && !$0.allDay }.sorted { $0.start! < $1.start! }
        if Calendar.current.isDate(entry.selectedDay, inSameDayAs: entry.date) {
            return WidgetAgendaData.nextEvent(in: events, at: entry.date) ?? events.first
        }
        return events.first
    }
    private var following: [AgendaItem] {
        dayItems.filter { $0.id != nextEvent?.id }
            .sorted { ($0.start ?? .distantFuture) < ($1.start ?? .distantFuture) }
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
            Link(destination: calendarURL) { calendarLabel }.buttonStyle(.plain)

        }
        .padding(family == .systemSmall ? 12 : 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(white: 0.125))
    }
    private func agendaContent(extra: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            DayHeading(date: entry.selectedDay)
            if let event = nextEvent {
                eventRow(event, primary: true)
            } else if dayItems.isEmpty {
                Text("Sin eventos ni tareas este día").font(.system(size: 13)).foregroundStyle(.gray)
            }
            ForEach(Array(following.prefix(extra))) { item in eventRow(item, primary: false) }
            if following.count > extra {
                Label("\(following.count - extra) más", systemImage: "ellipsis")
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
            }

        }.fixedSize(horizontal: false, vertical: true)
    }
    private func eventRow(_ item: AgendaItem, primary: Bool) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .center, spacing: 10) {
                Link(destination: item.reminder ? calendarURL : eventURL(item)) {
                    HStack(alignment: .center, spacing: 10) {
                        if item.isBirthday {
                            Text("🎁").font(.system(size: primary ? 15 : 13))
                        } else {
                            RoundedRectangle(cornerRadius: 2).fill(item.color).frame(width: 3)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.displayTitle).font(.system(size: primary ? 14 : 12, weight: .semibold))
                                .foregroundStyle(.white).lineLimit(primary || item.allDay ? 2 : 1)
                            if !item.isBirthday { HStack(spacing: 4) {
                                if item.reminder { Image(systemName: "checklist") }
                                if item.allDay { Text("Todo el día") }
                                else if let start = item.start {
                                    if !Calendar.current.isDate(start, inSameDayAs: entry.selectedDay) {
                                        Text(start.formatted(.dateTime.day().month(.abbreviated)))
                                    }
                                    Text(start, style: .time)
                                } else { Text("Sin fecha") }
                            }.font(.system(size: 11)).foregroundStyle(Color(white: 0.65)) }
                        }
                        Spacer(minLength: 0)
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityHint("Abrir en Calendario de Apple")
                if primary, item.id == WidgetAgendaData.nextEvent(in: entry.snapshot.items, at: entry.date)?.id, family != .systemSmall, let url = item.meetingURL, MeetingLinks.isAllowed(url) {
                    Link(destination: deepLink(host: "join", values: ["url": url.absoluteString])) { joinLabel }
                        .buttonStyle(.plain).accessibilityLabel("Unirse a \(item.title)")
                }
            }.fixedSize(horizontal: false, vertical: true)
        }
    }
    private func eventURL(_ item: AgendaItem) -> URL {
        deepLink(host: "event", values: [
            "id": item.externalIdentifier ?? "",
            "title": item.title,
            "calendar": item.calendarName,
            "timestamp": String((item.start ?? entry.selectedDay).timeIntervalSince1970)
        ])
    }

    private var calendarLabel: some View {
        HStack {
            Text("Abrir Calendario")
            Spacer()
            Image(systemName: "arrow.up.right")
        }.font(.system(size: 11, weight: .medium)).foregroundStyle(Color(white: 0.72))
            .contentShape(Rectangle()).accessibilityLabel("Abrir Calendario de Apple")
    }
    private var joinLabel: some View {
        Label("Unirse", systemImage: "video.fill")
            .font(.system(size: 11, weight: .semibold)).padding(.horizontal, 9).padding(.vertical, 8)
            .background(Color.blue, in: Capsule()).foregroundStyle(.white)
            .contentShape(Capsule())
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
