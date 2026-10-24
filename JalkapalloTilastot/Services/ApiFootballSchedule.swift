import Foundation

/// Taulukko ja otteluohjelma API-Footballista sarjoille, joita football-data.orgin ilmainen taso ei kata
/// (Eurooppa-liiga, Konferenssiliiga, Saudi Pro League, MLS). Kaksi kyselyä per sarja.
extension ApiFootballService {
    private struct StandingsResponse: Decodable {
        struct Row: Decodable {
            struct Team: Decodable { let name: String; let logo: String? }
            struct Totals: Decodable {
                struct Goals: Decodable { let `for`: Int?; let against: Int? }
                let played: Int?; let win: Int?; let draw: Int?; let lose: Int?
                let goals: Goals?
            }
            let rank: Int
            let team: Team
            let points: Int
            let form: String?
            let all: Totals
        }
        struct Entry: Decodable { let league: LeagueInfo }
        struct LeagueInfo: Decodable { let standings: [[Row]] }
        let errors: APIErrors
        let response: [Entry]
    }

    private struct FixturesResponse: Decodable {
        struct Item: Decodable {
            struct Info: Decodable {
                struct Status: Decodable { let short: String? }
                let id: Int
                let date: String
                let status: Status
            }
            struct Team: Decodable { let name: String; let logo: String? }
            struct Teams: Decodable { let home: Team; let away: Team }
            struct Goals: Decodable { let home: Int?; let away: Int? }
            struct LeagueRef: Decodable { let round: String? }
            let fixture: Info
            let league: LeagueRef
            let teams: Teams
            let goals: Goals
        }
        let errors: APIErrors
        let response: [Item]
    }

    func standings(for league: League, season: Int) async throws -> (rows: [StandingRow], crests: [String: String]) {
        let dto: StandingsResponse = try await fetch("standings", ["league": "\(league.apiFootballID)", "season": "\(season)"])
        if let message = dto.errors.messages.first { throw ServiceError.api(message) }
        // MLS palauttaa itä- ja länsikonferenssin erikseen: yhdistetään yhdeksi taulukoksi.
        let groups = dto.response.first?.league.standings ?? []
        var table = groups.flatMap { $0 }
        if groups.count > 1 {
            table.sort { ($0.points, ($0.all.goals?.for ?? 0) - ($0.all.goals?.against ?? 0))
                       > ($1.points, ($1.all.goals?.for ?? 0) - ($1.all.goals?.against ?? 0)) }
        } else {
            table.sort { $0.rank < $1.rank }
        }
        var crests: [String: String] = [:]
        var rows: [StandingRow] = []
        for (index, row) in table.enumerated() {
            if let logo = row.team.logo { crests[row.team.name] = logo }
            let form = (row.form ?? "").map { String($0) }.filter { ["W", "D", "L"].contains($0) }
            rows.append(StandingRow(position: groups.count > 1 ? index + 1 : row.rank, team: row.team.name,
                                    played: row.all.played ?? 0, won: row.all.win ?? 0,
                                    drawn: row.all.draw ?? 0, lost: row.all.lose ?? 0,
                                    goalsFor: row.all.goals?.for ?? 0, goalsAgainst: row.all.goals?.against ?? 0,
                                    points: row.points, form: form))
        }
        return (rows, crests)
    }

    func matches(for league: League, season: Int) async throws -> (matches: [Match], crests: [String: String]) {
        let dto: FixturesResponse = try await fetch("fixtures", ["league": "\(league.apiFootballID)", "season": "\(season)"])
        if let message = dto.errors.messages.first { throw ServiceError.api(message) }
        let parser = ISO8601DateFormatter()
        var crests: [String: String] = [:]
        var result: [Match] = []
        for item in dto.response {
            guard let date = parser.date(from: item.fixture.date) else { continue }
            if let logo = item.teams.home.logo { crests[item.teams.home.name] = logo }
            if let logo = item.teams.away.logo { crests[item.teams.away.name] = logo }
            let status: Match.Status
            switch item.fixture.status.short ?? "" {
            case "FT", "AET", "PEN", "AWD", "WO": status = .finished
            case "1H", "HT", "2H", "ET", "BT", "P", "LIVE", "INT": status = .live
            default: status = .scheduled
            }
            // "Regular Season - 12" -> 12; pudotuspelikierroksilla (esim. "Play-offs") 0.
            let matchday = Int((item.league.round ?? "").split(separator: "-").last?
                .trimmingCharacters(in: .whitespaces) ?? "") ?? 0
            result.append(Match(id: "\(league.rawValue)-\(item.fixture.id)", league: league.rawValue,
                                matchday: matchday, date: date,
                                home: item.teams.home.name, away: item.teams.away.name,
                                homeGoals: item.goals.home, awayGoals: item.goals.away, status: status))
        }
        return (result, crests)
    }
}
