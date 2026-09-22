import XCTest
@testable import PaletaCore

final class FuzzyMatcherTests: XCTestCase {
    func testMatchesInitialsAndIgnoresDiacritics() {
        XCTAssertNotNil(FuzzyMatcher.score(query: "gcp", candidate: "Guardar como PDF"))
        XCTAssertNotNil(FuzzyMatcher.score(query: "pagina", candidate: "Página"))
    }

    func testRejectsCharactersInWrongOrder() {
        XCTAssertNil(FuzzyMatcher.score(query: "xyz", candidate: "Exportar"))
    }

    func testRankingPrefersConsecutiveMatch() {
        let commands = [
            MenuCommand(id: "1", title: "Cerrar ventana", path: ["Archivo"], shortcut: ""),
            MenuCommand(id: "2", title: "Copiar", path: ["Edición"], shortcut: "⌘C")
        ]
        let ranked = FuzzyMatcher.ranked(commands, query: "cop") { $0.searchableText }
        XCTAssertEqual(ranked.first?.title, "Copiar")
    }

    func testHistoryComesFirstWithoutAQuery() {
        let commands = sampleCommands
        let now = Date(timeIntervalSince1970: 10_000)
        let ranked = CommandRanker.ranked(
            commands,
            query: "",
            now: now,
            usage: ["2": CommandUsage(count: 1, lastUsed: now)],
            id: \.id,
            text: \.searchableText
        )
        XCTAssertEqual(ranked.map(\.id), ["2", "1"])
    }

    func testHistoryBoostsOnlyCommandsMatchingTheQuery() {
        let commands = [
            MenuCommand(id: "1", title: "Copiar estilo", path: ["Formato"], shortcut: ""),
            MenuCommand(id: "2", title: "Copiar", path: ["Edición"], shortcut: "⌘C"),
            MenuCommand(id: "3", title: "Exportar", path: ["Archivo"], shortcut: "")
        ]
        let now = Date(timeIntervalSince1970: 10_000)
        let ranked = CommandRanker.ranked(
            commands,
            query: "copi",
            now: now,
            usage: [
                "1": CommandUsage(count: 1, lastUsed: now.addingTimeInterval(-60)),
                "3": CommandUsage(count: 100, lastUsed: now)
            ],
            id: \.id,
            text: \.searchableText
        )
        XCTAssertEqual(ranked.map(\.id), ["1", "2"])
    }

    private var sampleCommands: [MenuCommand] {
        [
            MenuCommand(id: "1", title: "Cerrar ventana", path: ["Archivo"], shortcut: ""),
            MenuCommand(id: "2", title: "Copiar", path: ["Edición"], shortcut: "⌘C")
        ]
    }
}
