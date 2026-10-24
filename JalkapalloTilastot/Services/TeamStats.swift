import Foundation

/// Kotona/vieraissa-rajaus sarjataulukon tilastoille.
enum Venue: String, CaseIterable, Hashable {
    case all, home, away

    var title: String {
        switch self {
        case .all: return "Yhteensä"
        case .home: return "Kotona"
        case .away: return "Vieraissa"
        }
    }
}

/// Joukkueen yksittäinen pelattu ottelu joukkueen näkökulmasta.
struct TeamGame: Identifiable, Hashable {
    let match: Match
    let isHome: Bool
    let goalsFor: Int
    let goalsAgainst: Int

    var id: String { match.id }
    /// "W", "D" tai "L"
    var code: String { TeamGame.code(goalsFor, goalsAgainst) }
    var total: Int { goalsFor + goalsAgainst }
    var opponent: String { isHome ? match.away : match.home }
    var halfFor: Int? { isHome ? match.homeHalf : match.awayHalf }
    var halfAgainst: Int? { isHome ? match.awayHalf : match.homeHalf }
    var halfCode: String? {
        guard let f = halfFor, let a = halfAgainst else { return nil }
        return TeamGame.code(f, a)
    }

    static func code(_ goalsFor: Int, _ goalsAgainst: Int) -> String {
        goalsFor > goalsAgainst ? "W" : (goalsFor == goalsAgainst ? "D" : "L")
    }
}

/// Sarjataulukon yhteenveto yhden joukkueen peleistä.
struct TeamRecord {
    var played = 0, won = 0, drawn = 0, lost = 0
    var goalsFor = 0, goalsAgainst = 0

    var points: Int { won * 3 + drawn }
    var goalDifference: Int { goalsFor - goalsAgainst }

    init(games: [TeamGame]) {
        for game in games {
            played += 1
            goalsFor += game.goalsFor
            goalsAgainst += game.goalsAgainst
            switch game.code {
            case "W": won += 1
            case "D": drawn += 1
            default: lost += 1
            }
        }
    }
}

/// Kaikki pelatut ottelut joukkueittain (vanhimmasta uusimpaan) ja jokaisen joukkueen seuraava ottelu.
/// Joukkueet tunnistetaan nimiavaimella, jotta "Man City" ja "Manchester City" osuvat samaan.
struct TeamGames {
    private var byTeam: [String: [TeamGame]] = [:]
    private var nextByTeam: [String: Match] = [:]
    /// Joukkueiden nimet ottelulistan mukaan.
    private(set) var teamNames: [String] = []

    init(matches: [Match], venue: Venue) {
        var names: [String: String] = [:]
        for match in matches.sorted(by: { $0.date < $1.date }) {
            let homeKey = TeamNames.key(match.home)
            let awayKey = TeamNames.key(match.away)
            if names[homeKey] == nil { names[homeKey] = match.home }
            if names[awayKey] == nil { names[awayKey] = match.away }
            if match.status == .finished, let hg = match.homeGoals, let ag = match.awayGoals {
                if venue != .away {
                    byTeam[homeKey, default: []].append(TeamGame(match: match, isHome: true, goalsFor: hg, goalsAgainst: ag))
                }
                if venue != .home {
                    byTeam[awayKey, default: []].append(TeamGame(match: match, isHome: false, goalsFor: ag, goalsAgainst: hg))
                }
            } else {
                if nextByTeam[homeKey] == nil { nextByTeam[homeKey] = match }
                if nextByTeam[awayKey] == nil { nextByTeam[awayKey] = match }
            }
        }
        teamNames = names.values.sorted()
    }

    func games(for team: String) -> [TeamGame] { byTeam[TeamNames.key(team)] ?? [] }
    func next(for team: String) -> Match? { nextByTeam[TeamNames.key(team)] }

    /// Onko yhdelläkään pelatulla ottelulla puoliaikatulosta.
    var hasHalfTime: Bool {
        byTeam.values.contains { $0.contains { $0.halfFor != nil } }
    }
}
