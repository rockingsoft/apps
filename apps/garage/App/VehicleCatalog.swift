import Foundation

struct CatalogOption: Codable, Identifiable, Hashable {
    let id: Int
    let name: String

    var embeddedYear: Int? {
        guard let last = name.split(separator: " ").last,
              last.count == 4,
              let year = Int(last),
              (1950...Calendar.current.component(.year, from: .now) + 1).contains(year) else { return nil }
        return year
    }

    var nameWithoutYear: String {
        guard embeddedYear != nil, let index = name.lastIndex(of: " ") else { return name }
        return String(name[..<index])
    }
}

enum VehicleCatalog {
    private struct Page: Decodable {
        struct Links: Decodable { let next: String? }
        let data: [CatalogOption]
        let links: Links?
    }
    private struct CacheEntry: Codable {
        let savedAt: Date
        let options: [CatalogOption]
    }
    private struct ValuationPage: Decodable {
        struct Valuation: Decodable { let year: Int }
        let data: [Valuation]
    }
    private struct YearCacheEntry: Codable {
        let savedAt: Date
        let years: [Int]
    }
    private static let base = URL(string: "https://argautos.com/api/v1/")!
    private static let maxAge: TimeInterval = 7 * 24 * 60 * 60

    static func brands() async throws -> [CatalogOption] { try await fetch(path: "brands") }
    static func models(brandID: Int) async throws -> [CatalogOption] { try await fetch(path: "brands/\(brandID)/models") }
    static func versions(modelID: Int) async throws -> [CatalogOption] { try await fetch(path: "models/\(modelID)/versions") }

    static func years(versionID: Int) async throws -> [Int] {
        let key = "garage.catalog.years.\(versionID)"
        let cached = UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(YearCacheEntry.self, from: $0) }
        if let cached, Date().timeIntervalSince(cached.savedAt) < maxAge { return cached.years }
        do {
            let url = base.appending(path: "versions/\(versionID)/valuations")
            var request = URLRequest(url: url)
            request.timeoutInterval = 10
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            var (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode == 429,
               let seconds = http.value(forHTTPHeaderField: "Retry-After").flatMap(Int.init),
               (1...60).contains(seconds) {
                try await Task.sleep(for: .seconds(seconds))
                (data, response) = try await URLSession.shared.data(for: request)
            }
            guard let response = response as? HTTPURLResponse, (200...299).contains(response.statusCode) else { throw CatalogError.unavailable }
            let years = Array(Set(try JSONDecoder().decode(ValuationPage.self, from: data).data.map(\.year))).sorted(by: >)
            guard !years.isEmpty else { throw CatalogError.invalidResponse }
            if let data = try? JSONEncoder().encode(YearCacheEntry(savedAt: .now, years: years)) { UserDefaults.standard.set(data, forKey: key) }
            return years
        } catch {
            if let cached { return cached.years }
            throw error
        }
    }

    private static func fetch(path: String) async throws -> [CatalogOption] {
        let key = "garage.catalog.\(path)"
        let cached = UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(CacheEntry.self, from: $0) }
        if let cached, Date().timeIntervalSince(cached.savedAt) < maxAge { return cached.options }
        do {
            var result: [CatalogOption] = []
            var next: URL? = base.appending(path: path)
            var visited = Set<URL>()
            while let url = next, visited.count < 10 {
                guard url.scheme == "https", url.host == base.host, visited.insert(url).inserted else { throw CatalogError.invalidResponse }
                var request = URLRequest(url: url)
                request.timeoutInterval = 10
                request.setValue("application/json", forHTTPHeaderField: "Accept")
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let response = response as? HTTPURLResponse, (200...299).contains(response.statusCode) else { throw CatalogError.unavailable }
                let page = try JSONDecoder().decode(Page.self, from: data)
                result.append(contentsOf: page.data)
                next = page.links?.next.flatMap { URL(string: $0, relativeTo: base)?.absoluteURL }
            }
            guard !result.isEmpty, next == nil else { throw CatalogError.invalidResponse }
            let options = Array(Dictionary(grouping: result, by: \.id).values.compactMap(\.first)).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            if let data = try? JSONEncoder().encode(CacheEntry(savedAt: .now, options: options)) { UserDefaults.standard.set(data, forKey: key) }
            return options
        } catch {
            if let cached { return cached.options }
            throw error
        }
    }
}

enum CatalogError: LocalizedError {
    case unavailable, invalidResponse
    var errorDescription: String? { "No se pudo cargar ArgAutos. Intentá de nuevo más tarde." }
}
