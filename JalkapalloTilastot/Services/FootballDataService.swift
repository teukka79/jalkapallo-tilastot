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
                let halfTime: Goals?
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
                                status: status,
                                homeHalf: item.score.halfTime?.home, awayHalf: item.score.halfTime?.away))
        }
        return (result, crests)
    }

    // MARK: Useiden sarjojen ottelut aikavälillä

    private struct RangeDTO: Decodable {
        struct Item: Decodable {
            struct Comp: Decodable { let code: String? }
            let id: Int
            let utcDate: String
            let status: String
            let matchday: Int?
            let competition: Comp
            let homeTeam: TeamDTO
            let awayTeam: TeamDTO
            let score: MatchesDTO.Item.Score
        }
        let matches: [Item]
    }

    /// Kaikkien sarjojen ottelut päivämäärävälillä (yyyy-MM-dd) yhdellä kyselyllä; vain tämän appin football-data-sarjat.
    func matches(from: String, to: String) async throws -> (matches: [Match], crests: [String: String]) {
        let dto: RangeDTO = try await fetch("matches", query: ["dateFrom": from, "dateTo": to])
        let parser = ISO8601DateFormatter()
        var crests: [String: String] = [:]
        var result: [Match] = []
        for item in dto.matches {
            guard let code = item.competition.code, let league = League.from(code: code),
                  league.source == .footballData, let date = parser.date(from: item.utcDate) else { continue }
            if let crest = item.homeTeam.crest { crests[item.homeTeam.display] = crest }
            if let crest = item.awayTeam.crest { crests[item.awayTeam.display] = crest }
            let status: Match.Status
            switch item.status {
            case "FINISHED", "AWARDED": status = .finished
            case "IN_PLAY", "PAUSED": status = .live
            default: status = .scheduled
            }
            result.append(Match(id: "\(code)-\(item.id)", league: code, matchday: item.matchday ?? 0, date: date,
                                home: item.homeTeam.display, away: item.awayTeam.display,
                                homeGoals: item.score.fullTime.home, awayGoals: item.score.fullTime.away,
                                status: status,
                                homeHalf: item.score.halfTime?.home, awayHalf: item.score.halfTime?.away))
        }
        return (result, crests)
    }

    // MARK: Joukkueiden kokoonpanot ja ottelun maalit

    private struct TeamsDTO: Decodable {
        struct Member: Decodable { let name: String; let nationality: String? }
        struct Team: Decodable { let name: String; let shortName: String?; let squad: [Member]? }
        let teams: [Team]
    }

    private struct MatchDetailDTO: Decodable {
        struct Goal: Decodable {
            struct Named: Decodable { let name: String? }
            struct TeamRef: Decodable { let name: String?; let shortName: String? }
            let minute: Int?
            let injuryTime: Int?
            let type: String?
            let team: TeamRef?
            let scorer: Named?
            let assist: Named?
        }
        let goals: [Goal]?
    }

    struct SquadMember { let name: String; let nationality: String }

    /// Sarjan joukkueet pelaajineen (nimi + kansallisuus) yhdellä kyselyllä.
    func squads(for league: League) async throws -> [(team: String, members: [SquadMember])] {
        let dto: TeamsDTO = try await fetch("competitions/\(league.rawValue)/teams")
        return dto.teams.map { team in
            (team: team.shortName ?? team.name,
             members: (team.squad ?? []).compactMap { member in
                 guard let nationality = member.nationality else { return nil }
                 return SquadMember(name: member.name, nationality: nationality)
             })
        }
    }

    /// Ottelun maalit. Vastaus riippuu API-tason sisällöstä, joten tyhjä lista on normaali tulos.
    func goals(matchID: Int, home: String) async throws -> [GoalEvent] {
        let dto: MatchDetailDTO = try await fetch("matches/\(matchID)")
        return (dto.goals ?? []).compactMap { goal in
            guard let minute = goal.minute, let scorer = goal.scorer?.name else { return nil }
            let teamName = goal.team?.shortName ?? goal.team?.name ?? ""
            return GoalEvent(minute: minute, extra: goal.injuryTime, isHome: teamName == home,
                             scorer: scorer, assist: goal.assist?.name, kind: goal.type)
        }
    }

    private func fetch<T: Decodable>(_ path: String, query: [String: String] = [:]) async throws -> T {
        var components = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        if !query.isEmpty {
            components?.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        var request = URLRequest(url: components?.url ?? base.appendingPathComponent(path))
        request.setValue(apiKey, forHTTPHeaderField: "X-Auth-Token")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ServiceError.badStatus(0) }
        if http.statusCode == 429 { throw ServiceError.rateLimited }
        guard (200..<300).contains(http.statusCode) else { throw ServiceError.badStatus(http.statusCode) }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
