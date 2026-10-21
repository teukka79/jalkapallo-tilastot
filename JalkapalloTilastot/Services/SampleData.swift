import Foundation

struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

/// Generoitu esimerkkidata, jotta appi toimii ilman API-avainta.
/// Pelaajien nimet ja luvut ovat keksittyjä eivätkä kuvaa oikeita henkilöitä.
enum SampleData {
    static let teams: [League: [String]] = [
        .premierLeague: ["Arsenal", "Man City", "Liverpool", "Chelsea", "Tottenham", "Man United", "Newcastle",
                         "Aston Villa", "Brighton", "West Ham", "Crystal Palace", "Fulham", "Brentford", "Everton",
                         "Wolves", "Bournemouth", "Nottingham Forest", "Leeds", "Sunderland", "Burnley"],
        .laLiga: ["Real Madrid", "Barcelona", "Atlético Madrid", "Athletic Club", "Real Sociedad", "Villarreal",
                  "Betis", "Sevilla", "Valencia", "Girona", "Celta Vigo", "Osasuna", "Getafe", "Mallorca",
                  "Rayo Vallecano", "Espanyol", "Alavés", "Levante", "Elche", "Real Oviedo"],
        .serieA: ["Inter", "Milan", "Juventus", "Napoli", "Atalanta", "Roma", "Lazio", "Fiorentina", "Bologna",
                  "Torino", "Genoa", "Udinese", "Como", "Cagliari", "Parma", "Lecce", "Sassuolo", "Cremonese",
                  "Pisa", "Verona"],
        .ligue1: ["PSG", "Marseille", "Monaco", "Lyon", "Lille", "Nice", "Lens", "Rennes", "Strasbourg", "Brest",
                  "Toulouse", "Nantes", "Auxerre", "Angers", "Le Havre", "Lorient", "Metz", "Paris FC"],
        .bundesliga: ["Bayern München", "Dortmund", "Leverkusen", "RB Leipzig", "Eintracht Frankfurt", "Stuttgart",
                      "Freiburg", "Wolfsburg", "Hoffenheim", "Gladbach", "Werder Bremen", "Mainz", "Augsburg",
                      "Union Berlin", "St. Pauli", "Heidenheim", "Köln", "Hamburger SV"],
        .championsLeague: ["Real Madrid", "Bayern München", "Man City", "Arsenal", "PSG", "Inter", "Barcelona",
                           "Liverpool", "Dortmund", "Atlético Madrid", "Juventus", "Leverkusen", "Napoli",
                           "Benfica", "Sporting CP", "PSV"]
    ]

    private static let firstNames = ["Luca", "Mateo", "Jonas", "Rafael", "Diego", "Marco", "Lukas", "Hugo", "Pablo",
                                     "Andre", "Felix", "Nico", "Samuel", "Tomas", "Emil", "Victor", "Karim", "Jules",
                                     "Enzo", "Bruno", "Leon", "Adrian", "Milan", "Oscar", "Theo", "Ivan", "Rui", "Sven"]
    private static let lastNames = ["Moreau", "Ferrer", "Lindqvist", "Costa", "Brandt", "Rossi", "Navarro", "Keller",
                                    "Duarte", "Novak", "Haddad", "Berg", "Silva", "Marchetti", "Vidal", "Okafor",
                                    "Lambert", "Ortega", "Hartmann", "Petrov", "Santos", "Bianchi", "Dubois", "Weber",
                                    "Garcia", "Moretti", "Fontaine", "Kovac", "Aranda", "Schulz", "Pereira", "Lund"]
    private static let flags = ["🇫🇮", "🇸🇪", "🇧🇷", "🇦🇷", "🇫🇷", "🇩🇪", "🇪🇸", "🇮🇹", "🇵🇹", "🇳🇱", "🇳🇴", "🇩🇰",
                                "🇭🇷", "🇳🇬", "🇲🇦", "🇧🇪", "🇨🇮", "🇺🇾"]
    private static let playedRounds = 8

    private static func seed(for league: League) -> UInt64 {
        league.rawValue.unicodeScalars.reduce(UInt64(7)) { $0 &* 31 &+ UInt64($1.value) }
    }

    // MARK: Pelaajat

