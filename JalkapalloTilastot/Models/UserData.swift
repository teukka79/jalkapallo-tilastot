import Foundation

/// Tallennettu pelaajataulukon näkymä: rajaukset ja lajittelu.
struct SavedPlayerView: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var league: String?
    var team: String?
    var position: String?
    var minApps: Int
    var minMinutes: Int
    var watchOnly: Bool
    var ratedOnly: Bool
    var sort: String
    var ascending: Bool
}

/// Käyttäjän omat tiedot varmuuskopiota varten: tähdet, seurattavat, muistiinpanot ja näkymät.
struct UserDataBackup: Codable {
    var ratings: [String: Int]
    var watchlist: [String]
    var notes: [String: String]
    var savedViews: [SavedPlayerView]
}
