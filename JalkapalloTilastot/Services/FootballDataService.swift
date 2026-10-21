import Foundation

/// football-data.org v4. Ilmainen taso kattaa kaikki kuusi sarjaa (10 kyselyä/min).
/// Pelaajakohtaisia laukaustilastoja rajapinta ei tarjoa.
struct FootballDataService {
    let apiKey: String
    private let base = URL(string: "https://api.football-data.org/v4")!

    enum ServiceError: LocalizedError {
        case badStatus(Int)
        case rateLimited

        var errorDescription: String? {
            switch self {
            case .rateLimited: return "Kyselyraja täynnä, yritä minuutin kuluttua uudelleen"
            case .badStatus(401), .badStatus(403): return "API-avain ei kelpaa tähän sarjaan"
            case .badStatus(let code): return "Palvelin vastasi virheellä \(code)"
            }
        }
    }

    // MARK: DTO:t

    private struct TeamDTO: Decodable {
        let name: String
        let shortName: String?
        let crest: String?
        var display: String { shortName ?? name }
    }

    private struct StandingsDTO: Decodable {
        struct Group: Decodable {
            let type: String?
            let table: [Row]
        }
        struct Row: Decodable {
            let position: Int
            let team: TeamDTO
            let playedGames: Int
            let won: Int
            let draw: Int
            let lost: Int
            let points: Int
            let goalsFor: Int
            let goalsAgainst: Int
            let form: String?
        }
        let standings: [Group]
    }

    private struct MatchesDTO: Decodable {
        struct Item: Decodable {
            struct Score: Decodable {
                struct Goals: Decodable { let home: Int?; let away: Int? }
                let fullTime: Goals
            }
            let id: Int
            let utcDate: String
            let status: String
            let matchday: Int?
            let homeTeam: TeamDTO
            let awayTeam: TeamDTO
            let score: Score
        }
        let matches: [Item]
    }

    // MARK: Haut

    func standings(for league: League) async throws -> (rows: [StandingRow], crests: [String: String]) {
        let dto: StandingsDTO = try await fetch("competitions/\(league.rawValue)/standings")
        let group = dto.standings.first { $0.type == "TOTAL" } ?? dto.standings.first
        let table = group?.table ?? []
        var crests: [String: String] = [:]
        for row in table {
            if let crest = row.team.crest { crests[row.team.display] = crest }
        }
        let rows = table.map { row in
            let form = (row.form ?? "").split(separator: ",").map { String($0) }
            return StandingRow(position: row.position, team: row.team.display, played: row.playedGames,
                               won: row.won, drawn: row.draw, lost: row.lost,
                               goalsFor: row.goalsFor, goalsAgainst: row.goalsAgainst,
                               points: row.points, form: form)
        }
        return (rows, crests)
    }

    func matches(for league: League) async throws -> (matches: [Match], crests: [String: String]) {
        let dto: MatchesDTO = try await fetch("competitions/\(league.rawValue)/matches")
        let parser = ISO8601DateFormatter()
        var crests: [String: String] = [:]
        var result: [Match] = []
        for item in dto.matches {
            if let crest = item.homeTeam.crest { crests[item.homeTeam.display] = crest }
            if let crest = item.awayTeam.crest { crests[item.awayTeam.display] = crest }
            guard let date = parser.date(from: item.utcDate) else { continue }
            let status: Match.Status
            switch item.status {
            case "FINISHED", "AWARDED": status = .finished
            case "IN_PLAY", "PAUSED": status = .live
            default: status = .scheduled
            }
            result.append(Match(id: "\(league.rawValue)-\(item.id)", league: league.rawValue,
                                matchday: item.matchday ?? 0, date: date,
                                home: item.homeTeam.display, away: item.awayTeam.display,
                                homeGoals: item.score.fullTime.home, awayGoals: item.score.fullTime.away,
                                status: status))
        }
        return (result, crests)
    }

    private func fetch<T: Decodable>(_ path: String) async throws -> T {
        var request = URLRequest(url: base.appendingPathComponent(path))
        request.setValue(apiKey, forHTTPHeaderField: "X-Auth-Token")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ServiceError.badStatus(0) }
        if http.statusCode == 429 { throw ServiceError.rateLimited }
        guard (200..<300).contains(http.statusCode) else { throw ServiceError.badStatus(http.statusCode) }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
