import Foundation

struct Match: Identifiable, Hashable {
    enum Status { case scheduled, live, finished }

    let id: String
    let league: String
    let matchday: Int
    let date: Date
    let home: String
    let away: String
    var homeGoals: Int?
    var awayGoals: Int?
    var status: Status
    /// Puoliaikatulos, jos saatavilla.
    var homeHalf: Int? = nil
    var awayHalf: Int? = nil
}

struct StandingRow: Identifiable, Hashable {
    var id: String { team }
    let position: Int
    let team: String
    let played: Int
    let won: Int
    let drawn: Int
    let lost: Int
    let goalsFor: Int
    let goalsAgainst: Int
    let points: Int
    /// "W", "D" tai "L", vanhin ensin
    let form: [String]

    var goalDifference: Int { goalsFor - goalsAgainst }
}

enum StandingsCalculator {
    /// Laskee sarjataulukon pelatuista otteluista (käytetään esimerkkidatassa).
    static func table(matches: [Match], teams: [String]) -> [StandingRow] {
        struct Acc {
            var played = 0, won = 0, drawn = 0, lost = 0
            var goalsFor = 0, goalsAgainst = 0, points = 0
            var results: [(date: Date, code: String)] = []
        }
        var acc: [String: Acc] = [:]
        for t in teams { acc[t] = Acc() }

        func apply(_ team: String, scored: Int, conceded: Int, date: Date) {
            var a = acc[team] ?? Acc()
            a.played += 1
            a.goalsFor += scored
            a.goalsAgainst += conceded
            if scored > conceded {
                a.won += 1; a.points += 3; a.results.append((date, "W"))
            } else if scored == conceded {
                a.drawn += 1; a.points += 1; a.results.append((date, "D"))
            } else {
                a.lost += 1; a.results.append((date, "L"))
            }
            acc[team] = a
        }

        for m in matches where m.status == .finished {
            guard let hg = m.homeGoals, let ag = m.awayGoals else { continue }
            apply(m.home, scored: hg, conceded: ag, date: m.date)
            apply(m.away, scored: ag, conceded: hg, date: m.date)
        }

        let sorted = acc.sorted { l, r in
            let a = l.value, b = r.value
            if a.points != b.points { return a.points > b.points }
            let gdA = a.goalsFor - a.goalsAgainst
            let gdB = b.goalsFor - b.goalsAgainst
            if gdA != gdB { return gdA > gdB }
            if a.goalsFor != b.goalsFor { return a.goalsFor > b.goalsFor }
            return l.key < r.key
        }

        return sorted.enumerated().map { index, entry in
            let a = entry.value
            let form = a.results.sorted { $0.date < $1.date }.suffix(5).map { $0.code }
            return StandingRow(position: index + 1, team: entry.key, played: a.played,
                               won: a.won, drawn: a.drawn, lost: a.lost,
                               goalsFor: a.goalsFor, goalsAgainst: a.goalsAgainst,
                               points: a.points, form: Array(form))
        }
    }
}

/// Maali ottelun tapahtumalistassa.
struct GoalEvent: Identifiable, Hashable {
    let minute: Int
    let extra: Int?
    let isHome: Bool
    let scorer: String
    let assist: String?
    /// "OWN" (oma maali) tai "PENALTY" (rangaistuspotku)
    let kind: String?

    var id: String { "\(isHome)-\(minute)-\(extra ?? 0)-\(scorer)" }
}

/// Joukkueen yksittäinen tulos muotolistaa varten.
struct FormResult: Identifiable, Hashable {
    let id: String
    /// "W", "D" tai "L"
    let code: String
    let text: String
}
