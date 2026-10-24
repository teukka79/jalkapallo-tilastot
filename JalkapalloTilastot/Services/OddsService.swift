import Foundation

/// Yhden ottelun kertoimet (desimaali), keskiarvo vedonvälittäjien kesken.
struct MatchOdds: Codable, Hashable {
    let homeName: String
    let awayName: String
    let commence: Date
    var home: Double?
    var draw: Double?
    var away: Double?
    /// Yli/alle-raja (2.5) ja sen kertoimet
    var line: Double = 2.5
    var over: Double?
    var under: Double?
    /// Montako vedonvälittäjää keskiarvossa on mukana
    var bookmakers: Int = 0

    var hasMatchOdds: Bool { home != nil && draw != nil && away != nil }
}

/// Levylle tallennettu sarjan kerroinvälimuisti.
struct StoredOdds: Codable {
    var fetched: Date
    var entries: [MatchOdds]
}

enum OddsCache {
    /// Kertoimet pidetään tuoreina näin kauan; ilmainen taso on vain ~500 pyyntöä kuukaudessa.
    static let maxAge: TimeInterval = 6 * 3600

    private static var fileURL: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let folder = base.appendingPathComponent("Jalkapallotilastot", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("odds.json")
    }

    static func load() -> [String: StoredOdds] {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return [:] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([String: StoredOdds].self, from: data)) ?? [:]
    }

    static func save(_ value: [String: StoredOdds]) {
        guard let url = fileURL else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(value) { try? data.write(to: url, options: .atomic) }
    }
}

/// The Odds API (the-odds-api.com) v4. Yksi kysely hakee sarjan h2h- ja totals-markkinat (2 krediittiä).
struct OddsService {
    let apiKey: String

    enum ServiceError: LocalizedError {
        case badStatus(Int)
        case invalidKey

        var errorDescription: String? {
            switch self {
            case .badStatus(let code): return "The Odds API vastasi virheellä \(code)"
            case .invalidKey: return "The Odds API: avain ei kelpaa tai kuukausikiintiö on käytetty"
            }
        }
    }

    struct Result {
        let entries: [MatchOdds]
        /// Jäljellä olevat krediitit (x-requests-remaining)
        let remaining: Int?
    }

    private struct EventDTO: Decodable {
        struct Bookmaker: Decodable {
            struct Market: Decodable {
                struct Outcome: Decodable {
                    let name: String
                    let price: Double
                    let point: Double?
                }
                let key: String
                let outcomes: [Outcome]
            }
            let markets: [Market]
        }
        let commence_time: String
        let home_team: String
        let away_team: String
        let bookmakers: [Bookmaker]
    }

    func fetch(league: League) async throws -> Result {
        var components = URLComponents(string: "https://api.the-odds-api.com/v4/sports/\(league.oddsSportKey)/odds")!
        components.queryItems = [
            URLQueryItem(name: "apiKey", value: apiKey),
            URLQueryItem(name: "regions", value: "eu"),
            URLQueryItem(name: "markets", value: "h2h,totals"),
            URLQueryItem(name: "oddsFormat", value: "decimal"),
            URLQueryItem(name: "dateFormat", value: "iso")
        ]
        let (data, response) = try await URLSession.shared.data(from: components.url!)
        let http = response as? HTTPURLResponse
        let remaining = http?.value(forHTTPHeaderField: "x-requests-remaining").flatMap { Int($0) }
        switch http?.statusCode ?? 0 {
        case 200: break
        case 401, 429: throw ServiceError.invalidKey
        case 404, 422: return Result(entries: [], remaining: remaining)   // sarjaa ei tarjolla juuri nyt
        case let code: throw ServiceError.badStatus(code)
        }
        let events = try JSONDecoder().decode([EventDTO].self, from: data)
        let iso = ISO8601DateFormatter()
        let line = 2.5

        let entries = events.compactMap { event -> MatchOdds? in
            guard let date = iso.date(from: event.commence_time) else { return nil }
            var homePrices: [Double] = [], drawPrices: [Double] = [], awayPrices: [Double] = []
            var overPrices: [Double] = [], underPrices: [Double] = []
            for bookmaker in event.bookmakers {
                for market in bookmaker.markets {
                    switch market.key {
                    case "h2h":
                        for outcome in market.outcomes {
                            if outcome.name == event.home_team { homePrices.append(outcome.price) }
                            else if outcome.name == event.away_team { awayPrices.append(outcome.price) }
                            else if outcome.name == "Draw" { drawPrices.append(outcome.price) }
                        }
                    case "totals":
                        for outcome in market.outcomes where outcome.point == line {
                            if outcome.name == "Over" { overPrices.append(outcome.price) }
                            else if outcome.name == "Under" { underPrices.append(outcome.price) }
                        }
                    default: break
                    }
                }
            }
            func mean(_ values: [Double]) -> Double? {
                values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
            }
            return MatchOdds(homeName: event.home_team, awayName: event.away_team, commence: date,
                             home: mean(homePrices), draw: mean(drawPrices), away: mean(awayPrices),
                             line: line, over: mean(overPrices), under: mean(underPrices),
                             bookmakers: event.bookmakers.count)
        }
        return Result(entries: entries, remaining: remaining)
    }
}
