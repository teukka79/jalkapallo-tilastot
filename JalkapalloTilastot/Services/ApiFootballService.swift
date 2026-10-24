import Foundation

/// API-Football (api-sports.io, v3). Ilmainen tili: 100 kyselyä päivässä.
/// Yhden ottelun tilastot vaativat kaksi kyselyä: ottelun haku (fixtures) ja tilastot (fixtures/statistics).
/// Rajapinta ei anna puoliaikakohtaisia tilastoja eikä esim. huikeita paikkoja, joten vain saatavilla olevat rivit näytetään.
struct ApiFootballService {
    let apiKey: String
    private let base = URL(string: "https://v3.football.api-sports.io")!

    enum ServiceError: LocalizedError {
        case api(String)
        case noFixture
        case noStats
        case rateLimited
        case badStatus(Int)

        var errorDescription: String? {
            switch self {
            case .api(let message): return "API-Football: \(message)"
            case .noFixture: return "Ottelua ei löytynyt API-Footballista"
            case .noStats: return "API-Footballilla ei ole tilastoja tälle ottelulle"
            case .rateLimited: return "API-Footballin päiväraja täynnä, yritä myöhemmin"
            case .badStatus(let code): return "Palvelin vastasi virheellä \(code)"
            }
        }
    }

    /// football-data.org-koodi -> API-Footballin sarjatunnus
    static func leagueID(for code: String) -> Int? {
        League.from(code: code)?.apiFootballID
    }

    // MARK: DTO:t

    struct APIErrors: Decodable {
        let messages: [String]
        init(from decoder: Decoder) throws {
            // Rajapinta palauttaa tyhjänä [] ja virheissä {"avain": "viesti"}
            let container = try decoder.singleValueContainer()
            if let dict = try? container.decode([String: String].self) {
                messages = Array(dict.values)
            } else {
                messages = []
            }
        }
    }

