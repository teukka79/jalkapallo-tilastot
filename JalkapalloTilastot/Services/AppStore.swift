import SwiftUI
import AppKit
import Observation
import UniformTypeIdentifiers

enum AppSection: String, CaseIterable, Identifiable {
    case players = "Pelaajat"
    case standings = "Sarjataulukko"
    case fixtures = "Otteluohjelma"
    var id: String { rawValue }
}

/// Sovelluksen kuvake. Yökenttä on oletus ja näkyy aina Finderissa;
/// muut vaihdetaan Dockiin ajonaikaisesti, kun appi on käynnissä.
enum AppIconChoice: String, CaseIterable, Identifiable {
    case night, floodlight, pitchLine

    var id: String { rawValue }

    var title: String {
        switch self {
        case .night: return "Yökenttä"
        case .floodlight: return "Valonheitin"
        case .pitchLine: return "Kenttäviiva"
        }
    }

    var imageName: String {
        switch self {
        case .night: return "IconA"
        case .floodlight: return "IconB"
        case .pitchLine: return "IconC"
        }
    }
}

@MainActor
@Observable
final class AppStore {
    private enum Keys {
        static let apiKey = "footballDataAPIKey"
        static let ratings = "playerRatings"
        static let appIcon = "appIconChoice"
        static let apiFootballKey = "apiFootballAPIKey"
        static let toolsFolder = "toolsFolder"
        static let playersUpdated = "playersUpdatedAt"
        static let watchlist = "playerWatchlist"
        static let notes = "playerNotes"
        static let savedViews = "playerSavedViews"
        static let autoUpdate = "autoUpdatePlayers"
        static let oddsKey = "oddsAPIKey"
        static let oddsRemaining = "oddsRemainingCredits"
    }

    // Valinnat
    var selectedLeague: League? = nil
    var section: AppSection = .players

    // Data
    private(set) var players: [Player]
    private(set) var playersAreSample = true
    private(set) var matches: [String: [Match]] = [:]
    private(set) var standings: [String: [StandingRow]] = [:]
    private(set) var liveLeagues: Set<String> = []
    private(set) var updatedAt: [String: Date] = [:]
    /// Pelattujen otteluiden kortit ja kulmat (ottelun tunnus -> tiedot).
    private(set) var extras: [String: MatchExtras] = [:]
    /// Kortti- ja kulmatietojen haun eteneminen (0...1); nil, kun hakua ei ole käynnissä.
    private(set) var extrasProgress: Double? = nil
    private var extrasLoading = false
    private var extrasFailed: Set<String> = []
    /// ESPN:stä haetut pelaajarivit otteluittain (ottelun tunnus -> rivit); varapalvelu Understatille ja cup-sarjat.
    private var espnPlayerData: [String: EspnMatchPlayers] = [:]
    /// ESPN-pelaajien ottelurivit pelaajan tunnuksella.
    private var espnMatchLines: [String: [MatchLine]] = [:]
    private var asaMatchLines: [String: [MatchLine]] = [:]
    private(set) var isLoading = false
    /// "Kaikki sarjat" -näkymän tämän päivän ottelut kaikista sarjoista.
    private(set) var todayMatches: [Match] = []
    private(set) var todayUpdated: Date?
    private(set) var isLoadingToday = false
    /// Sarjat, joiden tämän päivän ottelut ovat oikeaa (ei esimerkki-) dataa.
    private(set) var liveToday: Set<String> = []
    private(set) var ratings: [String: Int]
    /// Joukkueen nimi -> logon osoite (täyttyy live-haussa)
    private(set) var crests: [String: String] = [:]
    var errorMessage: String?
    /// Haettujen oikeiden otteluiden tilastot (välimuisti levyllä)
    private(set) var matchStats: [String: MatchStats] = [:]

    /// Projektikansio, jossa .venv ja tools/fetch_players.py sijaitsevat (pelaajatilastojen päivitys)
    var toolsFolder: String {
        didSet { UserDefaults.standard.set(toolsFolder, forKey: Keys.toolsFolder) }
    }
    /// Näyttää päivityksen etenemisen; nil kun päivitystä ei ole käynnissä
    private(set) var playerUpdateStatus: String?
    private(set) var lastPlayersUpdate: Date?
    var isUpdatingPlayers: Bool { playerUpdateStatus != nil }
    /// 0...1, kun skriptin tulosteesta saadaan edistyminen ([n/N])
    private(set) var playerUpdateProgress: Double?

    // Käyttäjän omat tiedot
    private(set) var watchlist: Set<String>
    private(set) var notes: [String: String]
    private(set) var savedViews: [SavedPlayerView]
    var autoUpdatePlayers: Bool {
        didSet { UserDefaults.standard.set(autoUpdatePlayers, forKey: Keys.autoUpdate) }
    }

    private var crestsByKey: [String: String] = [:]
    @ObservationIgnored private var crestCache: [String: URL?] = [:]
    private var shotFile: ShotFile?
    /// Pelaajien pelatut ottelut (Viim. ottelut -sarake), ladataan matches.json:sta
    private(set) var matchLines: [String: [MatchLine]] = [:]
    private var shotFileLoaded = false
    private var goalCache: [String: [GoalEvent]] = [:]

    var apiFootballKey: String {
        didSet { UserDefaults.standard.set(apiFootballKey, forKey: Keys.apiFootballKey) }
    }

    /// The Odds API -avain (kertoimet)
    var oddsKey: String = UserDefaults.standard.string(forKey: "oddsAPIKey") ?? "" {
        didSet { UserDefaults.standard.set(oddsKey, forKey: Keys.oddsKey) }
    }
    /// Sarjakohtainen kerroinvälimuisti (levyllä, voimassa 6 h)
    private(set) var oddsStored: [String: StoredOdds] = OddsCache.load()
    /// Jäljellä olevat The Odds API -krediitit tässä kuussa
    private(set) var oddsRemaining: Int? = UserDefaults.standard.object(forKey: "oddsRemainingCredits") as? Int
    private(set) var oddsError: String?
    @ObservationIgnored private var oddsLoading: Set<String> = []

    var apiKey: String {
        didSet { UserDefaults.standard.set(apiKey, forKey: Keys.apiKey) }
    }

    var appIcon: AppIconChoice {
        didSet {
            UserDefaults.standard.set(appIcon.rawValue, forKey: Keys.appIcon)
            applyAppIcon()
        }
    }

