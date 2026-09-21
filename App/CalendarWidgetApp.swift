import SwiftUI

@main
struct CalendarWidgetApp: App {
    @StateObject private var model = AgendaModel()
    var body: some Scene {
        #if os(macOS)
        WindowGroup {
            ContentView().environmentObject(model)
                .onOpenURL { _ in model.today(); NSApp.activate(ignoringOtherApps: true) }
                .frame(minWidth: 320, idealWidth: 340, maxWidth: 500, minHeight: 540, idealHeight: 820)
        }
        .defaultSize(width: 340, height: 820)
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        MenuBarExtra("Agenda", systemImage: "calendar") {
            ContentView().environmentObject(model).frame(width: 340, height: 820)
        }.menuBarExtraStyle(.window)
        #else
        WindowGroup {
            ContentView().environmentObject(model)
                .frame(maxWidth: 520).frame(maxWidth: .infinity).background(Color(white: 0.125))
                .onOpenURL { _ in model.today() }
        }
        #endif
    }
}
