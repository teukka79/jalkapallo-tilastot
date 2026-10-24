import Foundation

enum ShotResult: String {
    case goal = "G", saved = "S", missed = "M", blocked = "B", post = "P"

    var onTarget: Bool { self == .goal || self == .saved }
}

/// Yksi laukaus. Koordinaatit Understatin tapaan: x 0–1 kentän pituussuunnassa (maali x = 1), y 0–1 leveyssuunnassa.
/// JSONissa laukaus on taulukko [x, y, xG, minuutti, tulos, tilanne].
struct Shot: Hashable, Decodable {
    let x: Double
    let y: Double
    let xG: Double
    let minute: Int
    let result: ShotResult
    let situation: String

    static let boxX = (105.0 - 16.5) / 105.0
    static let boxYMin = (68.0 - 40.32) / 2 / 68.0
    static let boxYMax = 1 - ((68.0 - 40.32) / 2 / 68.0)

    var isOutsideBox: Bool { !(x >= Shot.boxX && y >= Shot.boxYMin && y <= Shot.boxYMax) }

    init(x: Double, y: Double, xG: Double, minute: Int, result: ShotResult, situation: String = "O") {
        self.x = x
        self.y = y
        self.xG = xG
        self.minute = minute
        self.result = result
        self.situation = situation
    }

    init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        x = try c.decode(Double.self)
        y = try c.decode(Double.self)
        xG = try c.decode(Double.self)
        minute = try c.decode(Int.self)
        let code = try c.decode(String.self)
        result = ShotResult(rawValue: code) ?? .missed
        situation = try c.decode(String.self)
    }
}

/// shots.json: pelaajan tunnus -> laukaukset
struct ShotFile: Decodable {
    let shots: [String: [Shot]]
}

/// Yksi pelaajan pelaama ottelu. JSONissa rivi on taulukko
/// [päivä, vastustaja, maalit, laukaukset, maalia kohti, ulkopuolelta, ulkopuolelta maalia kohti, minuutit].
struct MatchLine: Hashable, Decodable {
    let date: String
    let opponent: String
    let goals: Int
    let shots: Int
    let onTarget: Int
    let outside: Int
    let outsideOnTarget: Int
    let minutes: Int

    init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        date = try c.decode(String.self)
        opponent = try c.decode(String.self)
        goals = try c.decode(Int.self)
        shots = try c.decode(Int.self)
        onTarget = try c.decode(Int.self)
        outside = try c.decode(Int.self)
        outsideOnTarget = try c.decode(Int.self)
        minutes = try c.decode(Int.self)
    }

    /// "2026-10-03" -> "03.10."
    var shortDate: String {
        guard date.count >= 10 else { return date }
        return "\(date.suffix(2)).\(date.dropFirst(5).prefix(2))."
    }
}

/// matches.json: pelaajan tunnus -> pelatut ottelut aikajärjestyksessä
struct MatchFile: Decodable {
    let matches: [String: [MatchLine]]
}