    init() {
        let defaults = UserDefaults.standard
        apiKey = defaults.string(forKey: Keys.apiKey) ?? ""
        apiFootballKey = defaults.string(forKey: Keys.apiFootballKey) ?? ""
        toolsFolder = defaults.string(forKey: Keys.toolsFolder) ?? (NSHomeDirectory() + "/Developer/Jalkapallo Tilastot")
        lastPlayersUpdate = defaults.object(forKey: Keys.playersUpdated) as? Date
        watchlist = Set(defaults.stringArray(forKey: Keys.watchlist) ?? [])
        autoUpdatePlayers = defaults.object(forKey: Keys.autoUpdate) as? Bool ?? true
        if let data = defaults.data(forKey: Keys.notes),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            notes = decoded
        } else {
            notes = [:]
        }
        if let data = defaults.data(forKey: Keys.savedViews),
           let decoded = try? JSONDecoder().decode([SavedPlayerView].self, from: data) {
            savedViews = decoded
        } else {
            savedViews = []
        }
        appIcon = AppIconChoice(rawValue: defaults.string(forKey: Keys.appIcon) ?? "") ?? .night

        if let data = defaults.data(forKey: Keys.ratings),
           let decoded = try? JSONDecoder().decode([String: Int].self, from: data) {
            ratings = decoded
        } else {
            ratings = [:]
        }

        if let data = try? Data(contentsOf: AppStore.playersFileURL),
           let decoded = try? JSONDecoder().decode([Player].self, from: data), !decoded.isEmpty {
            players = decoded
            playersAreSample = false
        } else {
            players = League.allCases.flatMap { SampleData.players(for: $0) }
        }

        if let data = try? Data(contentsOf: AppStore.statsFileURL),
           let decoded = try? JSONDecoder().decode([String: MatchStats].self, from: data) {
            matchStats = decoded
        }

