import Foundation

public enum FuzzyMatcher {
    public static func score(query: String, candidate: String) -> Int? {
        let needle = normalized(query)
        let haystack = normalized(candidate)
        guard !needle.isEmpty else { return 0 }

        var score = 0
        var searchIndex = haystack.startIndex
        var previousMatch: String.Index?

        for character in needle {
            guard let match = haystack[searchIndex...].firstIndex(of: character) else { return nil }
            let distance = haystack.distance(from: searchIndex, to: match)
            score += max(1, 12 - distance)

            if let previousMatch, haystack.index(after: previousMatch) == match {
                score += 14
            }
            let previousCharacterIsWord = match == haystack.startIndex
                ? false
                : haystack[haystack.index(before: match)].isLetter || haystack[haystack.index(before: match)].isNumber
            if match == haystack.startIndex || !previousCharacterIsWord {
                score += 18
            }

            previousMatch = match
            searchIndex = haystack.index(after: match)
        }
        return score - haystack.count / 8
    }

    public static func ranked<T>(_ values: [T], query: String, text: (T) -> String) -> [T] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return values }
        return values.compactMap { value -> (T, Int)? in
            score(query: query, candidate: text(value)).map { (value, $0) }
        }
        .sorted { lhs, rhs in lhs.1 == rhs.1 ? text(lhs.0) < text(rhs.0) : lhs.1 > rhs.1 }
        .map(\.0)
    }

    private static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}
