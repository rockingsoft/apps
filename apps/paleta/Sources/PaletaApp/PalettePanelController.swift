import AppKit
import PaletaCore

@MainActor
final class PalettePanelController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    private let service: AccessibilityMenuService
    private let history: CommandHistory
    private let searchField = NSSearchField()
    private let tableView = NSTableView()
    private let statusLabel = NSTextField(labelWithString: "")
    private var commands: [AccessibleCommand] = []
    private var filtered: [AccessibleCommand] = []
    private var sourceApplication: NSRunningApplication?

    init(service: AccessibilityMenuService, history: CommandHistory) {
        self.service = service
        self.history = history
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 430),
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        super.init(window: panel)
        configureContent()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func toggle() {
        if window?.isVisible == true {
            dismiss()
            return
        }
        guard service.requestPermission() else {
            show(message: "Permití Accesibilidad para Paleta en Configuración del Sistema")
            return
        }
        sourceApplication = NSWorkspace.shared.frontmostApplication
        guard let sourceApplication, sourceApplication.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
        commands = service.commands(for: sourceApplication)
        filtered = rankedCommands(query: "")
        searchField.stringValue = ""
        statusLabel.stringValue = commands.isEmpty ? "No se encontraron comandos" : sourceApplication.localizedName ?? ""
        tableView.reloadData()
        selectFirst()
        showWindow(nil)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(searchField)
    }

    func numberOfRows(in tableView: NSTableView) -> Int { filtered.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard filtered.indices.contains(row) else { return nil }
        let item = filtered[row].command
        let cell = NSTableCellView()
        let title = NSTextField(labelWithString: item.title)
        title.font = .systemFont(ofSize: 14, weight: .medium)
        let context = NSTextField(labelWithString: item.context)
        context.font = .systemFont(ofSize: 11)
        context.textColor = .secondaryLabelColor
        context.lineBreakMode = .byTruncatingMiddle
        let shortcut = NSTextField(labelWithString: item.shortcut)
        shortcut.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        shortcut.textColor = .secondaryLabelColor
        shortcut.alignment = .right
        [title, context, shortcut].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; cell.addSubview($0) }
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 12),
            title.topAnchor.constraint(equalTo: cell.topAnchor, constant: 7),
            context.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            context.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 2),
            context.trailingAnchor.constraint(lessThanOrEqualTo: shortcut.leadingAnchor, constant: -10),
            shortcut.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -12),
            shortcut.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
        ])
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {}

    func controlTextDidChange(_ obj: Notification) {
        filtered = rankedCommands(query: searchField.stringValue)
        tableView.reloadData()
        selectFirst()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.moveUp(_:)): moveSelection(by: -1)
        case #selector(NSResponder.moveDown(_:)): moveSelection(by: 1)
        case #selector(NSResponder.insertNewline(_:)): executeSelection()
        case #selector(NSResponder.cancelOperation(_:)): dismiss()
        default: return false
        }
        return true
    }

    private func configureContent() {
        guard let content = window?.contentView else { return }
        searchField.placeholderString = "Buscar un comando…"
        searchField.font = .systemFont(ofSize: 20)
        searchField.focusRingType = .none
        searchField.delegate = self

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("command"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = 48
        tableView.intercellSpacing = NSSize(width: 0, height: 2)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.doubleAction = #selector(executeSelection)

        let scroll = NSScrollView()
        scroll.documentView = tableView
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.font = .systemFont(ofSize: 11)

        [searchField, scroll, statusLabel].forEach { $0.translatesAutoresizingMaskIntoConstraints = false; content.addSubview($0) }
        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
            searchField.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            searchField.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            searchField.heightAnchor.constraint(equalToConstant: 36),
            scroll.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 12),
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 8),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -8),
            statusLabel.topAnchor.constraint(equalTo: scroll.bottomAnchor, constant: 7),
            statusLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 20),
            statusLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -20),
            statusLabel.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -9),
            statusLabel.heightAnchor.constraint(equalToConstant: 16)
        ])
    }

    private func show(message: String) {
        commands = []
        filtered = []
        statusLabel.stringValue = message
        tableView.reloadData()
        showWindow(nil)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }

    private func selectFirst() {
        guard !filtered.isEmpty else { return }
        tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        tableView.scrollRowToVisible(0)
    }

    private func moveSelection(by delta: Int) {
        guard !filtered.isEmpty else { return }
        let current = max(0, tableView.selectedRow)
        let next = min(filtered.count - 1, max(0, current + delta))
        tableView.selectRowIndexes(IndexSet(integer: next), byExtendingSelection: false)
        tableView.scrollRowToVisible(next)
    }

    @objc private func executeSelection() {
        guard filtered.indices.contains(tableView.selectedRow) else { return }
        let selected = filtered[tableView.selectedRow]
        history.record(historyKey(for: selected))
        dismiss()
        sourceApplication?.activate(options: [])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [service] in service.perform(selected) }
    }

    private func dismiss() {
        window?.orderOut(nil)
    }

    private func rankedCommands(query: String) -> [AccessibleCommand] {
        CommandRanker.ranked(
            commands,
            query: query,
            usage: history.usage,
            id: historyKey(for:),
            text: { $0.command.searchableText }
        )
    }

    private func historyKey(for command: AccessibleCommand) -> String {
        let applicationID = sourceApplication?.bundleIdentifier ?? sourceApplication?.localizedName ?? "unknown"
        return applicationID + "\u{1E}" + command.command.id
    }
}
