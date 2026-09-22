import Foundation

public struct MenuCommand: Identifiable, Equatable {
    public let id: String
    public let title: String
    public let path: [String]
    public let shortcut: String

    public init(id: String, title: String, path: [String], shortcut: String) {
        self.id = id
        self.title = title
        self.path = path
        self.shortcut = shortcut
    }

    public var searchableText: String { (path + [title]).joined(separator: " ") }
    public var context: String { path.joined(separator: " › ") }
}
