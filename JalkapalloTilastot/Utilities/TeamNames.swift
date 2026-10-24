import Foundation

/// Joukkuenimien yhdistäminen: football-data.org, Understat ja API-Football nimeävät samat joukkueet eri tavoin.
enum TeamNames {
    private static let skip: Set<String> = ["fc", "cf", "afc", "sc", "ac", "as", "ssc", "us", "rc", "ud", "cd", "sv",
                                            "fsv", "vfb", "vfl", "tsg", "bsc", "fk", "ca", "club", "de", "the", "calcio"]

    private static let aliases: [String: String] = [
        "manchester city": "man city", "manchester united": "man united",
        "newcastle united": "newcastle", "wolverhampton wanderers": "wolves", "wolverhampton": "wolves",
        "spurs": "tottenham", "tottenham hotspur": "tottenham",
        "brighton hove albion": "brighton", "brighton hove": "brighton",
        "nottingham": "nottingham forest", "leeds united": "leeds", "west ham united": "west ham",
        "athletic": "athletic club", "real betis balompie": "betis", "real betis": "betis",
        "deportivo alaves": "alaves", "real sociedad futbol": "real sociedad", "celta vigo": "celta vigo",
        "rayo vallecano de madrid": "rayo vallecano", "internazionale milano": "inter", "internazionale": "inter",
        "paris saint germain": "psg", "olympique marseille": "marseille", "olympique lyonnais": "lyon",
        "bayern munich": "bayern munchen", "borussia dortmund": "dortmund", "bayer leverkusen": "leverkusen",
        "rasenballsport leipzig": "rb leipzig", "borussia monchengladbach": "gladbach",
        "borussia m gladbach": "gladbach", "fc cologne": "koln", "cologne": "koln", "koln": "koln",
        "eintracht frankfurt": "eintracht frankfurt", "sporting cp": "sporting cp", "sporting lisbon": "sporting cp",
        "sporting clube portugal": "sporting cp", "benfica": "benfica", "sl benfica": "benfica",
        "barca": "barcelona", "atleti": "atletico madrid", "nott m forest": "nottingham forest",
        "man utd": "man united", "psg": "psg", "mgladbach": "gladbach", "m gladbach": "gladbach",
        "inter milan": "inter", "napoli": "napoli", "ath bilbao": "athletic club", "athletic bilbao": "athletic club"
    ]

    /// Vertailuavain: ilman diakriitteja, etuliitteitä (FC, AC…) ja numeroita; tunnetut vaihtoehtonimet yhdistetty.
    static func key(_ name: String) -> String {
        let folded = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).lowercased()
        let tokens = folded.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty && Int($0) == nil && !skip.contains($0) }
        let joined = tokens.joined(separator: " ")
        return aliases[joined] ?? joined
    }

    /// Toinen avain on toisen osajoukko ("brighton" ⊂ "brighton hove albion").
    static func related(_ a: String, _ b: String) -> Bool {
        let x = Set(a.split(separator: " ")), y = Set(b.split(separator: " "))
        guard !x.isEmpty, !y.isEmpty else { return false }
        return x.isSubset(of: y) || y.isSubset(of: x)
    }
}
