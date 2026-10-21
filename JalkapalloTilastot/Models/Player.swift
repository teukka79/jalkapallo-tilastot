import Foundation

enum Position: String, Codable, CaseIterable, Identifiable, Hashable {
    case goalkeeper = "Maalivahti"
    case defender = "Puolustaja"
    case midfielder = "Keskikenttä"
    case forward = "Hyökkääjä"

    var id: String { rawValue }
}

/// Pelaajan kausitilasto. JSON-tuonti/vienti käyttää tätä rakennetta sellaisenaan.
struct Player: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var team: String
    /// League.rawValue, esim. "PL"
    var league: String
    /// Lippuemoji
    var nationality: String
    var position: Position
    var appearances: Int
    var goals: Int
    var shots: Int
    var shotsOnTarget: Int
    /// Laukaukset rangaistusalueen ulkopuolelta
    var shotsOutsideBox: Int
    /// Maalia kohti -laukaukset rangaistusalueen ulkopuolelta
    var shotsOnTargetOutsideBox: Int

    var onTargetPercent: Double {
        shots > 0 ? Double(shotsOnTarget) / Double(shots) * 100 : 0
    }

    var shotsPerGame: Double {
        appearances > 0 ? Double(shots) / Double(appearances) : 0
    }

    var leagueFlag: String { League.from(code: league)?.flag ?? "" }
}