    private struct FlexibleNumber: Decodable {
        let number: Double?
        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if c.decodeNil() {
                number = nil
            } else if let d = try? c.decode(Double.self) {
                number = d
            } else if let s = try? c.decode(String.self) {
                let cleaned = s.replacingOccurrences(of: "%", with: "")
                    .replacingOccurrences(of: ",", with: ".")
                    .trimmingCharacters(in: .whitespaces)
                number = Double(cleaned)
            } else {
                number = nil
            }
        }
    }

    private struct FixturesDTO: Decodable {
        struct Item: Decodable {
            struct Info: Decodable { let id: Int; let date: String }
            struct Team: Decodable { let id: Int; let name: String }
            struct Teams: Decodable { let home: Team; let away: Team }
            struct Goals: Decodable { let home: Int?; let away: Int? }
            let fixture: Info
            let teams: Teams
            let goals: Goals
        }
        let errors: APIErrors
        let response: [Item]
    }

    private struct StatsDTO: Decodable {
        struct TeamStats: Decodable {
            struct Team: Decodable { let id: Int }
            struct Stat: Decodable {
                let type: String
                let value: FlexibleNumber?
            }
            let team: Team
            let statistics: [Stat]
        }
        let errors: APIErrors
        let response: [TeamStats]
    }

    // MARK: Haku

    func stats(for match: Match) async throws -> MatchStats {
        guard let leagueID = Self.leagueID(for: match.league) else { throw ServiceError.noFixture }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        let from = calendar.date(byAdding: .day, value: -1, to: match.date) ?? match.date
        let to = calendar.date(byAdding: .day, value: 1, to: match.date) ?? match.date
        let season = League.from(code: match.league)?.season(on: match.date) ?? 0

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"

        let fixtures: FixturesDTO = try await fetch("fixtures", [
            "league": "\(leagueID)",
            "season": "\(season)",
            "from": formatter.string(from: from),
            "to": formatter.string(from: to)
        ])
        if let message = fixtures.errors.messages.first { throw ServiceError.api(message) }
        guard let item = Self.bestFixture(fixtures.response, for: match) else { throw ServiceError.noFixture }

        let stats: StatsDTO = try await fetch("fixtures/statistics", ["fixture": "\(item.fixture.id)"])
        if let message = stats.errors.messages.first { throw ServiceError.api(message) }
        guard stats.response.count >= 2 else { throw ServiceError.noStats }

        let home = stats.response.first { $0.team.id == item.teams.home.id } ?? stats.response[0]
        let away = stats.response.first { $0.team.id == item.teams.away.id } ?? stats.response[1]
        let values = Self.build(home: home, away: away)
        guard !values.isEmpty else { throw ServiceError.noStats }
        return MatchStats(periods: [.full: values], isSample: false)
    }

    private static func build(home: StatsDTO.TeamStats, away: StatsDTO.TeamStats) -> [StatKey: StatPair] {
        func collect(_ entry: StatsDTO.TeamStats) -> [String: Double] {
            var map: [String: Double] = [:]
            for stat in entry.statistics { map[stat.type] = stat.value?.number ?? 0 }
            return map
        }
        let h = collect(home)
        let a = collect(away)

        let simple: [(String, StatKey)] = [
            ("expected_goals", .xG), ("Ball Possession", .possession), ("Total Shots", .shots),
            ("Shots on Goal", .shotsOnTarget), ("Shots off Goal", .shotsOffTarget), ("Blocked Shots", .blockedShots),
            ("Shots insidebox", .shotsInsideBox), ("Shots outsidebox", .shotsOutsideBox),
            ("Corner Kicks", .corners), ("Offsides", .offsides), ("Fouls", .fouls),
            ("Goalkeeper Saves", .saves), ("Yellow Cards", .yellowCards), ("Red Cards", .redCards)
        ]
        var out: [StatKey: StatPair] = [:]
        for (name, key) in simple {
            if let hv = h[name], let av = a[name] {
                out[key] = StatPair(home: StatValue(value: hv), away: StatValue(value: av))
            }
        }
        if let hMade = h["Passes accurate"], let hAll = h["Total passes"],
           let aMade = a["Passes accurate"], let aAll = a["Total passes"] {
            out[.passes] = StatPair(home: StatValue(value: hMade, attempts: hAll),
                                    away: StatValue(value: aMade, attempts: aAll))
        }
        return out
    }

    // MARK: Ottelun tunnistus

    /// football-data.org ja API-Football nimeävät joukkueet eri tavoin ("Man City" / "Manchester City"),
    /// joten ottelu tunnistetaan lopputuloksen, aloitusajan ja joukkuenimien osittaisen yhteneväisyyden perusteella.
    private static func bestFixture(_ items: [FixturesDTO.Item], for match: Match) -> FixturesDTO.Item? {
        let parser = ISO8601DateFormatter()
        var best: (item: FixturesDTO.Item, score: Double)?
        for item in items {
            let goalsMatch = item.goals.home == match.homeGoals && item.goals.away == match.awayGoals
            let simHome = similarity(match.home, item.teams.home.name)
            let simAway = similarity(match.away, item.teams.away.name)
            guard goalsMatch || (simHome > 0 && simAway > 0) else { continue }

            var score = (goalsMatch ? 10.0 : 0) + Double(simHome + simAway)
            if let kickoff = parser.date(from: item.fixture.date),
               abs(kickoff.timeIntervalSince(match.date)) < 3600 {
                score += 1.5
            }
            if best == nil || score > best!.score { best = (item, score) }
        }
        return best?.item
    }

    private static func tokens(_ name: String) -> [String] {
        let skip: Set<String> = ["fc", "cf", "afc", "sc", "ac", "as", "ssc", "us", "rc", "ud", "cd", "sv", "fsv", "vfb", "vfl", "tsg", "bsc"]
        let folded = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).lowercased()
        return folded
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 1 && !skip.contains($0) && Int($0) == nil }
    }

    private static func similarity(_ a: String, _ b: String) -> Int {
        let tb = tokens(b)
        var score = 0
        for t in tokens(a) {
            if tb.contains(where: { $0 == t || ($0.count >= 3 && t.count >= 3 && ($0.hasPrefix(t) || t.hasPrefix($0))) }) {
                score += 1
            }
        }
        return score
    }

    // MARK: HTTP

    func fetch<T: Decodable>(_ path: String, _ query: [String: String]) async throws -> T {
        var components = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        components?.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = components?.url else { throw ServiceError.badStatus(0) }
        var request = URLRequest(url: url)
        request.setValue(apiKey, forHTTPHeaderField: "x-apisports-key")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ServiceError.badStatus(0) }
        if http.statusCode == 429 { throw ServiceError.rateLimited }
        guard (200..<300).contains(http.statusCode) else { throw ServiceError.badStatus(http.statusCode) }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
