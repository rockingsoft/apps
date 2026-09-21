import SwiftUI
import EventKit

struct ContentView: View {
    @EnvironmentObject var model: AgendaModel
    @Environment(\.scenePhase) private var phase
    @State private var search = ""
    @State private var showSearch = false
    @State private var settings = false
    private var filtered: [AgendaItem] {
        model.visible.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || $0.calendarName.localizedCaseInsensitiveContains(search) }
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Hoy") { model.today() }.font(.system(size: 11, weight: .medium))
                Spacer()
                if model.loading { ProgressView().controlSize(.mini) }
                Button { showSearch.toggle() } label: { Image(systemName: "magnifyingglass") }.accessibilityLabel("Buscar")
            }.buttonStyle(.plain).foregroundStyle(.gray).padding(.horizontal, 18).padding(.top, 14).padding(.bottom, 3).background(Color(white: 0.965))
            MonthView(month: model.month, selected: model.selected, items: model.visible, select: { model.selected = $0 }, move: model.move)
            if showSearch {
                TextField("Buscar eventos y recordatorios", text: $search).textFieldStyle(.roundedBorder).padding(10)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 17) {
                    if !model.calendarAllowed || !model.remindersAllowed { permissions }
                    if let error = model.error {
                        Text(error).font(.caption).foregroundStyle(.orange).textSelection(.enabled)
                    }
                    let overdue = filtered.filter { $0.reminder && $0.start != nil && $0.start! < Calendar.current.startOfDay(for: Date()) }
                    if !overdue.isEmpty {
                        DisclosureGroup("Vencidos (\(overdue.count))") {
                            VStack(alignment: .leading, spacing: 9) {
                                ForEach(overdue) { item in AgendaRow(item: item, complete: { model.complete(item) }) }
                            }.padding(.top, 8)
                        }.font(.system(size: 11)).tint(.gray)
                    }
                    ForEach(0..<14) { offset in
                        let day = Calendar.current.date(byAdding: .day, value: offset, to: model.selected)!
                        let entries = filtered.filter { $0.occurs(on: day) && !(overdue.contains($0)) }
                        if !entries.isEmpty || offset == 0 {
                            VStack(alignment: .leading, spacing: 9) {
                                DayHeading(date: day)
                                if entries.isEmpty { Text("Sin eventos ni recordatorios").font(.system(size: 12)).foregroundStyle(.gray) }
                                ForEach(entries) { item in AgendaRow(item: item, complete: { model.complete(item) }) }
                            }
                        }
                    }
                    let undated = filtered.filter { $0.start == nil }
                    if !undated.isEmpty { specialSection("SIN FECHA", items: undated) }
                }.padding(16)
            }
            HStack {
                Menu {
                    if model.sources.isEmpty { Text("No hay calendarios disponibles") }
                    ForEach(model.sources) { source in
                        Button { model.toggle(source) } label: {
                            Label(source.title, systemImage: model.hidden.contains(source.id) ? "circle" : "checkmark.circle.fill")
                        }
                    }
                } label: { Label(model.hidden.isEmpty ? "Todos los calendarios" : "Calendarios filtrados", systemImage: "line.3.horizontal.decrease") }
                Spacer()
                Button { settings = true } label: { Image(systemName: "gearshape") }.accessibilityLabel("Ajustes")
            }.font(.system(size: 12)).buttonStyle(.plain).padding(14).background(Color(white: 0.16))
        }
        .foregroundStyle(.white).background(Color(white: 0.125))
        .task { await model.refresh() }
        .task(id: model.month) { await model.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)) { _ in Task { await model.refresh() } }
        .onChange(of: phase) { _, value in if value == .active { Task { await model.refresh() } } }
        .sheet(isPresented: $settings) {
            VStack(alignment: .leading, spacing: 18) {
                Text("Calendario y recordatorios").font(.title2.bold())
                Text("Los datos se leen de las cuentas configuradas en este dispositivo. Elegí las fuentes en el menú de calendarios.")
                permissions
                Text("Si denegaste un permiso, habilitalo en Ajustes del sistema → Privacidad y seguridad. Los widgets se actualizan según la frecuencia permitida por Apple.").font(.caption).foregroundStyle(.secondary)
                Button("Actualizar ahora") { Task { await model.refresh() } }
                Button("Listo") { settings = false }.keyboardShortcut(.defaultAction)
            }.padding(24).frame(minWidth: 290, idealWidth: 360).preferredColorScheme(.dark)
        }
    }
    private var permissions: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !model.calendarAllowed {
                Button("Permitir acceso a Calendario") { Task { await model.request(false) } }
            }
            if !model.remindersAllowed {
                Button("Permitir acceso a Recordatorios") { Task { await model.request(true) } }
            }
        }.buttonStyle(.bordered).font(.caption)
    }
    private func specialSection(_ title: String, items: [AgendaItem]) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title).font(.system(size: 10, weight: .bold)).foregroundStyle(.gray)
            ForEach(items) { item in AgendaRow(item: item, complete: { model.complete(item) }) }
        }
    }
}
