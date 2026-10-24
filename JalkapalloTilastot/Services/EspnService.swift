import Foundation

/// ESPN:n julkinen (epävirallinen) rajapinta: sarjataulukko, otteluohjelma ja ottelutilastot ilman API-avainta.
/// Käytössä sarjoille, joita football-data.orgin ilmainen taso ei kata. Rajapintaa ei ole dokumentoitu,
/// joten vastaukset puretaan varovasti: puuttuva kenttä ei kaada hakua.
struct EspnService {
    private let siteBase = "https://site.api.espn.com/apis/site/v2/sports/soccer"
    private let tableBase = "https://site.api.espn.com/apis/v2/sports/soccer"

    enum ServiceError: LocalizedError {
        case badStatus(Int, String)
        case empty(String)

        var errorDescription: String? {
            switch self {
            case .badStatus(let code, let url): return "ESPN vastasi virheellä \(code): \(url)"
            case .empty(let what): return "ESPN ei palauttanut tietoja: \(what)"
            }
        }
    }

    // MARK: Joustava numeropurku

    private struct Flexible: Decodable {
        let number: Double?
        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let d = try? c.decode(Double.self) {
                number = d
            } else if let s = try? c.decode(String.self) {
                number = Double(s.replacingOccurrences(of: "%", with: "").replacingOccurrences(of: ",", with: ".")
                    .trimmingCharacters(in: .whitespaces))
            } else {
                number = nil
            }
        }
    }

    // MARK: Taulukko

    private struct StandingsDTO: Decodable {
        struct Entry: Decodable {
            struct Team: Decodable {
                struct Logo: Decodable { let href: String? }
                let displayName: String?
                let name: String?
                let logos: [Logo]?
            }
            struct Stat: Decodable {
                let name: String?
                let value: Flexible?
            }
            let team: Team
            let stats: [Stat]?
        }
        struct Table: Decodable { let entries: [Entry]? }
        struct Child: Decodable { let standings: Table? }
        let children: [Child]?
        let standings: Table?
    }

    func standings(for league: League) async throws -> (rows: [StandingRow], crests: [String: String]) {
        let dto: StandingsDTO = try await fetch("\(tableBase)/\(league.espnSlug)/standings", [:])
        // Useita lohkoja (esim. MLS:n itä ja länsi) yhdistetään yhdeksi taulukoksi.
        var entries = dto.children?.flatMap { $0.standings?.entries ?? [] } ?? []
        let groupCount = dto.children?.filter { !($0.standings?.entries ?? []).isEmpty }.count ?? 0
        if entries.isEmpty { entries = dto.standings?.entries ?? [] }
        guard !entries.isEmpty else { throw ServiceError.empty("sarjataulukko") }

        struct Parsed { let team: String; let logo: String?; let values: [String: Double] }
        var parsed: [Parsed] = entries.map { entry in
            var values: [String: Double] = [:]
            for stat in entry.stats ?? [] {
                if let name = stat.name, let value = stat.value?.number { values[name] = value }
            }
            return Parsed(team: entry.team.displayName ?? entry.team.name ?? "?",
                          logo: entry.team.logos?.first?.href, values: values)
        }
        func number(_ p: Parsed, _ key: String) -> Int { Int(p.values[key] ?? 0) }
        func diff(_ p: Parsed) -> Int { number(p, "pointsFor") - number(p, "pointsAgainst") }

        if groupCount > 1 || parsed.contains(where: { $0.values["rank"] == nil }) {
            parsed.sort { (number($0, "points"), diff($0)) > (number($1, "points"), diff($1)) }
        } else {
            parsed.sort { ($0.values["rank"] ?? 0) < ($1.values["rank"] ?? 0) }
        }

        var crests: [String: String] = [:]
        var rows: [StandingRow] = []
        for (index, p) in parsed.enumerated() {
            if let logo = p.logo { crests[p.team] = logo }
            rows.append(StandingRow(position: index + 1, team: p.team, played: number(p, "gamesPlayed"),
                                    won: number(p, "wins"), drawn: number(p, "ties"), lost: number(p, "losses"),
                                    goalsFor: number(p, "pointsFor"), goalsAgainst: number(p, "pointsAgainst"),
                                    points: number(p, "points"), form: []))
        }
        return (rows, crests)
    }

    // MARK: Otteluohjelma

    private struct ScoreboardDTO: Decodable {
        struct Event: Decodable {
            struct Status: Decodable {
                struct Kind: Decodable { let state: String?; let completed: Bool? }
                let type: Kind?
            }
            struct Competition: Decodable {
                struct Competitor: Decodable {
                    struct Team: Decodable { let displayName: String?; let logo: String? }
                    struct Line: Decodable { let value: Flexible? }
                    let linescores: [Line]?
                    let homeAway: String?
                    let score: Flexible?
                    let team: Team
                }
                let competitors: [Competitor]
            }
            let id: String
            let date: String
            let status: Status?
            let competitions: [Competition]?
        }
        let events: [Event]?
    }

    func matches(for league: League) async throws -> (matches: [Match], crests: [String: String]) {
        let ranges = Self.monthRanges(for: league)
        var events: [ScoreboardDTO.Event] = []
        var firstError: Error?
        await withTaskGroup(of: Result<ScoreboardDTO, Error>.self) { group in
            for range in ranges {
                group.addTask {
                    do {
                        let dto: ScoreboardDTO = try await self.fetch("\(self.siteBase)/\(league.espnSlug)/scoreboard",
                                                                      ["dates": range])
                        return .success(dto)
                    } catch {
                        return .failure(error)
                    }
                }
            }
            for await result in group {
                switch result {
                case .success(let dto): events += dto.events ?? []
                case .failure(let error): if firstError == nil { firstError = error }
                }
            }
        }
        // Varavaihtoehto: jos aikavälihaku ei toimi, haetaan yksittäiset päivät (±45 vrk tästä päivästä).
        if events.isEmpty {
            let days = Self.dayList(around: Date(), radius: 45)
            for start in stride(from: 0, to: days.count, by: 15) {
                let slice = Array(days[start..<min(start + 15, days.count)])
                await withTaskGroup(of: [ScoreboardDTO.Event].self) { group in
                    for day in slice {
                        group.addTask {
                            let dto: ScoreboardDTO? = try? await self.fetch(
                                "\(self.siteBase)/\(league.espnSlug)/scoreboard", ["dates": day])
                            return dto?.events ?? []
                        }
                    }
                    for await list in group { events += list }
                }
            }
        }
        if events.isEmpty, let firstError { throw firstError }
        var seen = Set<String>()
        events = events.filter { seen.insert($0.id).inserted }
        let dto = ScoreboardDTO(events: events)
        var crests: [String: String] = [:]
        struct Raw { let id: String; let date: Date; let home: String; let away: String
            let hg: Int?; let ag: Int?; let status: Match.Status; let hh: Int?; let ah: Int? }
        var raw: [Raw] = []
        for event in dto.events ?? [] {
            guard let date = Self.parse(event.date),
                  let competition = event.competitions?.first,
                  let home = competition.competitors.first(where: { $0.homeAway == "home" }),
                  let away = competition.competitors.first(where: { $0.homeAway == "away" }),
                  let homeName = home.team.displayName, let awayName = away.team.displayName else { continue }
            if let logo = home.team.logo { crests[homeName] = logo }
            if let logo = away.team.logo { crests[awayName] = logo }
            let state = event.status?.type?.state ?? "pre"
            let status: Match.Status = state == "post" ? .finished : (state == "in" ? .live : .scheduled)
            let played = status != .scheduled
            raw.append(Raw(id: event.id, date: date, home: homeName, away: awayName,
                           hg: played ? home.score?.number.map { Int($0) } : nil,
                           ag: played ? away.score?.number.map { Int($0) } : nil, status: status,
                           hh: Self.half(home, played: played), ah: Self.half(away, played: played)))
        }
        guard !raw.isEmpty else { throw ServiceError.empty("otteluohjelma") }

        // ESPN ei kerro kierrosta, joten ottelut ryhmitellään viikoittain: viikko = "kierros".
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        func weekKey(_ date: Date) -> Int {
            let c = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
            return (c.yearForWeekOfYear ?? 0) * 100 + (c.weekOfYear ?? 0)
        }
        let weeks = Array(Set(raw.map { weekKey($0.date) })).sorted()
        let matches = raw.map { r in
            Match(id: "\(league.rawValue)-\(r.id)", league: league.rawValue,
                  matchday: (weeks.firstIndex(of: weekKey(r.date)) ?? 0) + 1, date: r.date,
                  home: r.home, away: r.away, homeGoals: r.hg, awayGoals: r.ag, status: r.status,
                  homeHalf: r.hh, awayHalf: r.ah)
        }
        return (matches, crests)
    }

    // MARK: Yksittäisten päivien ottelut

    /// Tiettyjen päivien (yyyyMMdd) ottelut yhdestä sarjasta. Onnistuu, jos edes yksi päivä vastaa.
    func matches(for league: League, days: [String]) async throws -> (matches: [Match], crests: [String: String]) {
        var events: [ScoreboardDTO.Event] = []
        var failure: Error?
        var succeeded = false
        await withTaskGroup(of: Result<ScoreboardDTO, Error>.self) { group in
            for day in days {
                group.addTask {
                    do {
                        let dto: ScoreboardDTO = try await self.fetch("\(self.siteBase)/\(league.espnSlug)/scoreboard", ["dates": day])
                        return .success(dto)
                    } catch {
                        return .failure(error)
                    }
                }
            }
            for await result in group {
                switch result {
                case .success(let dto): succeeded = true; events += dto.events ?? []
                case .failure(let error): if failure == nil { failure = error }
                }
            }
        }
        if !succeeded, let failure { throw failure }
        var seen = Set<String>()
        var crests: [String: String] = [:]
        var result: [Match] = []
        for event in events where seen.insert(event.id).inserted {
            guard let date = Self.parse(event.date),
                  let competition = event.competitions?.first,
                  let home = competition.competitors.first(where: { $0.homeAway == "home" }),
                  let away = competition.competitors.first(where: { $0.homeAway == "away" }),
                  let homeName = home.team.displayName, let awayName = away.team.displayName else { continue }
            if let logo = home.team.logo { crests[homeName] = logo }
            if let logo = away.team.logo { crests[awayName] = logo }
            let state = event.status?.type?.state ?? "pre"
            let status: Match.Status = state == "post" ? .finished : (state == "in" ? .live : .scheduled)
            let played = status != .scheduled
            result.append(Match(id: "\(league.rawValue)-\(event.id)", league: league.rawValue, matchday: 0, date: date,
                                home: homeName, away: awayName,
                                homeGoals: played ? home.score?.number.map { Int($0) } : nil,
                                awayGoals: played ? away.score?.number.map { Int($0) } : nil, status: status,
                                homeHalf: Self.half(home, played: played), awayHalf: Self.half(away, played: played)))
        }
        return (result, crests)
    }

    // MARK: Ottelutilastot

    private struct SummaryDTO: Decodable {
        struct Box: Decodable {
            struct TeamBox: Decodable {
                struct Stat: Decodable { let name: String?; let displayValue: String? }
                let homeAway: String?
                let statistics: [Stat]?
            }
            let teams: [TeamBox]?
        }
        let boxscore: Box?
    }

    func stats(for match: Match, league: League) async throws -> MatchStats {
        let eventID = String(match.id.split(separator: "-").last ?? "")
        let dto: SummaryDTO = try await fetch("\(siteBase)/\(league.espnSlug)/summary", ["event": eventID])
        let teams = dto.boxscore?.teams ?? []
        guard let home = teams.first(where: { $0.homeAway == "home" }) ?? teams.first,
              let away = teams.first(where: { $0.homeAway == "away" }) ?? (teams.count > 1 ? teams[1] : nil) else {
            throw ServiceError.empty("ottelutilastot")
        }
        func collect(_ box: SummaryDTO.Box.TeamBox) -> [String: Double] {
            var map: [String: Double] = [:]
            for stat in box.statistics ?? [] {
                guard let name = stat.name, let text = stat.displayValue,
                      let number = Double(text.replacingOccurrences(of: "%", with: "")) else { continue }
                map[name] = number
            }
            return map
        }
        let h = collect(home)
        let a = collect(away)

        var out: [StatKey: StatPair] = [:]
        func add(_ key: StatKey, _ name: String) {
            if let hv = h[name], let av = a[name] {
                out[key] = StatPair(home: StatValue(value: hv), away: StatValue(value: av))
            }
        }
        add(.possession, "possessionPct")
        add(.shots, "totalShots")
        add(.shotsOnTarget, "shotsOnTarget")
        add(.blockedShots, "blockedShots")
        add(.corners, "wonCorners")
        add(.offsides, "offsides")
        add(.fouls, "foulsCommitted")
        add(.saves, "saves")
        add(.yellowCards, "yellowCards")
        add(.redCards, "redCards")
        if let ht = h["totalShots"], let at = a["totalShots"] {
            let ho = ht - (h["shotsOnTarget"] ?? 0) - (h["blockedShots"] ?? 0)
            let ao = at - (a["shotsOnTarget"] ?? 0) - (a["blockedShots"] ?? 0)
            if ho >= 0, ao >= 0 {
                out[.shotsOffTarget] = StatPair(home: StatValue(value: ho), away: StatValue(value: ao))
            }
        }
        if let hm = h["accuratePasses"], let ha = h["totalPasses"], let am = a["accuratePasses"], let aa = a["totalPasses"] {
            out[.passes] = StatPair(home: StatValue(value: hm, attempts: ha), away: StatValue(value: am, attempts: aa))
        }
        add(.interceptions, "interceptions")
        func addRatio(_ key: StatKey, made: String, total: String) {
            if let hm = h[made], let ht = h[total], let am = a[made], let at = a[total] {
                out[key] = StatPair(home: StatValue(value: hm, attempts: ht), away: StatValue(value: am, attempts: at))
            }
        }
        addRatio(.crosses, made: "accurateCrosses", total: "totalCrosses")
        addRatio(.tackles, made: "effectiveTackles", total: "totalTackles")
        addRatio(.longBalls, made: "accurateLongBalls", total: "totalLongBalls")
        guard !out.isEmpty else { throw ServiceError.empty("ottelutilastot") }
        return MatchStats(periods: [.full: out], isSample: false)
    }

    // MARK: Apu

    /// Ensimmäisen jakson maalit ESPN:n jaksokohtaisista tuloksista (vain pelatuille otteluille).
    private static func half(_ competitor: ScoreboardDTO.Event.Competition.Competitor, played: Bool) -> Int? {
        guard played, let lines = competitor.linescores, lines.count >= 2,
              let value = lines[0].value?.number else { return nil }
        return Int(value)
    }

    /// Päivät muodossa yyyyMMdd annetun hetken ympäriltä.
    private static func dayList(around date: Date, radius: Int) -> [String] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd"
        return (-radius...radius).compactMap { offset in
            Calendar(identifier: .gregorian).date(byAdding: .day, value: offset, to: date).map(formatter.string(from:))
        }
    }

    /// Kauden kuukausivälit muodossa yyyyMMdd-yyyyMMdd. MLS: kalenterivuosi, muut: heinäkuu–kesäkuu.
    private static func monthRanges(for league: League) -> [String] {
        let year = league.season(on: Date())
        let startMonth = league == .mls ? 1 : 7
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        var ranges: [String] = []
        for offset in 0..<12 {
            let monthIndex = startMonth - 1 + offset
            let y = year + monthIndex / 12
            let m = monthIndex % 12 + 1
            guard let first = calendar.date(from: DateComponents(year: y, month: m, day: 1)),
                  let days = calendar.range(of: .day, in: .month, for: first)?.count else { continue }
            ranges.append(String(format: "%04d%02d01-%04d%02d%02d", y, m, y, m, days))
        }
        return ranges
    }

    /// ESPN antaa ajan ilman sekunteja ("2026-10-17T00:30Z"), jota ISO8601DateFormatter ei hyväksy.
    private static func parse(_ text: String) -> Date? {
        for format in ["yyyy-MM-dd'T'HH:mm'Z'", "yyyy-MM-dd'T'HH:mm:ss'Z'"] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(identifier: "UTC")
            formatter.dateFormat = format
            if let date = formatter.date(from: text) { return date }
        }
        return ISO8601DateFormatter().date(from: text)
    }

    private func fetch<T: Decodable>(_ urlString: String, _ query: [String: String]) async throws -> T {
        var components = URLComponents(string: urlString)
        if !query.isEmpty {
            components?.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = components?.url else { throw ServiceError.badStatus(0, urlString) }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse else { throw ServiceError.badStatus(0, url.absoluteString) }
        guard (200..<300).contains(http.statusCode) else {
            throw ServiceError.badStatus(http.statusCode, url.path + (url.query.map { "?" + $0 } ?? ""))
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
