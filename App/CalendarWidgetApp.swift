import SwiftUI
#if os(macOS)
import AppKit

final class AgendaAppDelegate: NSObject, NSApplicationDelegate {
    private var pendingURLs: [URL] = []
    var openURL: ((URL) -> Void)? {
        didSet { drainPendingURLs() }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        pendingURLs.append(contentsOf: urls)
        drainPendingURLs()
    }

    private func drainPendingURLs() {
        guard let openURL else { return }
        let urls = pendingURLs
        pendingURLs.removeAll()
        urls.forEach(openURL)
    }
}
#endif

@main
struct CalendarWidgetApp: App {
    @StateObject private var model = AgendaModel()
    #if os(macOS)
    @NSApplicationDelegateAdaptor(AgendaAppDelegate.self) private var appDelegate
    #endif
    var body: some Scene {
        #if os(macOS)
        WindowGroup {
            ContentView().environmentObject(model)
                .onAppear { appDelegate.openURL = model.open }
                .onOpenURL(perform: model.open)
                .frame(minWidth: 320, idealWidth: 340, maxWidth: 500, minHeight: 540, idealHeight: 820)
        }
        .defaultSize(width: 340, height: 820)
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        MenuBarExtra("Agenda", systemImage: "calendar") {
            ContentView().environmentObject(model)
                .onAppear { appDelegate.openURL = model.open }
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