    static func players(for league: League) -> [Player] {
        guard let names = teams[league] else { return [] }
        var rng = SeededRNG(seed: seed(for: league) &+ 99)
        var result: [Player] = []
        let layout: [Position] = [.forward, .forward, .forward,
                                  .midfielder, .midfielder, .midfielder, .midfielder,
                                  .defender, .defender, .defender]

        for (teamIndex, team) in names.enumerated() {
            let strength = 1.0 - Double(teamIndex) / Double(names.count) * 0.7
            for (slot, position) in layout.enumerated() {
                let apps = Int.random(in: (playedRounds - 3)...playedRounds, using: &rng)
                let perGame: Double
                let outsideShare: Double
                switch position {
                case .forward: perGame = 3.0; outsideShare = 0.28
                case .midfielder: perGame = 1.7; outsideShare = 0.55
                default: perGame = 0.8; outsideShare = 0.5
                }
                let volume = perGame * Double(apps) * (0.7 + 0.5 * strength)
                let shots = Int((volume * Double.random(in: 0.6...1.4, using: &rng)).rounded())
                let onTarget = min(shots, Int((Double(shots) * Double.random(in: 0.28...0.48, using: &rng)).rounded()))
                let outside = min(shots, Int((Double(shots) * outsideShare * Double.random(in: 0.7...1.3, using: &rng)).rounded()))
                let outsideOn = min(outside, onTarget,
                                    Int((Double(outside) * Double.random(in: 0.2...0.4, using: &rng)).rounded()))
                let goals = min(onTarget, Int((Double(onTarget) * Double.random(in: 0.2...0.5, using: &rng)).rounded()))

                let first = firstNames[Int.random(in: 0..<firstNames.count, using: &rng)]
                let last = lastNames[Int.random(in: 0..<lastNames.count, using: &rng)]
                let flag = flags[Int.random(in: 0..<flags.count, using: &rng)]

                result.append(Player(id: "\(league.rawValue)-\(teamIndex)-\(slot)",
                                     name: "\(first) \(last)", team: team, league: league.rawValue,
                                     nationality: flag, position: position, appearances: apps,
                                     goals: goals, shots: shots, shotsOnTarget: onTarget,
                                     shotsOutsideBox: outside, shotsOnTargetOutsideBox: outsideOn))
            }
        }
        return result
    }

    // MARK: Ottelut

    static func matches(for league: League, now: Date = Date()) -> [Match] {
        guard let names = teams[league] else { return [] }
        var rng = SeededRNG(seed: seed(for: league) &+ 11)
        var rounds = roundRobin(names)
        if league == .championsLeague {
            rounds = Array(rounds.prefix(8))
        } else {
            let reversed = rounds.map { round in round.map { pair in (pair.1, pair.0) } }
            rounds += reversed
        }

        let anchor = Calendar.current.startOfDay(for: now)
        let slotOffsets: [TimeInterval] = [13.5 * 3600, 16 * 3600, 18.5 * 3600, 86400 + 15 * 3600]
        var result: [Match] = []

        for (r, pairs) in rounds.enumerated() {
            let roundStart = anchor.addingTimeInterval(Double(r - playedRounds) * 7 * 86400)
            for (i, pair) in pairs.enumerated() {
                let date = roundStart.addingTimeInterval(slotOffsets[i % slotOffsets.count])
                var match = Match(id: "\(league.rawValue)-\(r)-\(i)", league: league.rawValue,
                                  matchday: r + 1, date: date, home: pair.0, away: pair.1,
                                  homeGoals: nil, awayGoals: nil, status: .scheduled)
                if r < playedRounds {
                    let sH = strength(of: pair.0, in: names)
                    let sA = strength(of: pair.1, in: names)
                    let lambdaH = min(3.2, max(0.3, 0.9 + 1.1 * sH - 0.6 * sA + 0.25))
                    let lambdaA = min(3.2, max(0.3, 0.9 + 1.1 * sA - 0.6 * sH))
                    match.homeGoals = poisson(lambdaH, using: &rng)
                    match.awayGoals = poisson(lambdaA, using: &rng)
                    match.status = .finished
                }
                result.append(match)
            }
        }
        return result
    }

    private static func strength(of team: String, in names: [String]) -> Double {
        guard let idx = names.firstIndex(of: team) else { return 0.5 }
        return 1.0 - Double(idx) / Double(names.count) * 0.8
    }

    private static func poisson(_ lambda: Double, using rng: inout SeededRNG) -> Int {
        let limit = exp(-lambda)
        var k = 0
        var p = 1.0
        repeat {
            k += 1
            p *= Double.random(in: 0..<1, using: &rng)
        } while p > limit
        return k - 1
    }

    /// Ympyrämenetelmä: jokainen joukkue pelaa kerran per kierros.
    private static func roundRobin(_ names: [String]) -> [[(String, String)]] {
        var arr = names
        let n = arr.count
        var rounds: [[(String, String)]] = []
        for r in 0..<(n - 1) {
            var pairs: [(String, String)] = []
            for i in 0..<(n / 2) {
                let a = arr[i]
                let b = arr[n - 1 - i]
                pairs.append(r % 2 == 0 ? (a, b) : (b, a))
            }
            rounds.append(pairs)
            let last = arr.removeLast()
            arr.insert(last, at: 1)
        }
        return rounds
    }
}
