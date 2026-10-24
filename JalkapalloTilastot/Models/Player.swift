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
    /// Maaliodottama (xG) ja pelatut minuutit; puuttuvat vanhoista tuonneista
    var xG: Double? = nil
    var minutes: Int? = nil

    /// Maalit miinus xG: positiivinen = tehnyt enemmän kuin laukausten laatu antaisi odottaa
    var xGDifference: Double? { xG.map { Double(goals) - $0 } }

    var xGPerShot: Double? {
        guard let xG, shots > 0 else { return nil }
        return xG / Double(shots)
    }

    var shotsPer90: Double? {
        guard let minutes, minutes > 0 else { return nil }
        return Double(shots) / Double(minutes) * 90
    }

    var onTargetPercent: Double {
        shots > 0 ? Double(shotsOnTarget) / Double(shots) * 100 : 0
    }

    var shotsPerGame: Double {
        appearances > 0 ? Double(shots) / Double(appearances) : 0
    }

    var leagueFlag: String { League.from(code: league)?.flag ?? "" }
}
