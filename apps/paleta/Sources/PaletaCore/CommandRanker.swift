import Foundation

public struct CommandUsage: Codable, Equatable, Sendable {
    public var count: Int
    public var lastUsed: Date

    public init(count: Int, lastUsed: Date) {
        self.count = count
        self.lastUsed = lastUsed
    }
}

public enum CommandRanker {
    public static func ranked<T>(
        _ values: [T],
        query: String,
        now: Date = Date(),
        usage: [String: CommandUsage],
        id: (T) -> String,
        text: (T) -> String
    ) -> [T] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)

        return values.enumerated().compactMap { index, value -> RankedValue<T>? in
            let commandUsage = usage[id(value)]
            if trimmedQuery.isEmpty {
                return RankedValue(value: value, score: historyScore(commandUsage, now: now), originalIndex: index)
            }
            guard let fuzzyScore = FuzzyMatcher.score(query: trimmedQuery, candidate: text(value)) else { return nil }
            return RankedValue(
                value: value,
                score: fuzzyScore + historyScore(commandUsage, now: now),
                originalIndex: index
            )
        }
        .sorted { lhs, rhs in
            lhs.score == rhs.score ? lhs.originalIndex < rhs.originalIndex : lhs.score > rhs.score
        }
        .map(\.value)
    }

    private static func historyScore(_ usage: CommandUsage?, now: Date) -> Int {
        guard let usage else { return 0 }
        let ageInDays = max(0, now.timeIntervalSince(usage.lastUsed) / 86_400)
        let recency = max(0, 120 - Int(ageInDays * 4))
        return 200 + recency + min(usage.count, 50) * 4
    }

    private struct RankedValue<T> {
        let value: T
        let score: Int
        let originalIndex: Int
    }
}
