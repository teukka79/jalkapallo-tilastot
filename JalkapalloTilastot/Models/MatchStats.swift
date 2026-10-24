import Foundation

/// Tilastojen jakso: koko ottelu tai yksittäinen puoliaika.
enum StatPeriod: String, CaseIterable, Identifiable, Codable {
    case full, firstHalf, secondHalf

    var id: String { rawValue }

    var title: String {
        switch self {
        case .full: return "Ottelu"
        case .firstHalf: return "1. puoliaika"
        case .secondHalf: return "2. puoliaika"
        }
    }
}

/// Miten luku esitetään: kokonaisluku, kaksi desimaalia, prosentti tai onnistumisprosentti + (onnistuneet/yritykset).
enum StatKind { case count, decimal, percent, ratio }

enum StatKey: String, CaseIterable, Codable, Hashable {
    case xG, xGOT, xA
    case possession
    case shots, shotsOnTarget, shotsOffTarget, blockedShots, shotsInsideBox, shotsOutsideBox, hitWoodwork
    case bigChances, corners, touchesInBox, throughPasses, offsides, freeKicks
    case passes, longBalls, finalThirdPasses, crosses, throwIns
    case fouls, tackles, duelsWon, clearances, interceptions, saves, errorsToShot, errorsToGoal
    case yellowCards, redCards

    var label: String {
        switch self {
        case .xG: return "Maaliodottama (xG)"
        case .xGOT: return "xG kohti maalia (xGOT)"
        case .xA: return "Syöttöodottama (xA)"
        case .possession: return "Pallonhallinta"
        case .shots: return "Laukaukset yhteensä"
        case .shotsOnTarget: return "Laukaukset kohti maalia"
        case .shotsOffTarget: return "Laukaukset ohi maalin"
        case .blockedShots: return "Blokatut laukaukset"
        case .shotsInsideBox: return "Laukaukset rangaistusal. sisäpuolelta"
        case .shotsOutsideBox: return "Laukaukset rangaistusal. ulkopuolelta"
        case .hitWoodwork: return "Laukaukset maalipuihin"
        case .bigChances: return "Huikea paikka"
        case .corners: return "Kulmapotkut"
        case .touchesInBox: return "Kosketukset vastustajan rang.alueella"
        case .throughPasses: return "Tarkat läpisyötöt"
        case .offsides: return "Paitsiot"
        case .freeKicks: return "Vapaapotkut"
        case .passes: return "Syötöt"
        case .longBalls: return "Pitkät syötöt"
        case .finalThirdPasses: return "Syötöt viimeisellä kolmanneksella"
        case .crosses: return "Keskitykset"
        case .throwIns: return "Sivurajaheitot"
        case .fouls: return "Rikkeet"
        case .tackles: return "Taklaukset"
        case .duelsWon: return "Voitetut kaksinkamppailut"
        case .clearances: return "Purut"
        case .interceptions: return "Katkaisut"
        case .saves: return "Torjunnat"
        case .errorsToShot: return "Laukaukseen johtaneet virheet"
        case .errorsToGoal: return "Maaliin johtaneet virheet"
        case .yellowCards: return "Keltaiset kortit"
        case .redCards: return "Punaiset kortit"
        }
    }

    var kind: StatKind {
        switch self {
        case .xG, .xGOT, .xA: return .decimal
        case .possession: return .percent
        case .passes, .longBalls, .finalThirdPasses, .crosses, .tackles: return .ratio
        default: return .count
        }
    }

    var hint: String? {
        switch self {
        case .xG: return "Laukausten laadusta laskettu odotettu maalimäärä"
        case .xGOT: return "Maalia kohti tulleiden laukausten odotettu maalimäärä"
        case .xA: return "Syöttöjen perusteella laskettu odotettujen maalisyöttöjen määrä"
        default: return nil
        }
    }
}

