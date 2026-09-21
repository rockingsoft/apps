import SwiftUI

struct MonthView: View {
    var month: Date
    var selected: Date
    var items: [AgendaItem]
    var compact = false
    var select: ((Date) -> Void)?
    var move: ((Int) -> Void)?
    private let calendar = Calendar.current
    var body: some View {
        VStack(spacing: compact ? 5 : 12) {
            HStack(spacing: 5) {
                Text(month.formatted(.dateTime.month(.wide)).capitalized).fontWeight(.bold)
                Text(month.formatted(.dateTime.year())).foregroundStyle(.red)
                Spacer(minLength: 0)
                if let move {
                    Button { move(-1) } label: { Image(systemName: "chevron.left").font(.system(size: 14, weight: .semibold)).frame(width: 24, height: 28) }.accessibilityLabel("Mes anterior")
                    Button { move(1) } label: { Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold)).frame(width: 24, height: 28) }.accessibilityLabel("Mes siguiente")
                }
            }
            .font(.system(size: compact ? 18 : 27)).lineLimit(1).minimumScaleFactor(0.75).buttonStyle(.plain)
            HStack(spacing: 0) {
                ForEach(0..<7) { offset in
                    let index = (calendar.firstWeekday - 1 + offset) % 7
                    Text(calendar.shortStandaloneWeekdaySymbols[index].uppercased())
                        .font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 0) {
                ForEach(AgendaDates.monthDays(month), id: \.self) { day in
                    if let select {
                        Button { select(day) } label: {
                            cell(day)
                                .padding(.vertical, compact ? 0 : 2)
                                .contentShape(Rectangle())
                        }.buttonStyle(.plain)
                            .accessibilityLabel(day.formatted(date: .complete, time: .omitted))
                    } else { cell(day) }
                }
            }
        }
        .padding(compact ? 8 : 16)
        .foregroundStyle(Color(white: 0.12)).background(Color(white: 0.965))
        .environment(\.colorScheme, .light)
    }
    private func cell(_ day: Date) -> some View {
        let today = calendar.isDateInToday(day)
        let active = calendar.isDate(day, inSameDayAs: selected)
        let inMonth = calendar.isDate(day, equalTo: month, toGranularity: .month)
        let entries = items.filter { $0.occurs(on: day) }
        return VStack(spacing: 1) {
            Text(day.formatted(.dateTime.day())).font(.system(size: compact ? 11 : 12, weight: today ? .bold : .regular))
                .foregroundStyle(today ? .white : inMonth ? Color(white: 0.12) : .gray)
                .frame(width: compact ? 19 : 23, height: compact ? 13 : 21)
                .background { if today { Circle().fill(.cyan) } }
            HStack(spacing: 2) {
                ForEach(Array(entries.prefix(4).enumerated()), id: \.offset) { _, item in Circle().fill(item.color).frame(width: 3, height: 3) }
            }.frame(height: compact ? 2 : 3)
        }
        .frame(maxWidth: .infinity).padding(.vertical, compact ? 0 : 1)
        .background(active && !today ? Color.black.opacity(0.07) : .clear, in: RoundedRectangle(cornerRadius: 4))
    }
}

struct AgendaRow: View {
    let item: AgendaItem
    var complete: (() -> Void)?
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if item.reminder, let complete {
                Button(action: complete) { Image(systemName: "circle").foregroundStyle(item.color).font(.system(size: 15)) }
                    .buttonStyle(.plain).accessibilityLabel("Completar \(item.title)")
            } else {
                Image(systemName: item.reminder ? "circle" : "circle.fill").font(.system(size: 10)).foregroundStyle(item.color).padding(.top, 3)
            }
            VStack(alignment: .leading, spacing: 2) {
                if !item.allDay, let start = item.start {
                    HStack(spacing: 3) {
                        Text(start, style: .time)
                        if let end = item.end { Text("–"); Text(end, style: .time) }
                    }.font(.system(size: 10, weight: .medium)).foregroundStyle(.gray)
                }
                Text(item.title).font(.system(size: 12, weight: .medium)).lineLimit(2)
                    .padding(.horizontal, item.allDay && !item.reminder ? 5 : 0)
                    .padding(.vertical, item.allDay && !item.reminder ? 2 : 0)
                    .background(item.allDay && !item.reminder ? item.color.opacity(0.65) : .clear, in: RoundedRectangle(cornerRadius: 4))
            }
            Spacer(minLength: 0)
        }.foregroundStyle(.white)
    }
}

struct DayHeading: View {
    let date: Date
    var body: some View {
        HStack(spacing: 3) {
            Text(AgendaDates.title(date)).fontWeight(.bold)
            Text(date.formatted(.dateTime.day().month(.twoDigits).year()))
            Spacer()
        }.font(.system(size: 10)).foregroundStyle(Calendar.current.isDateInToday(date) ? .cyan : .gray)
    }
}
