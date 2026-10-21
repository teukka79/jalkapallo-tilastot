import SwiftUI

/// Kuusi sarjaa. rawValue on football-data.org:n kilpailukoodi.
enum League: String, CaseIterable, Identifiable, Codable, Hashable {
    case championsLeague = "CL"
    case premierLeague = "PL"
    case laLiga = "PD"
    case serieA = "SA"
    case ligue1 = "FL1"
    case bundesliga = "BL1"

    var id: String { rawValue }

    var name: String {
        switch self {
        case .championsLeague: return "Mestarien liiga"
        case .premierLeague: return "Valioliiga"
        case .laLiga: return "La Liga"
        case .serieA: return "Serie A"
        case .ligue1: return "Ligue 1"
        case .bundesliga: return "Bundesliiga"
        }
    }

    var flag: String {
        switch self {
        case .championsLeague: return "🇪🇺"
        case .premierLeague: return "🇬🇧"
        case .laLiga: return "🇪🇸"
        case .serieA: return "🇮🇹"
        case .ligue1: return "🇫🇷"
        case .bundesliga: return "🇩🇪"
        }
    }

    /// Sarjan tunnusväri chipissä ja taulukkokorostuksissa.
    var accent: Color {
        switch self {
        case .championsLeague: return Color(hex: 0x5AA9FF)
        case .premierLeague: return Color(hex: 0x9B7BFF)
        case .laLiga: return Color(hex: 0xFF7A59)
        case .serieA: return Color(hex: 0x3FD0C9)
        case .ligue1: return Color(hex: 0xD6E85A)
        case .bundesliga: return Color(hex: 0xFF5C7A)
        }
    }

    static func from(code: String) -> League? { League(rawValue: code) }
}
