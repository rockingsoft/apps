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
}
