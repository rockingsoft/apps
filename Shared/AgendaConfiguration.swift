import AppIntents
import Foundation
import WidgetKit
import CryptoKit

struct WidgetCalendar: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Calendario")
    static var defaultQuery = WidgetCalendarQuery()
    var id: String
    var name: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}
struct WidgetCalendarQuery: EntityStringQuery {
    func entities(for identifiers: [String]) async throws -> [WidgetCalendar] {
        available.filter { identifiers.contains($0.id) }
    }
    func suggestedEntities() async throws -> [WidgetCalendar] { available }
    func entities(matching string: String) async throws -> [WidgetCalendar] {
        available.filter { $0.name.localizedCaseInsensitiveContains(string) }
    }
    private var available: [WidgetCalendar] {
        let snapshot = AgendaCache.read()
        if let sources = snapshot.sources {
            return sources.filter { !$0.reminder }.map { .init(id: $0.id, name: $0.title) }
        }
        var seen: Set<String> = []
        return snapshot.items.filter { !$0.reminder && seen.insert($0.calendarID).inserted }
            .map { .init(id: $0.calendarID, name: $0.calendarName) }
    }
}
struct AgendaConfiguration: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Configurar agenda"
    static var description = IntentDescription("Elegí los calendarios y el contenido de este widget.")
    @Parameter(title: "Todos los calendarios", default: true) var allCalendars: Bool
    @Parameter(title: "Calendarios") var calendars: [WidgetCalendar]?
    @Parameter(title: "Mostrar tareas", default: true) var showTasks: Bool
    @Parameter(title: "Mostrar eventos de todo el día", default: true) var showAllDay: Bool
    @Parameter(title: "Mostrar mes", default: true) var showMonth: Bool
    static var parameterSummary: some ParameterSummary {
        When(\.$allCalendars, .equalTo, false) {
            Summary {
                \.$allCalendars
                \.$calendars
                \.$showTasks
                \.$showAllDay
                \.$showMonth
            }
        } otherwise: {
            Summary {
                \.$allCalendars
                \.$showTasks
                \.$showAllDay
                \.$showMonth
            }
        }
    }
}


struct SelectWidgetDay: AppIntent {
    static var title: LocalizedStringResource = "Seleccionar día"
    static var openAppWhenRun = false
    @Parameter(title: "Fecha") var timestamp: Double
    @Parameter(title: "Widget") var selectionKey: String
    init() {}
    init(date: Date?, key: String) {
        timestamp = date?.timeIntervalSince1970 ?? 0
        selectionKey = key
    }
    func perform() async throws -> some IntentResult {
        if timestamp == 0 { AgendaCache.defaults.removeObject(forKey: selectionKey) }
        else { AgendaCache.defaults.set(timestamp, forKey: selectionKey) }
        WidgetCenter.shared.reloadTimelines(ofKind: "AgendaWidget")
        return .result()
    }
}

extension AgendaConfiguration {
    var selectionKey: String {
        let ids = (calendars ?? []).map(\.id).sorted().joined(separator: "|")
        let value = "\(allCalendars)|\(ids)|\(showTasks)|\(showAllDay)|\(showMonth)"
        return "selectedDay." + SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    func selectedDate(now: Date) -> Date {
        let timestamp = AgendaCache.defaults.double(forKey: selectionKey)
        return timestamp == 0 ? now : Date(timeIntervalSince1970: timestamp)
    }
}
