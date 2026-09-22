import AppKit
import ApplicationServices
import PaletaCore

struct AccessibleCommand {
    let command: MenuCommand
    let element: AXUIElement
}

@MainActor
final class AccessibilityMenuService {
    func requestPermission() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    func commands(for application: NSRunningApplication) -> [AccessibleCommand] {
        let appElement = AXUIElementCreateApplication(application.processIdentifier)
        guard let menuBar: AXUIElement = value(of: kAXMenuBarAttribute, from: appElement) else { return [] }
        return children(of: menuBar).flatMap { collect(from: $0, path: []) }
    }

    func perform(_ command: AccessibleCommand) {
        AXUIElementPerformAction(command.element, kAXPressAction as CFString)
    }

    private func collect(from element: AXUIElement, path: [String]) -> [AccessibleCommand] {
        let role: String = value(of: kAXRoleAttribute, from: element) ?? ""
        let title: String = value(of: kAXTitleAttribute, from: element) ?? ""
        let descendants = children(of: element)

        if role == kAXMenuItemRole as String, descendants.isEmpty, !title.isEmpty {
            let enabled: Bool = value(of: kAXEnabledAttribute, from: element) ?? true
            guard enabled, title != "-" else { return [] }
            let id = (path + [title]).joined(separator: "\u{1F}")
            return [AccessibleCommand(
                command: MenuCommand(id: id, title: title, path: path, shortcut: shortcut(for: element)),
                element: element
            )]
        }

        let nextPath = title.isEmpty ? path : path + [title]
        return descendants.flatMap { collect(from: $0, path: nextPath) }
    }

    private func children(of element: AXUIElement) -> [AXUIElement] {
        value(of: kAXChildrenAttribute, from: element) ?? []
    }

    private func value<T>(of attribute: String, from element: AXUIElement) -> T? {
        var raw: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &raw) == .success else { return nil }
        return raw as? T
    }

    private func shortcut(for element: AXUIElement) -> String {
        let key: String = value(of: kAXMenuItemCmdCharAttribute, from: element) ?? ""
        guard !key.isEmpty else { return "" }
        let modifiers: Int = value(of: kAXMenuItemCmdModifiersAttribute, from: element) ?? 0
        var result = ""
        if modifiers & (1 << 2) != 0 { result += "⌃" }
        if modifiers & (1 << 1) != 0 { result += "⌥" }
        if modifiers & (1 << 0) != 0 { result += "⇧" }
        if modifiers & (1 << 3) == 0 { result += "⌘" }
        return result + key.uppercased()
    }
}