struct StatValue: Codable, Hashable {
    var value: Double
    /// Suhdeluvuissa yritysten määrä (value = onnistuneet)
    var attempts: Double? = nil

    /// Palkin pituuden peruste: suhdeluvuilla onnistumisprosentti, muuten arvo sellaisenaan.
    func share(for kind: StatKind) -> Double {
        if kind == .ratio {
            guard let attempts, attempts > 0 else { return 0 }
            return value / attempts
        }
        return value
    }

    static func + (l: StatValue, r: StatValue) -> StatValue {
        let sum = ((l.value + r.value) * 100).rounded() / 100
        let attempts: Double? = (l.attempts == nil && r.attempts == nil) ? nil : (l.attempts ?? 0) + (r.attempts ?? 0)
        return StatValue(value: sum, attempts: attempts)
    }
}

struct StatPair: Codable, Hashable {
    var home: StatValue
    var away: StatValue
}

/// Yhden ottelun tilastot jaksoittain. Avaimina merkkijonot, jotta JSON-välimuisti pysyy tavallisena objektina.
struct MatchStats: Codable, Hashable {
    private var periods: [String: [String: StatPair]]
    var isSample: Bool

    init(periods: [StatPeriod: [StatKey: StatPair]], isSample: Bool) {
        var raw: [String: [String: StatPair]] = [:]
        for (period, values) in periods {
            raw[period.rawValue] = Dictionary(uniqueKeysWithValues: values.map { ($0.key.rawValue, $0.value) })
        }
        self.periods = raw
        self.isSample = isSample
    }

    func values(for period: StatPeriod) -> [StatKey: StatPair] {
        var out: [StatKey: StatPair] = [:]
        for (raw, pair) in periods[period.rawValue] ?? [:] {
            if let key = StatKey(rawValue: raw) { out[key] = pair }
        }
        return out
    }

    var availablePeriods: [StatPeriod] {
        StatPeriod.allCases.filter { !(periods[$0.rawValue] ?? [:]).isEmpty }
    }

    /// Yhdistää kaksi puoliaikaa koko ottelun tilastoksi.
    static func combine(_ a: [StatKey: StatPair], _ b: [StatKey: StatPair]) -> [StatKey: StatPair] {
        var out: [StatKey: StatPair] = [:]
        for key in Set(a.keys).union(b.keys) {
            guard let x = a[key] else { out[key] = b[key]; continue }
            guard let y = b[key] else { out[key] = x; continue }
            if key == .possession {
                let home = ((x.home.value + y.home.value) / 2).rounded()
                out[key] = StatPair(home: StatValue(value: home), away: StatValue(value: 100 - home))
            } else {
                out[key] = StatPair(home: x.home + y.home, away: x.away + y.away)
            }
        }
        return out
    }
}

/// Tilastonäkymän ryhmittely samassa järjestyksessä kuin esimerkkikuvissa.
struct StatGroup: Identifiable {
    let title: String
    let keys: [StatKey]
    var id: String { title }

    static let all: [StatGroup] = [
        StatGroup(title: "Tärkeimmät tilastot",
                  keys: [.xG, .possession, .shots, .shotsOnTarget, .bigChances, .corners, .passes, .yellowCards, .redCards]),
        StatGroup(title: "Laukaukset",
                  keys: [.xG, .xGOT, .shots, .shotsOnTarget, .shotsOffTarget, .blockedShots,
                         .shotsInsideBox, .shotsOutsideBox, .hitWoodwork]),
        StatGroup(title: "Hyökkäys",
                  keys: [.bigChances, .corners, .touchesInBox, .throughPasses, .offsides, .freeKicks]),
        StatGroup(title: "Syötöt",
                  keys: [.passes, .longBalls, .finalThirdPasses, .crosses, .xA, .throwIns]),
        StatGroup(title: "Puolustus",
                  keys: [.fouls, .tackles, .duelsWon, .clearances, .interceptions, .saves, .errorsToShot, .errorsToGoal])
    ]
}
