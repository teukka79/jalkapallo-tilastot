import Foundation

/// American Soccer Analysis (ASA): MLS:n pelaajatilastot ilman API-avainta.
/// Antaa laukaukset, maalia kohti -laukaukset, maalit, xG:n ja minuutit pelaajittain ja otteluittain
/// (ei laukausten sijaintia, joten rangaistusalueen ulkopuolisia laukauksia ei ole).
/// Vastaukset puretaan joustavasti: puuttuva kenttä ei kaada hakua.
struct AsaService {
    private let base = "https://app.americansocceranalysis.com/api/v1/mls"

    enum ServiceError: LocalizedError {
        case failed(String)
        var errorDescription: String? {
            switch self { case .failed(let text): return "ASA: \(text)" }
        }
    }

    struct Result {
        var players: [Player]
        var lines: [String: [MatchLine]]
    }

    private func fetch(_ path: String, _ query: [String: String] = [:]) async throws -> [[String: Any]] {
        var components = URLComponents(string: base + path)
        if !query.isEmpty {
            components?.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components?.url else { throw ServiceError.failed("virheellinen osoite \(path)") }
        var request = URLRequest(url: url)
        request.timeoutInterval = 60
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ServiceError.failed("HTTP \(http.statusCode) \(path)")
        }
        guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw ServiceError.failed("odottamaton vastaus \(path)")
        }
        return rows
    }

    private func number(_ value: Any?) -> Double {
        if let n = value as? NSNumber { return n.doubleValue }
        if let s = value as? String, let d = Double(s) { return d }
        return 0
    }

    private func position(_ code: String) -> Position {
        switch code.uppercased() {
        case "GK": return .goalkeeper
        case "CB", "FB": return .defender
        case "ST", "W": return .forward
        default: return .midfielder
        }
    }

    private struct Acc {
        var name: String, team: String
        var positions: [String: Int] = [:]
        var appearances = 0, goals = 0, shots = 0, onTarget = 0, minutes = 0
        var xg = 0.0
        var lines: [(date: String, line: MatchLine)] = []
    }

    /// Hakee MLS-kauden (kalenterivuosi) pelaajat ja ottelurivit.
    func mlsPlayers(season: Int) async throws -> Result {
        async let teamRows = fetch("/teams")
        async let playerRows = fetch("/players")
        async let gameRows = fetch("/games", ["season_name": String(season)])
        let (teams, people, games) = try await (teamRows, playerRows, gameRows)

        var teamName: [String: String] = [:]
        for row in teams {
            if let id = row["team_id"] as? String, let name = (row["team_name"] ?? row["team_short_name"]) as? String {
                teamName[id] = name
            }
        }
        var personName: [String: String] = [:]
        for row in people {
            if let id = row["player_id"] as? String, let name = row["player_name"] as? String { personName[id] = name }
        }
        struct Game { let date: String; let home: String; let away: String }
        var game: [String: Game] = [:]
        for row in games {
            guard let id = row["game_id"] as? String else { continue }
            let date = String(((row["date_time_utc"] as? String) ?? "").prefix(10))
            game[id] = Game(date: date, home: row["home_team_id"] as? String ?? "", away: row["away_team_id"] as? String ?? "")
        }

        // Ottelukohtaiset rivit haetaan pelipaikoittain: yksittäinen vastaus on rajattu 10 000 riviin.
        var rows: [[String: Any]] = []
        var failures = 0
        for pos in ["GK", "CB", "FB", "DM", "CM", "AM", "W", "ST"] {
            do {
                rows += try await fetch("/players/xgoals", ["season_name": String(season), "split_by_games": "true",
                                                           "general_position": pos])
            } catch {
                failures += 1
            }
        }
        if failures == 8 {
            rows = try await fetch("/players/xgoals", ["season_name": String(season), "split_by_games": "true"])
        }
        guard !rows.isEmpty else { throw ServiceError.failed("ei pelaajarivejä kaudelle \(season)") }

        var byPlayer: [String: Acc] = [:]
        for row in rows {
            guard let pid = row["player_id"] as? String, let tid = row["team_id"] as? String else { continue }
            let minutes = Int(number(row["minutes_played"]))
            let shots = Int(number(row["shots"]))
            if minutes <= 0 && shots == 0 { continue }
            let key = "MLS-\(pid)-\(tid)"
            var acc = byPlayer[key] ?? Acc(name: personName[pid] ?? pid, team: teamName[tid] ?? tid)
            let goals = Int(number(row["goals"]))
            let onTarget = Int(number(row["shots_on_target"]))
            acc.appearances += minutes > 0 || shots > 0 ? 1 : 0
            acc.goals += goals
            acc.shots += shots
            acc.onTarget += onTarget
            acc.minutes += minutes
            acc.xg += number(row["xgoals"])
            if let code = row["general_position"] as? String { acc.positions[code, default: 0] += 1 }
            let match = (row["game_id"] as? String).flatMap { game[$0] }
            let opponentID = match.map { $0.home == tid ? $0.away : $0.home } ?? ""
            let date = match?.date ?? ""
            acc.lines.append((date, MatchLine(date: date, opponent: teamName[opponentID] ?? "?", goals: goals,
                                              shots: shots, onTarget: onTarget, minutes: minutes)))
            byPlayer[key] = acc
        }

        var players: [Player] = []
        var lines: [String: [MatchLine]] = [:]
        for (id, acc) in byPlayer {
            let code = acc.positions.max { $0.value < $1.value }?.key ?? "CM"
            // Maali on aina laukaus ja kohti maalia, joten luvut pidetään keskenään johdonmukaisina.
            let shots = max(acc.shots, acc.goals)
            var player = Player(id: id, name: acc.name, team: acc.team, league: League.mls.rawValue, nationality: "",
                                position: position(code), appearances: acc.appearances, goals: acc.goals,
                                shots: shots, shotsOnTarget: min(max(acc.onTarget, acc.goals), shots),
                                shotsOutsideBox: 0, shotsOnTargetOutsideBox: 0)
            player.xG = (acc.xg * 100).rounded() / 100
            player.minutes = acc.minutes
            players.append(player)
            lines[id] = acc.lines.sorted { $0.date < $1.date }.map(\.line)
        }
        guard !players.isEmpty else { throw ServiceError.failed("pelaajia ei löytynyt") }
        return Result(players: players, lines: lines)
    }
}