        if let data = try? Data(contentsOf: AppStore.crestsFileURL),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            crests = decoded
            rebuildCrestIndex()
        }

        if let data = try? Data(contentsOf: AppStore.extrasFileURL),
           let decoded = try? JSONDecoder().decode([String: MatchExtras].self, from: data) {
            extras = decoded
        }

        if let data = try? Data(contentsOf: AppStore.espnPlayersFileURL),
           let decoded = try? JSONDecoder().decode([String: EspnMatchPlayers].self, from: data) {
            espnPlayerData = decoded
            espnMatchLines = AppStore.aggregateEspn(espnPlayerData, leagues: nil).lines
        }

        if let data = try? Data(contentsOf: AppStore.asaMatchesFileURL),
           let decoded = try? JSONDecoder().decode(MatchFile.self, from: data) {
            asaMatchLines = decoded.matches
        }

        loadSampleSchedules()
    }

    // MARK: Johdetut

    /// Sarjataulukko ja otteluohjelma näyttävät aina yhden sarjan; "Kaikki" -valinnalla Valioliigan.
    var focusLeague: League { selectedLeague ?? .premierLeague }
    var hasApiFootballKey: Bool { !apiFootballKey.trimmingCharacters(in: .whitespaces).isEmpty }
    var hasAPIKey: Bool { !apiKey.trimmingCharacters(in: .whitespaces).isEmpty }
    var ratedCount: Int { ratings.values.filter { $0 > 0 }.count }
    /// Logo joukkueelle: ensin täsmällinen nimi, sitten yhdistetty nimiavain ("Manchester City FC" = "Man City").
    func crestURL(for team: String) -> URL? {
        if let cached = crestCache[team] { return cached }
        let found = lookupCrest(team)
        crestCache[team] = found
        return found
    }

    private func rebuildCrestIndex() {
        crestCache = [:]
        crestsByKey = Dictionary(crests.map { (TeamNames.key($0.key), $0.value) }, uniquingKeysWith: { first, _ in first })
    }

    /// Joukkue → logon osoite säilyy levyllä, joten logot näkyvät heti seuraavassa käynnistyksessä.
    private func saveCrests() {
        guard let data = try? JSONEncoder().encode(crests) else { return }
        try? data.write(to: AppStore.crestsFileURL, options: .atomic)
    }

    private func lookupCrest(_ team: String) -> URL? {
        if let direct = crests[team] { return URL(string: direct) }
        let key = TeamNames.key(team)
        if let match = crestsByKey[key] { return URL(string: match) }
        for (other, url) in crestsByKey where TeamNames.related(key, other) { return URL(string: url) }
        return nil
    }
    func isLive(_ league: League) -> Bool { liveLeagues.contains(league.rawValue) }

    // MARK: Kuvake

    /// Oletus (Yökenttä) palauttaa paketin oman kuvakkeen, muut asetetaan Dockiin.
    func applyAppIcon() {
        NSApplication.shared.applicationIconImage = appIcon == .night ? nil : NSImage(named: appIcon.imageName)
    }

    // MARK: Arvostelut

    func rating(for id: String) -> Int { ratings[id] ?? 0 }

    func setRating(_ id: String, _ stars: Int) {
        if stars <= 0 { ratings.removeValue(forKey: id) } else { ratings[id] = stars }
        if let data = try? JSONEncoder().encode(ratings) {
            UserDefaults.standard.set(data, forKey: Keys.ratings)
        }
    }

    // MARK: Live-haku

    /// Onko sarjan live-datalle API-avain (football-data.org tai API-Football sarjan lähteen mukaan).
    func hasKey(for league: League) -> Bool {
        switch league.source {
        case .footballData: return hasAPIKey
        case .apiFootball: return hasApiFootballKey
        case .espn: return true
        }
    }

    func refresh(force: Bool = false) async {
        let league = focusLeague
        guard hasKey(for: league) else { return }
        if !force && liveLeagues.contains(league.rawValue) { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let t: (rows: [StandingRow], crests: [String: String])
            let g: (matches: [Match], crests: [String: String])
            switch league.source {
            case .footballData:
                let service = FootballDataService(apiKey: apiKey.trimmingCharacters(in: .whitespaces))
                async let table = service.standings(for: league)
                async let games = service.matches(for: league)
                let result = try await (table, games)
                t = result.0
                g = result.1
            case .espn:
                let service = EspnService()
                async let table = service.standings(for: league)
                async let games = service.matches(for: league)
                let result = try await (table, games)
                t = result.0
                g = result.1
            case .apiFootball:
                let service = ApiFootballService(apiKey: apiFootballKey.trimmingCharacters(in: .whitespaces))
                let season = league.season(on: Date())
                async let table = service.standings(for: league, season: season)
                async let games = service.matches(for: league, season: season)
                let result = try await (table, games)
                t = result.0
                g = result.1
            }
            standings[league.rawValue] = t.rows
            matches[league.rawValue] = g.matches
            crests.merge(t.crests) { _, new in new }
            crests.merge(g.crests) { _, new in new }
            rebuildCrestIndex()
            saveCrests()
            liveLeagues.insert(league.rawValue)
            updatedAt[league.rawValue] = Date()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Kortit ja kulmat

    /// Hakee puuttuvien pelattujen otteluiden kortit ja kulmat ESPN:stä. Valmiit tallennetaan levylle,
    /// joten jatkossa haetaan vain uudet ottelut.
    func loadExtras(for league: League) async {
        guard !extrasLoading else { return }
        let finished = (matches[league.rawValue] ?? []).filter {
            $0.status == .finished && extras[$0.id] == nil && !extrasFailed.contains($0.id)
        }
        guard !finished.isEmpty else { return }
        extrasLoading = true
        extrasProgress = 0
        defer { extrasLoading = false; extrasProgress = nil }
        let service = EspnService()

        // ESPN-sarjoissa tunnus on valmiina; football-data.org-sarjoissa se etsitään ESPN:n otteluohjelmasta.
        var targets: [(match: Match, event: String)] = []
        if league.source == .espn {
            targets = finished.map { ($0, String($0.id.split(separator: "-").last ?? "")) }
        } else if let espn = try? await service.matches(for: league) {
            func same(_ name: String, _ other: String) -> Bool {
                let a = TeamNames.key(name), b = TeamNames.key(other)
                return a == b || TeamNames.related(a, b)
            }
            for match in finished {
                if let found = espn.matches.first(where: {
                    same($0.home, match.home) && same($0.away, match.away)
                        && abs($0.date.timeIntervalSince(match.date)) < 36 * 3600
                }) {
                    targets.append((match, String(found.id.split(separator: "-").last ?? "")))
                } else {
                    extrasFailed.insert(match.id)
                }
            }
        } else {
            return
        }

        let total = Double(max(targets.count, 1))
        var done = 0
        let chunk = 6
        for start in stride(from: 0, to: targets.count, by: chunk) {
            let slice = Array(targets[start..<min(start + chunk, targets.count)])
            await withTaskGroup(of: (String, MatchExtras?).self) { group in
                for target in slice {
                    group.addTask { (target.match.id, try? await service.extras(eventID: target.event, league: league)) }
                }
                for await (id, value) in group {
                    if let value { extras[id] = value } else { extrasFailed.insert(id) }
                    done += 1
                }
            }
            extrasProgress = Double(done) / total
            saveExtras()
            if Task.isCancelled { break }
        }
    }

    private func saveExtras() {
        guard let data = try? JSONEncoder().encode(extras) else { return }
        try? data.write(to: AppStore.extrasFileURL, options: .atomic)
    }

    // MARK: Kertoimet (The Odds API)

    var hasOddsKey: Bool { !oddsKey.trimmingCharacters(in: .whitespaces).isEmpty }

    /// Ottelun kertoimet välimuistista; nil, jos ei saatavilla.
    func odds(for match: Match) -> MatchOdds? {
        guard let list = oddsStored[match.league]?.entries else { return nil }
        let h = TeamNames.key(match.home), a = TeamNames.key(match.away)
        return list.first { entry in
            let oh = TeamNames.key(entry.homeName), oa = TeamNames.key(entry.awayName)
            let sameTeams = (oh == h || TeamNames.related(oh, h)) && (oa == a || TeamNames.related(oa, a))
            return sameTeams && abs(entry.commence.timeIntervalSince(match.date)) < 36 * 3600
        }
    }

    /// Hakee kertoimet annetuille sarjoille. Tuore välimuisti (alle 6 h) ohitetaan, jotta kuukausikiintiö riittää.
    func loadOdds(for leagues: [League], force: Bool = false) async {
        guard hasOddsKey else { return }
        let service = OddsService(apiKey: oddsKey.trimmingCharacters(in: .whitespaces))
        for league in leagues {
            let id = league.rawValue
            if oddsLoading.contains(id) { continue }
            if !force, let stored = oddsStored[id], Date().timeIntervalSince(stored.fetched) < OddsCache.maxAge { continue }
            if let remaining = oddsRemaining, remaining < 2 { oddsError = "The Odds API: kuukauden krediitit on käytetty"; return }
            oddsLoading.insert(id)
            defer { oddsLoading.remove(id) }
            do {
                let result = try await service.fetch(league: league)
                oddsStored[id] = StoredOdds(fetched: Date(), entries: result.entries)
                OddsCache.save(oddsStored)
                if let remaining = result.remaining {
                    oddsRemaining = remaining
                    UserDefaults.standard.set(remaining, forKey: Keys.oddsRemaining)
                }
                oddsError = nil
            } catch {
                oddsError = error.localizedDescription
                if case OddsService.ServiceError.invalidKey = error { return }
            }
        }
    }

    // MARK: Tämän päivän ottelut kaikista sarjoista

    /// Hakee tämän päivän ottelut: football-data.org yhdellä kyselyllä, ESPN-sarjat erikseen.
    /// Sarjat, joiden live-dataa ei saada (esim. avain puuttuu), täydennetään esimerkkidatalla.
    func refreshToday() async {
        guard !isLoadingToday else { return }
        isLoadingToday = true
        errorMessage = nil
        defer { isLoadingToday = false }

        let calendar = Calendar.current
        let now = Date()
        var collected: [Match] = []
        var live: Set<String> = []
        var newCrests: [String: String] = [:]
        var firstError: Error?

        if hasAPIKey {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(identifier: "UTC")
            formatter.dateFormat = "yyyy-MM-dd"
            let from = formatter.string(from: now.addingTimeInterval(-86_400))
            let to = formatter.string(from: now.addingTimeInterval(86_400))
            let service = FootballDataService(apiKey: apiKey.trimmingCharacters(in: .whitespaces))
            do {
                let result = try await service.matches(from: from, to: to)
                collected += result.matches
                newCrests.merge(result.crests) { _, new in new }
                for league in League.allCases where league.source == .footballData { live.insert(league.rawValue) }
            } catch {
                firstError = error
            }
        }

        // ESPN: eilinen, tämä päivä ja huominen, jotta aikavyöhykkeiden rajapäivät tulevat mukaan.
        let dayFormatter = DateFormatter()
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.dateFormat = "yyyyMMdd"
        let days = [-1, 0, 1].compactMap { calendar.date(byAdding: .day, value: $0, to: now) }.map(dayFormatter.string(from:))
        let espn = EspnService()
        struct Outcome {
            let league: League
            let matches: [Match]
            let crests: [String: String]
            let error: Error?
        }
        var outcomes: [Outcome] = []
        await withTaskGroup(of: Outcome.self) { group in
            for league in League.allCases where league.source == .espn {
                group.addTask {
                    do {
                        let result = try await espn.matches(for: league, days: days)
                        return Outcome(league: league, matches: result.matches, crests: result.crests, error: nil)
                    } catch {
                        return Outcome(league: league, matches: [], crests: [:], error: error)
                    }
                }
            }
            for await outcome in group { outcomes.append(outcome) }
        }
        for outcome in outcomes {
            if let error = outcome.error {
                if firstError == nil { firstError = error }
            } else {
                collected += outcome.matches
                newCrests.merge(outcome.crests) { _, new in new }
                live.insert(outcome.league.rawValue)
            }
        }

        // Sarjat ilman live-dataa: käytetään esimerkkiotteluita.
        for league in League.allCases where !live.contains(league.rawValue) {
            collected += matches[league.rawValue] ?? []
        }

        var seen = Set<String>()
        todayMatches = collected
            .filter { calendar.isDate($0.date, inSameDayAs: now) && seen.insert($0.id).inserted }
            .sorted { $0.date < $1.date }
        liveToday = live
        todayUpdated = now
        if !newCrests.isEmpty {
            crests.merge(newCrests) { _, new in new }
            rebuildCrestIndex()
            saveCrests()
        }
        if let firstError { errorMessage = firstError.localizedDescription }
    }

    // MARK: Ottelutilastot

    enum StatsError: LocalizedError {
        case notPlayed
        case needsKey

        var errorDescription: String? {
            switch self {
            case .notPlayed: return "Ottelusta ei ole vielä tilastoja"
            case .needsKey: return "Ottelutilastot haetaan API-Footballista.\nLisää ilmainen API-avain asetuksista (rattaan kuvake), niin tilastot ilmestyvät tähän."
            }
        }
    }

    /// Esimerkkiottelun tilastot generoidaan; oikean ottelun tilastot haetaan API-Footballista ja tallennetaan levylle.
    func loadStats(for match: Match) async throws -> MatchStats {
        if !(liveLeagues.contains(match.league) || liveToday.contains(match.league)) {
            guard let sample = SampleData.stats(for: match) else { throw StatsError.notPlayed }
            return sample
        }
        if let cached = matchStats[match.id] { return cached }
        if let league = League.from(code: match.league), league.source == .espn {
            let result = try await EspnService().stats(for: match, league: league)
            if match.status == .finished {
                matchStats[match.id] = result
                if let data = try? JSONEncoder().encode(matchStats) {
                    try? data.write(to: AppStore.statsFileURL, options: .atomic)
                }
            }
            return result
        }
        // Muut sarjat: ESPN ensin (ilmainen, ei avainta), API-Football varalla.
        var espnError: Error?
        if let league = League.from(code: match.league) {
            do {
                let espn = EspnService()
                let eventID = try await espn.eventID(for: match, league: league)
                let result = try await espn.stats(for: match, league: league, eventID: eventID)
                if match.status == .finished {
                    matchStats[match.id] = result
                    if let data = try? JSONEncoder().encode(matchStats) {
                        try? data.write(to: AppStore.statsFileURL, options: .atomic)
                    }
                }
                return result
            } catch {
                espnError = error
            }
        }
        guard hasApiFootballKey else { throw espnError ?? StatsError.needsKey }

        let service = ApiFootballService(apiKey: apiFootballKey.trimmingCharacters(in: .whitespaces))
        let result = try await service.stats(for: match)
        if match.status == .finished {
            matchStats[match.id] = result
            if let data = try? JSONEncoder().encode(matchStats) {
                try? data.write(to: AppStore.statsFileURL, options: .atomic)
            }
        }
        return result
    }

    // MARK: Pelaajatilastojen päivitys

    /// Päivittää pelaajat ajamalla tools/fetch_players.py:n (Understat), tuo tuloksen ja täydentää kansallisuudet.
    /// Ensimmäinen ajo kestää useita minuutteja.
    /// only: päivittää vain tämän sarjan (nil = kaikki).
    func updatePlayers(only scope: League? = nil) async {
        guard !isUpdatingPlayers else { return }
        errorMessage = nil
        playerUpdateStatus = "Käynnistetään…"
        let folder = (toolsFolder as NSString).expandingTildeInPath
        let python = folder + "/.venv/bin/python"
        let script = folder + "/tools/fetch_players.py"
        var understatError: String?
        var understatOK = false
        let understatTried = scope == nil || scope?.hasPlayerStats == true || scope == .mls

        if !understatTried {
            // Cup-sarjat ja MLS eivät kulje Python-skriptin kautta
        } else if FileManager.default.isExecutableFile(atPath: python), FileManager.default.fileExists(atPath: script) {
            playerUpdateStatus = "Käynnistetään…"
            playerUpdateProgress = nil
            let temp = FileManager.default.temporaryDirectory
            let output = temp.appendingPathComponent("players-update.json")
            let shotsOutput = temp.appendingPathComponent("shots-update.json")
            let matchesOutput = temp.appendingPathComponent("matches-update.json")
            try? FileManager.default.removeItem(at: output)
            try? FileManager.default.removeItem(at: shotsOutput)
            try? FileManager.default.removeItem(at: matchesOutput)

            let result = await runUpdate(python: python, script: script, folder: folder,
                                         output: output, shotsOutput: shotsOutput, matchesOutput: matchesOutput,
                                         leagueCode: scope?.rawValue)
            if result.status == 0 {
                do {
                    if let scope {
                        try mergePlayers(data: try Data(contentsOf: output), league: scope)
                        mergeDictFile(key: "shots", from: shotsOutput, into: AppStore.shotsFileURL, idPrefix: "\(scope.rawValue)-")
                        mergeDictFile(key: "matches", from: matchesOutput, into: AppStore.matchesFileURL, idPrefix: "\(scope.rawValue)-")
                        shotFile = nil
                        shotFileLoaded = false
                        await loadMatchLines()
                    } else {
                        try importPlayers(data: try Data(contentsOf: output))
                        installShots(from: shotsOutput)
                        installMatches(from: matchesOutput)
                    }
                    lastPlayersUpdate = Date()
                    UserDefaults.standard.set(lastPlayersUpdate, forKey: Keys.playersUpdated)
                    await enrichNationalities()
                    understatOK = true
                } catch {
                    understatError = "Päivityksen tulosta ei voitu lukea"
                }
            } else {
                understatError = result.lastLine
            }
        } else {
            understatError = "projektikansiosta puuttuu .venv tai tools/fetch_players.py"
        }

        // MLS haetaan American Soccer Analysisista (xG mukana); jos se ei vastaa, ESPN:stä.
        playerUpdateProgress = nil
        // Jos skripti (FotMob) toi MLS:n pelaajat laukaustietoineen, ASA:ta ei tarvita
        let mlsFromScript = understatOK && players.contains { $0.league == League.mls.rawValue }
        let asaTried = (scope == nil || scope?.hasAsaPlayerStats == true) && !mlsFromScript
        let asaOK = asaTried ? await updateAsaPlayers() : true

        // Cup-sarjat haetaan aina ESPN:stä. Jos Understat ei vastannut, myös viisi suurta sarjaa haetaan sieltä.
        let leagues = (scope.map { [$0] } ?? League.allCases).filter {
            $0.hasEspnPlayerStats || (understatTried && !understatOK && $0.hasPlayerStats) || (!asaOK && $0.hasAsaPlayerStats)
        }
        let espnOK = leagues.isEmpty ? true : await updateEspnPlayers(leagues: leagues)
        if understatTried && !understatOK {
            errorMessage = espnOK
                ? "Laukaustilastojen lähteet (Understat, FotMob, WhoScored) eivät vastanneet (\(understatError ?? "tuntematon virhe")). Pelaajat haettiin ESPN:stä: xG ja rangaistusalueen ulkopuoliset laukaukset puuttuvat."
                : "Päivitys epäonnistui: \(understatError ?? "tuntematon virhe")"
        }
        playerUpdateStatus = nil
        playerUpdateProgress = nil
    }

    /// Päivittää pelaajat käynnistyessä, jos edellisestä päivityksestä on yli vuorokausi.
    func autoUpdatePlayersIfNeeded() async {
        guard autoUpdatePlayers, !isUpdatingPlayers, let last = lastPlayersUpdate,
              Date().timeIntervalSince(last) > 24 * 3600 else { return }
        await updatePlayers()
    }

    /// Lähteen vaihtuessa pelaaja-id muuttuu: siirtää tähdet vanhalta id:ltä uudelle saman sarjan ja nimen pelaajalle.
    private func migrateRatings(from old: [Player], to new: [Player]) {
        let newIds = Set(new.map(\.id))
        var byName: [String: String] = [:]
        for p in new { byName["\(p.league)|\(p.name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil))"] = p.id }
        var changed = false
        for o in old where !newIds.contains(o.id) {
            guard let stars = ratings[o.id],
                  let nid = byName["\(o.league)|\(o.name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil))"],
                  ratings[nid] == nil else { continue }
            ratings[nid] = stars
            changed = true
        }
        if changed, let data = try? JSONEncoder().encode(ratings) {
            UserDefaults.standard.set(data, forKey: Keys.ratings)
        }
    }

    /// Korvaa yhden sarjan pelaajat skriptin tuloksella ja säilyttää muut sarjat.
    private func mergePlayers(data: Data, league: League) throws {
        let decoded = try JSONDecoder().decode([Player].self, from: data).filter { $0.league == league.rawValue }
        guard !decoded.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
        if playersAreSample { players = [] }
        let old = players.filter { $0.league == league.rawValue }
        players.removeAll { $0.league == league.rawValue }
        players.append(contentsOf: decoded)
        migrateRatings(from: old, to: decoded)
        playersAreSample = false
        if let out = try? JSONEncoder().encode(players) {
            try? out.write(to: AppStore.playersFileURL, options: .atomic)
        }
    }

    /// Yhdistää {avain: {id: …}} -muotoisen tiedoston tulokset olemassa olevaan: sarjan (id-etuliite) vanhat rivit korvataan.
    private func mergeDictFile(key: String, from newURL: URL, into dest: URL, idPrefix: String) {
        guard let newData = try? Data(contentsOf: newURL),
              let newObject = (try? JSONSerialization.jsonObject(with: newData)) as? [String: Any],
              let fresh = newObject[key] as? [String: Any] else { return }
        var merged: [String: Any] = [:]
        if let oldData = try? Data(contentsOf: dest),
           let oldObject = (try? JSONSerialization.jsonObject(with: oldData)) as? [String: Any],
           let old = oldObject[key] as? [String: Any] {
            merged = old.filter { !$0.key.hasPrefix(idPrefix) }
        }
        merged.merge(fresh) { _, new in new }
        if let out = try? JSONSerialization.data(withJSONObject: [key: merged]) {
            try? out.write(to: dest, options: .atomic)
        }
    }

    private func installShots(from url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try? FileManager.default.removeItem(at: AppStore.shotsFileURL)
        try? FileManager.default.copyItem(at: url, to: AppStore.shotsFileURL)
        shotFile = nil
        shotFileLoaded = false
    }

    private func installMatches(from url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try? FileManager.default.removeItem(at: AppStore.matchesFileURL)
        try? FileManager.default.copyItem(at: url, to: AppStore.matchesFileURL)
        Task { await loadMatchLines() }
    }

    /// Lukee pelaajien ottelurivit tiedostosta (puuttuva tiedosto = sarake näyttää viivat).
    func loadMatchLines() async {
        let url = AppStore.matchesFileURL
        let file = await Task.detached(priority: .userInitiated) { () -> MatchFile? in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? JSONDecoder().decode(MatchFile.self, from: data)
        }.value
        matchLines = (file?.matches ?? [:]).merging(espnMatchLines) { current, _ in current }
            .merging(asaMatchLines) { current, _ in current }
    }

    private final class OutputBuffer: @unchecked Sendable {
        private let lock = NSLock()
        private var line = ""

        /// Palauttaa viimeisen ei-tyhjän rivin ja päivittää sen muistiin.
        func update(with text: String) -> String? {
            let lines = text.split(whereSeparator: { $0 == "\n" || $0 == "\r" })
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            guard let last = lines.last else { return nil }
            lock.lock(); line = last; lock.unlock()
            return last
        }

        var last: String { lock.lock(); defer { lock.unlock() }; return line }
    }

    /// Poimii skriptin tulosteesta "[n/N]"-edistymisen.
    private nonisolated static func progress(in text: String) -> Double? {
        var found: Double?
        var searchRange = text.startIndex..<text.endIndex
        while let range = text.range(of: #"\[(\d+)/(\d+)\]"#, options: .regularExpression, range: searchRange) {
            let parts = text[range].dropFirst().dropLast().split(separator: "/")
            if parts.count == 2, let a = Double(parts[0]), let b = Double(parts[1]), b > 0 { found = min(1, a / b) }
            searchRange = range.upperBound..<text.endIndex
        }
        return found
    }

    private func runUpdate(python: String, script: String, folder: String,
                           output: URL, shotsOutput: URL, matchesOutput: URL,
                           leagueCode: String? = nil) async -> (status: Int32, lastLine: String) {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: python)
            process.arguments = [script, "--out", output.path, "--shots-out", shotsOutput.path,
                                 "--matches-out", matchesOutput.path]
            if let leagueCode { process.arguments? += ["--leagues", leagueCode] }
            process.currentDirectoryURL = URL(fileURLWithPath: folder)
            var environment = ProcessInfo.processInfo.environment
            environment["PYTHONUNBUFFERED"] = "1"
            process.environment = environment

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            let buffer = OutputBuffer()

            pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                guard !data.isEmpty, let text = String(data: data, encoding: .utf8),
                      let line = buffer.update(with: text) else { return }
                let shown = String(line.prefix(90))
                let fraction = AppStore.progress(in: text)
                Task { @MainActor in
                    self?.playerUpdateStatus = shown
                    if let fraction { self?.playerUpdateProgress = fraction }
                }
            }
            process.terminationHandler = { finished in
                pipe.fileHandleForReading.readabilityHandler = nil
                // Luetaan loput putkeen jääneestä tulosteesta, jotta virheilmoituksessa näkyy viimeinen rivi.
                let rest = pipe.fileHandleForReading.readDataToEndOfFile()
                if !rest.isEmpty, let text = String(data: rest, encoding: .utf8) { _ = buffer.update(with: text) }
                continuation.resume(returning: (finished.terminationStatus, buffer.last))
            }
            do {
                try process.run()
            } catch {
                pipe.fileHandleForReading.readabilityHandler = nil
                continuation.resume(returning: (-1, error.localizedDescription))
            }
        }
    }

    // MARK: MLS-pelaajat American Soccer Analysisista

    /// Hakee MLS:n pelaajat ja ottelurivit ASA:sta ja korvaa niillä sarjan aiemmat pelaajat. Palauttaa true, jos haku onnistui.
    @discardableResult
    func updateAsaPlayers() async -> Bool {
        playerUpdateStatus = "ASA: MLS…"
        let season = League.mls.season(on: Date())
        guard let result = try? await AsaService().mlsPlayers(season: season) else { return false }
        players.removeAll { $0.league == League.mls.rawValue }
        players.append(contentsOf: result.players)
        playersAreSample = false
        if let data = try? JSONEncoder().encode(players) {
            try? data.write(to: AppStore.playersFileURL, options: .atomic)
        }
        asaMatchLines = result.lines
        let encoded: [String: [[Any]]] = result.lines.mapValues { lines in
            lines.map { [$0.date, $0.opponent, $0.goals, $0.shots, $0.onTarget, $0.outside, $0.outsideOnTarget, $0.minutes] as [Any] }
        }
        if let data = try? JSONSerialization.data(withJSONObject: ["matches": encoded]) {
            try? data.write(to: AppStore.asaMatchesFileURL, options: .atomic)
        }
        matchLines = matchLines.filter { !$0.key.hasPrefix("MLS-") }.merging(asaMatchLines) { current, _ in current }
        lastPlayersUpdate = Date()
        UserDefaults.standard.set(lastPlayersUpdate, forKey: Keys.playersUpdated)
        return true
    }

    // MARK: Pelaajat ESPN:stä (cup-sarjat ja varapalvelu)

    /// Hakee puuttuvien pelattujen otteluiden pelaajarivit ESPN:stä ja yhdistää ne pelaajalistaan.
    /// Palauttaa true, jos sarjoille saatiin pelaajia.
    @discardableResult
    func updateEspnPlayers(leagues: [League]) async -> Bool {
        let service = EspnService()
        var gotAny = false
        for league in leagues {
            playerUpdateStatus = "ESPN: \(league.name)…"
            guard let list = try? await service.matches(for: league) else { continue }
            let finished = list.matches.filter { $0.status == .finished }
            let missing = finished.filter { espnPlayerData[$0.id] == nil }
            var done = 0
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.timeZone = TimeZone(identifier: "UTC")
            for start in stride(from: 0, to: missing.count, by: 6) {
                let slice = Array(missing[start..<min(start + 6, missing.count)])
                await withTaskGroup(of: (Match, [EspnPlayerLine]?).self) { group in
                    for match in slice {
                        let event = String(match.id.split(separator: "-").last ?? "")
                        group.addTask { (match, try? await service.playerLines(eventID: event, league: league)) }
                    }
                    for await (match, lines) in group {
                        if let lines {
                            espnPlayerData[match.id] = EspnMatchPlayers(league: league.rawValue,
                                                                        date: formatter.string(from: match.date),
                                                                        home: match.home, away: match.away, lines: lines)
                        }
                        done += 1
                    }
                }
                playerUpdateStatus = "ESPN: \(league.name) \(done)/\(missing.count)"
                playerUpdateProgress = Double(done) / Double(max(missing.count, 1))
                if let data = try? JSONEncoder().encode(espnPlayerData) {
                    try? data.write(to: AppStore.espnPlayersFileURL, options: .atomic)
                }
            }
            if espnPlayerData.values.contains(where: { $0.league == league.rawValue }) { gotAny = true }
        }
        guard gotAny else { return false }

        let result = AppStore.aggregateEspn(espnPlayerData, leagues: Set(leagues.map(\.rawValue)))
        guard !result.players.isEmpty else { return false }
        let replaced = Set(leagues.map(\.rawValue))
        players.removeAll { replaced.contains($0.league) }
        players.append(contentsOf: result.players)
        playersAreSample = false
        if let data = try? JSONEncoder().encode(players) {
            try? data.write(to: AppStore.playersFileURL, options: .atomic)
        }
        espnMatchLines = AppStore.aggregateEspn(espnPlayerData, leagues: nil).lines
        // Understatin ottelurivit ovat ensisijaisia, ESPN:n täydentävät niitä
        matchLines = matchLines.filter { !$0.key.hasPrefix("espn-") }.merging(espnMatchLines) { current, _ in current }
        lastPlayersUpdate = Date()
        UserDefaults.standard.set(lastPlayersUpdate, forKey: Keys.playersUpdated)
        return true
    }

    /// Laskee pelaajien kausitilastot ja ottelurivit ESPN-pelaajariveistä. leagues = nil: kaikki sarjat.
    private nonisolated static func aggregateEspn(_ data: [String: EspnMatchPlayers],
                                                  leagues: Set<String>?) -> (players: [Player], lines: [String: [MatchLine]]) {
        struct Acc {
            var name: String, team: String, league: String
            var positions: [String: Int] = [:]
            var appearances = 0, goals = 0, shots = 0, onTarget = 0
            var lines: [(date: String, line: MatchLine)] = []
        }
        func position(_ code: String) -> Position? {
            let c = code.uppercased()
            if c.isEmpty || c == "SUB" || c == "S" { return nil }
            if c.hasPrefix("G") { return .goalkeeper }
            if c.hasPrefix("CD") || c.hasPrefix("D") || c == "LB" || c == "RB" || c == "WB" || c == "SW" || c == "LWB" || c == "RWB" { return .defender }
            if c.hasPrefix("CF") || c.hasPrefix("F") || c.hasPrefix("ST") || c.hasPrefix("LF") || c.hasPrefix("RF") || c == "SS" || c == "LW" || c == "RW" { return .forward }
            if c.hasPrefix("M") || c.hasPrefix("CM") || c.hasPrefix("AM") || c.hasPrefix("DM") || c.hasPrefix("LM") || c.hasPrefix("RM") { return .midfielder }
            return nil
        }
        var byPlayer: [String: Acc] = [:]
        for match in data.values {
            if let leagues, !leagues.contains(match.league) { continue }
            for line in match.lines {
                let key = "espn-\(match.league)-\(TeamNames.key(line.team))-\(TeamNames.key(line.name))"
                var acc = byPlayer[key] ?? Acc(name: line.name, team: line.team, league: match.league)
                acc.appearances += 1
                acc.goals += line.goals
                acc.shots += line.shots
                acc.onTarget += line.onTarget
                if let p = position(line.position) { acc.positions[p.rawValue, default: 0] += 1 }
                let opponent = TeamNames.key(line.team) == TeamNames.key(match.home) ? match.away : match.home
                acc.lines.append((match.date, MatchLine(date: match.date, opponent: opponent, goals: line.goals,
                                                        shots: line.shots, onTarget: line.onTarget)))
                byPlayer[key] = acc
            }
        }
        var players: [Player] = []
        var lines: [String: [MatchLine]] = [:]
        for (id, acc) in byPlayer {
            let pos = acc.positions.max { $0.value < $1.value }.flatMap { Position(rawValue: $0.key) } ?? .midfielder
            players.append(Player(id: id, name: acc.name, team: acc.team, league: acc.league, nationality: "",
                                  position: pos, appearances: acc.appearances, goals: acc.goals, shots: acc.shots,
                                  shotsOnTarget: acc.onTarget, shotsOutsideBox: 0, shotsOnTargetOutsideBox: 0))
            lines[id] = acc.lines.sorted { $0.date < $1.date }.map(\.line)
        }
        return (players, lines)
    }

    // MARK: Kansallisuudet

    private struct SquadEntry {
        let tokens: Set<String>
        let nationality: String
        let teamKey: String
    }

    /// Täydentää tyhjät kansallisuudet football-data.orgin joukkuekokoonpanoista (viisi kyselyä).
    func enrichNationalities() async {
        guard hasAPIKey else { return }
        let service = FootballDataService(apiKey: apiKey.trimmingCharacters(in: .whitespaces))
        var index: [String: [SquadEntry]] = [:]
        for league in League.allCases where league.hasPlayerStats {
            playerUpdateStatus = "Haetaan kansallisuudet: \(league.name)…"
            guard let squads = try? await service.squads(for: league) else { continue }
            index[league.rawValue] = squads.flatMap { squad in
                squad.members.map { SquadEntry(tokens: Nationality.tokens($0.name),
                                               nationality: $0.nationality,
                                               teamKey: TeamNames.key(squad.team)) }
            }
        }
        guard !index.isEmpty else { return }

        var updated = players
        for i in updated.indices where updated[i].nationality.isEmpty {
            let tokens = Nationality.tokens(updated[i].name)
            let hits = (index[updated[i].league] ?? []).filter { Nationality.namesMatch(tokens, $0.tokens) }
            let teamKey = TeamNames.key(updated[i].team)
            let pick = hits.first(where: { $0.teamKey == teamKey }) ?? (hits.count == 1 ? hits.first : nil)
            if let pick { updated[i].nationality = Nationality.flag(for: pick.nationality) }
        }
        players = updated
        if let data = try? JSONEncoder().encode(players) {
            try? data.write(to: AppStore.playersFileURL, options: .atomic)
        }
    }

    // MARK: Laukaukset

    /// Pelaajan laukaukset: tuodusta shots.json:sta tai esimerkkidatassa generoituna.
    func shots(for player: Player) async -> [Shot] {
        if !shotFileLoaded {
            let url = AppStore.shotsFileURL
            shotFile = await Task.detached(priority: .userInitiated) { () -> ShotFile? in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? JSONDecoder().decode(ShotFile.self, from: data)
            }.value
            shotFileLoaded = true
        }
        if let list = shotFile?.shots[player.id] { return list }
        return playersAreSample ? SampleData.shots(for: player) : []
    }

    // MARK: Seuranta, muistiinpanot ja näkymät

    func isWatched(_ id: String) -> Bool { watchlist.contains(id) }

    func toggleWatch(_ id: String) {
        if watchlist.contains(id) { watchlist.remove(id) } else { watchlist.insert(id) }
        UserDefaults.standard.set(Array(watchlist), forKey: Keys.watchlist)
    }

    func note(for id: String) -> String { notes[id] ?? "" }
    func hasNote(_ id: String) -> Bool { !(notes[id] ?? "").isEmpty }

    func setNote(_ id: String, _ text: String) {
        if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            notes.removeValue(forKey: id)
        } else {
            notes[id] = text
        }
        persist(notes, key: Keys.notes)
    }

    func saveView(_ view: SavedPlayerView) {
        savedViews.append(view)
        persist(savedViews, key: Keys.savedViews)
    }

    func deleteView(_ id: UUID) {
        savedViews.removeAll { $0.id == id }
        persist(savedViews, key: Keys.savedViews)
    }

    private func persist<T: Encodable>(_ value: T, key: String) {
        if let data = try? JSONEncoder().encode(value) { UserDefaults.standard.set(data, forKey: key) }
    }

    // MARK: Varmuuskopio ja CSV

    func exportUserData() -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let backup = UserDataBackup(ratings: ratings, watchlist: Array(watchlist).sorted(),
                                    notes: notes, savedViews: savedViews)
        return (try? encoder.encode(backup)) ?? Data()
    }

    func importUserData(_ data: Data) throws {
        let backup = try JSONDecoder().decode(UserDataBackup.self, from: data)
        ratings = backup.ratings
        watchlist = Set(backup.watchlist)
        notes = backup.notes
        savedViews = backup.savedViews
        persist(ratings, key: Keys.ratings)
        persist(notes, key: Keys.notes)
        persist(savedViews, key: Keys.savedViews)
        UserDefaults.standard.set(Array(watchlist), forKey: Keys.watchlist)
    }

    /// Pelaajat CSV:nä (Excel-yhteensopiva, pilkkuerotin, pisteet desimaalierottimina).
    func exportCSV() -> Data {
        func quoted(_ text: String) -> String { "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        var lines = ["Pelaaja,Joukkue,Sarja,Asema,Ottelut,Minuutit,Maalit,xG,Laukaukset,Maalia kohti,Ulkopuolelta,Maalia kohti ulkopuolelta,Tähdet,Seurataan,Muistiinpano"]
        for p in players {
            let league = League(rawValue: p.league)?.name ?? p.league
            let fields = [quoted(p.name), quoted(p.team), quoted(league), quoted(p.position.rawValue),
                          "\(p.appearances)", p.minutes.map { "\($0)" } ?? "", "\(p.goals)",
                          p.xG.map { String(format: "%.2f", $0) } ?? "", "\(p.shots)", "\(p.shotsOnTarget)",
                          "\(p.shotsOutsideBox)", "\(p.shotsOnTargetOutsideBox)", "\(rating(for: p.id))",
                          isWatched(p.id) ? "1" : "0", quoted(note(for: p.id))]
            lines.append(fields.joined(separator: ","))
        }
        return ("\u{FEFF}" + lines.joined(separator: "\n")).data(using: .utf8) ?? Data()
    }

    // MARK: Ottelun lisätiedot

    /// Joukkueen viimeisimmät pelatut ottelut ennen annettua hetkeä, vanhin ensin.
    func recentForm(team: String, league: String, before date: Date, limit: Int = 5) -> [FormResult] {
        let played = (matches[league] ?? [])
            .filter { $0.status == .finished && $0.date < date && ($0.home == team || $0.away == team) }
            .sorted { $0.date > $1.date }
            .prefix(limit)
        return played.reversed().compactMap { match in
            guard let hg = match.homeGoals, let ag = match.awayGoals else { return nil }
            let mine = match.home == team ? hg : ag
            let theirs = match.home == team ? ag : hg
            let code = mine > theirs ? "W" : (mine == theirs ? "D" : "L")
            return FormResult(id: match.id, code: code, text: "\(match.home) \(hg)–\(ag) \(match.away)")
        }
    }

    /// Ottelun maalit: esimerkkiotteluille generoidaan, oikeille haetaan football-data.orgista (jos taso sallii).
    func loadGoals(for match: Match) async -> [GoalEvent] {
        if let cached = goalCache[match.id] { return cached }
        var result: [GoalEvent] = []
        if !(liveLeagues.contains(match.league) || liveToday.contains(match.league)) {
            result = SampleData.goals(for: match)
        } else if League.from(code: match.league)?.source == .footballData, hasAPIKey,
                  let id = Int(match.id.split(separator: "-").last ?? "") {
            let service = FootballDataService(apiKey: apiKey.trimmingCharacters(in: .whitespaces))
            result = (try? await service.goals(matchID: id, home: match.home)) ?? []
        }
        if match.status == .finished { goalCache[match.id] = result }
        return result
    }

    // MARK: Pelaajadatan tuonti ja vienti

    func importPlayers(data: Data) throws {
        let decoded = try JSONDecoder().decode([Player].self, from: data)
        guard !decoded.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
        let old = players
        players = decoded
        migrateRatings(from: old, to: decoded)
        playersAreSample = false
        try? data.write(to: AppStore.playersFileURL, options: .atomic)
    }

    func exportData() -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? encoder.encode(players)) ?? Data()
    }

    func resetToSample() {
        try? FileManager.default.removeItem(at: AppStore.playersFileURL)
        players = League.allCases.flatMap { SampleData.players(for: $0) }
        playersAreSample = true
    }

    // MARK: Sisäiset

    private func loadSampleSchedules() {
        for league in League.allCases {
            let games = SampleData.matches(for: league)
            matches[league.rawValue] = games
            standings[league.rawValue] = StandingsCalculator.table(matches: games,
                                                                    teams: SampleData.teams[league] ?? [])
        }
    }

    private static var shotsFileURL: URL {
        let dir = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                appropriateFor: nil, create: true)) ?? FileManager.default.temporaryDirectory
        return dir.appendingPathComponent("shots.json")
    }

    private static var crestsFileURL: URL {
        let dir = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                appropriateFor: nil, create: true)) ?? FileManager.default.temporaryDirectory
        return dir.appendingPathComponent("crests.json")
    }

    private static var espnPlayersFileURL: URL {
        let dir = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                appropriateFor: nil, create: true)) ?? FileManager.default.temporaryDirectory
        return dir.appendingPathComponent("espn-players.json")
    }

    private static var extrasFileURL: URL {
        let dir = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                appropriateFor: nil, create: true)) ?? FileManager.default.temporaryDirectory
        return dir.appendingPathComponent("extras.json")
    }

    private static var matchesFileURL: URL {
        let dir = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                appropriateFor: nil, create: true)) ?? FileManager.default.temporaryDirectory
        return dir.appendingPathComponent("matches.json")
    }

    private static var asaMatchesFileURL: URL {
        let dir = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                appropriateFor: nil, create: true)) ?? FileManager.default.temporaryDirectory
        return dir.appendingPathComponent("asa-matches.json")
    }

    private static var statsFileURL: URL {
        let dir = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                appropriateFor: nil, create: true)) ?? FileManager.default.temporaryDirectory
        return dir.appendingPathComponent("matchstats.json")
    }

    private static var playersFileURL: URL {
        let dir = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                appropriateFor: nil, create: true)) ?? FileManager.default.temporaryDirectory
        return dir.appendingPathComponent("players.json")
    }
}

/// JSON-vienti fileExporterille.
struct PlayersDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
