import SwiftUI

/// Yksitoista sarjaa. rawValue on tunnus, jolla sarja tallennetaan (football-data.orgin kilpailukoodi tai oma koodi).
enum League: String, CaseIterable, Identifiable, Codable, Hashable {
    case championsLeague = "CL"
    case europaLeague = "EL"
    case conferenceLeague = "UECL"
    case premierLeague = "PL"
    case laLiga = "PD"
    case serieA = "SA"
    case ligue1 = "FL1"
    case bundesliga = "BL1"
    case saudiProLeague = "SPL"
    case mls = "MLS"
    case superLig = "TUR"

    var id: String { rawValue }

    /// Mistä rajapinnasta taulukko ja ottelut haetaan.
    enum DataSource { case footballData, apiFootball, espn }

    /// Taulukon värivyöhykkeet.
    enum ZoneStyle { case europeanCup, domestic, none }

    var name: String {
        switch self {
        case .championsLeague: return "Mestarien liiga"
        case .europaLeague: return "Eurooppa-liiga"
        case .conferenceLeague: return "Konferenssiliiga"
        case .premierLeague: return "Valioliiga"
        case .laLiga: return "La Liga"
        case .serieA: return "Serie A"
        case .ligue1: return "Ligue 1"
        case .bundesliga: return "Bundesliiga"
        case .saudiProLeague: return "Saudi Pro League"
        case .mls: return "MLS"
        case .superLig: return "Süper Lig"
        }
    }

    var flag: String {
        switch self {
        case .championsLeague, .europaLeague, .conferenceLeague: return "🇪🇺"
        case .premierLeague: return "🇬🇧"
        case .laLiga: return "🇪🇸"
        case .serieA: return "🇮🇹"
        case .ligue1: return "🇫🇷"
        case .bundesliga: return "🇩🇪"
        case .saudiProLeague: return "🇸🇦"
        case .mls: return "🇺🇸"
        case .superLig: return "🇹🇷"
        }
    }

    /// Sarjan tunnusväri chipissä ja taulukkokorostuksissa.
    var accent: Color {
        switch self {
        case .championsLeague: return Color(hex: 0x5AA9FF)
        case .europaLeague: return Color(hex: 0xFF9F43)
        case .conferenceLeague: return Color(hex: 0x37C98B)
        case .premierLeague: return Color(hex: 0x9B7BFF)
        case .laLiga: return Color(hex: 0xFF7A59)
        case .serieA: return Color(hex: 0x3FD0C9)
        case .ligue1: return Color(hex: 0xD6E85A)
        case .bundesliga: return Color(hex: 0xFF5C7A)
        case .saudiProLeague: return Color(hex: 0xE8D08A)
        case .mls: return Color(hex: 0x8DA2FB)
        case .superLig: return Color(hex: 0xE5484D)
        }
    }

    /// football-data.orgin ilmainen taso kattaa vain kuusi ensimmäistä; loput haetaan ESPN:n julkisesta rajapinnasta.
    var source: DataSource {
        switch self {
        case .europaLeague, .conferenceLeague, .saudiProLeague, .mls, .superLig: return .espn
        default: return .footballData
        }
    }

    /// API-Footballin sarjatunnus.
    var apiFootballID: Int {
        switch self {
        case .championsLeague: return 2
        case .europaLeague: return 3
        case .conferenceLeague: return 848
        case .premierLeague: return 39
        case .laLiga: return 140
        case .serieA: return 135
        case .ligue1: return 61
        case .bundesliga: return 78
        case .saudiProLeague: return 307
        case .mls: return 253
        case .superLig: return 203
        }
    }

    /// ESPN:n sarjatunnus.
    var espnSlug: String {
        switch self {
        case .championsLeague: return "uefa.champions"
        case .europaLeague: return "uefa.europa"
        case .conferenceLeague: return "uefa.europa.conf"
        case .premierLeague: return "eng.1"
        case .laLiga: return "esp.1"
        case .serieA: return "ita.1"
        case .ligue1: return "fra.1"
        case .bundesliga: return "ger.1"
        case .saudiProLeague: return "ksa.1"
        case .mls: return "usa.1"
        case .superLig: return "tur.1"
        }
    }

    /// The Odds API:n sarjatunnus.
    var oddsSportKey: String {
        switch self {
        case .championsLeague: return "soccer_uefa_champs_league"
        case .europaLeague: return "soccer_uefa_europa_league"
        case .conferenceLeague: return "soccer_uefa_europa_conference_league"
        case .premierLeague: return "soccer_epl"
        case .laLiga: return "soccer_spain_la_liga"
        case .serieA: return "soccer_italy_serie_a"
        case .ligue1: return "soccer_france_ligue_one"
        case .bundesliga: return "soccer_germany_bundesliga"
        case .saudiProLeague: return "soccer_saudi_arabia_pro_league"
        case .mls: return "soccer_usa_mls"
        case .superLig: return "soccer_turkey_super_league"
        }
    }

    /// Pelaajakohtaiset laukaustilastot (Understat) on vain viidelle suurelle liigalle.
    var hasPlayerStats: Bool {
        switch self {
        case .premierLeague, .laLiga, .serieA, .ligue1, .bundesliga: return true
        default: return false
        }
    }

    var zoneStyle: ZoneStyle {
        switch self {
        case .championsLeague, .europaLeague, .conferenceLeague: return .europeanCup
        case .saudiProLeague, .mls: return .none
        default: return .domestic
        }
    }

    /// API-Footballin kausi: MLS pelataan kalenterivuoden aikana, muut heinäkuusta alkaen.
    func season(on date: Date) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        let parts = calendar.dateComponents([.year, .month], from: date)
        let year = parts.year ?? 0
        if self == .mls { return year }
        return (parts.month ?? 1) >= 7 ? year : year - 1
    }

    static func from(code: String) -> League? { League(rawValue: code) }
}
