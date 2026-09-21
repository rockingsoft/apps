import SwiftUI
#if os(macOS)
import AppKit

final class AgendaAppDelegate: NSObject, NSApplicationDelegate {
    @MainActor let model = AgendaModel()

    func application(_ application: NSApplication, open urls: [URL]) {
        Task { @MainActor in urls.forEach(model.open) }
    }
}
#endif

@main
struct CalendarWidgetApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(AgendaAppDelegate.self) private var appDelegate
    private var model: AgendaModel { appDelegate.model }
    #else
    @StateObject private var model = AgendaModel()
    #endif
    var body: some Scene {
        #if os(macOS)
        MenuBarExtra("Agenda", systemImage: "calendar") {
            ContentView().environmentObject(model)
                .frame(width: 340, height: 820)
        }.menuBarExtraStyle(.window)
        #else
        WindowGroup {
            ContentView().environmentObject(model)
                .frame(maxWidth: 520).frame(maxWidth: .infinity).background(Color(white: 0.125))
                .onOpenURL { url in model.open(url) }
        }
        #endif
    }
}
