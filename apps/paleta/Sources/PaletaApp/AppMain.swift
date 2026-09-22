import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var hotKey: GlobalHotKey?
    private var palette: PalettePanelController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let palette = PalettePanelController(service: AccessibilityMenuService())
        self.palette = palette
        hotKey = GlobalHotKey { DispatchQueue.main.async { palette.toggle() } }
    }
}

@main
enum PaletaMain {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
