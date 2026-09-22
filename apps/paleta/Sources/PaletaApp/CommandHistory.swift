import Foundation
import PaletaCore

@MainActor
final class CommandHistory {
    private let defaults: UserDefaults
    private let storageKey = "commandUsage.v1"
    private let maximumEntries = 500
    private(set) var usage: [String: CommandUsage]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([String: CommandUsage].self, from: data) {
            usage = decoded
        } else {
            usage = [:]
        }
    }

    func record(_ id: String, at date: Date = Date()) {
        let previous = usage[id]
        usage[id] = CommandUsage(count: (previous?.count ?? 0) + 1, lastUsed: date)
        pruneIfNeeded()
        if let data = try? JSONEncoder().encode(usage) {
            defaults.set(data, forKey: storageKey)
        }
    }

    private func pruneIfNeeded() {
        guard usage.count > maximumEntries else { return }
        let retained = usage.sorted { $0.value.lastUsed > $1.value.lastUsed }.prefix(maximumEntries)
        usage = Dictionary(uniqueKeysWithValues: retained.map { ($0.key, $0.value) })
    }
}
