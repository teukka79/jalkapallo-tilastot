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
    private(set) var isLoading = false
    private(set) var ratings: [String: Int]
    /// Joukkueen nimi -> logon osoite (täyttyy live-haussa)
    private(set) var crests: [String: String] = [:]
    var errorMessage: String?

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

        loadSampleSchedules()
    }

    // MARK: Johdetut

    /// Sarjataulukko ja otteluohjelma näyttävät aina yhden sarjan; "Kaikki" -valinnalla Valioliigan.
    var focusLeague: League { selectedLeague ?? .premierLeague }
    var hasAPIKey: Bool { !apiKey.trimmingCharacters(in: .whitespaces).isEmpty }
    var ratedCount: Int { ratings.values.filter { $0 > 0 }.count }
    func crestURL(for team: String) -> URL? { crests[team].flatMap { URL(string: $0) } }
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

    func refresh(force: Bool = false) async {
        guard hasAPIKey else { return }
        let league = focusLeague
        if !force && liveLeagues.contains(league.rawValue) { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let service = FootballDataService(apiKey: apiKey.trimmingCharacters(in: .whitespaces))
        do {
            async let table = service.standings(for: league)
            async let games = service.matches(for: league)
            let (t, g) = try await (table, games)
            standings[league.rawValue] = t.rows
            matches[league.rawValue] = g.matches
            crests.merge(t.crests) { _, new in new }
            crests.merge(g.crests) { _, new in new }
            liveLeagues.insert(league.rawValue)
            updatedAt[league.rawValue] = Date()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Pelaajadatan tuonti ja vienti

    func importPlayers(data: Data) throws {
        let decoded = try JSONDecoder().decode([Player].self, from: data)
        guard !decoded.isEmpty else { throw CocoaError(.fileReadCorruptFile) }
        players = decoded
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
