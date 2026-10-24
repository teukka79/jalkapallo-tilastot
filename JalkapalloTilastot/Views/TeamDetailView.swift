import SwiftUI

struct TeamSelection: Identifiable, Hashable {
    let name: String
    var id: String { name }
}

/// Yhden joukkueen viimeisimmät ottelut sarjassa: tulokset, puoliaikatulokset ja yhteenveto.
struct TeamDetailView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let team: String
    let league: League

    @State private var count = 5
    @State private var venue: Venue = .all
    @State private var openMatch: Match?

    private static let shortDate: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fi_FI")
        f.dateFormat = "d.M."
        return f
    }()

    private static let longDate: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fi_FI")
        f.dateFormat = "EEEE d.M. 'klo' HH:mm"
        return f
    }()

    private var teamGames: TeamGames {
        TeamGames(matches: store.matches[league.rawValue] ?? [], venue: venue)
    }

    private var standing: StandingRow? {
        store.standings[league.rawValue]?.first { TeamNames.key($0.team) == TeamNames.key(team) }
    }

    var body: some View {
        let source = teamGames
        let all = source.games(for: team)
        let shown = count == 0 ? all : Array(all.suffix(count))

        VStack(alignment: .leading, spacing: 16) {
            header(source)
            HStack(spacing: 12) {
                ThemedToggle(options: [(value: 5, label: "5 viimeisintä"), (value: 10, label: "10 viimeisintä"),
                                       (value: 0, label: "Kaikki")], selection: $count)
                ThemedToggle(options: Venue.allCases.map { (value: $0, label: $0.title) }, selection: $venue)
                Spacer()
            }
            summary(shown)
            if shown.isEmpty {
                Text("Pelattuja otteluita ei ole vielä saatavilla")
                    .font(Theme.label(14))
                    .foregroundStyle(Theme.chalkMuted)
                    .frame(maxWidth: .infinity, minHeight: 160)
                    .panel()
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(shown.reversed()) { game in gameRow(game) }
                    }
                }
                .panel()
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            Text("Vain tämän sarjan ottelut. Uusin ottelu ylimpänä; napauta ottelua nähdäksesi sen tilastot.")
                .font(Theme.label(11))
                .foregroundStyle(Theme.chalkMuted)
        }
        .padding(24)
        .frame(width: 620, height: 700)
        .background(Theme.background)
        .preferredColorScheme(.dark)
        .sheet(item: $openMatch) { MatchDetailView(match: $0) }
    }

    // MARK: Osat

    private func header(_ source: TeamGames) -> some View {
        HStack(alignment: .center, spacing: 14) {
            TeamBadge(name: team, size: 52)
            VStack(alignment: .leading, spacing: 4) {
                Text(team).font(Theme.title(24)).foregroundStyle(Theme.chalk)
                Text(subtitle(source)).font(Theme.label(12)).foregroundStyle(Theme.chalkMuted)
            }
            Spacer()
            Button { dismiss() } label: { Image(systemName: "xmark") }
                .buttonStyle(GhostButtonStyle())
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel("Sulje")
                .help("Sulje (Esc)")
        }
    }

    private func subtitle(_ source: TeamGames) -> String {
        var parts = ["\(league.flag) \(league.name)"]
        if let standing { parts.append("sija \(standing.position) · \(standing.points) p") }
        if let next = source.next(for: team) {
            parts.append("seuraava: \(next.home) – \(next.away), \(Self.longDate.string(from: next.date))")
        }
        return parts.joined(separator: " · ")
    }

    private func summary(_ games: [TeamGame]) -> some View {
        let record = TeamRecord(games: games)
        let withHalf = games.filter { $0.halfFor != nil && $0.halfAgainst != nil }
        let halfFor = withHalf.reduce(0) { $0 + ($1.halfFor ?? 0) }
        let halfAgainst = withHalf.reduce(0) { $0 + ($1.halfAgainst ?? 0) }
        let over = games.filter { $0.total > 2 }.count
        return HStack(spacing: 10) {
            tile("Tulokset", "\(record.won)V \(record.drawn)T \(record.lost)H")
            tile("Maalit", "\(record.goalsFor):\(record.goalsAgainst)")
            tile("1. jakson maalit", withHalf.isEmpty ? "–" : "\(halfFor):\(halfAgainst)",
                 help: "Tehdyt ja päästetyt maalit ensimmäisellä puoliajalla (\(withHalf.count) ottelua, joista puoliaikatulos on tiedossa)")
            tile("Yli 2.5", "\(over)/\(games.count)", help: "Otteluita, joissa tehtiin yli 2,5 maalia")
        }
    }

    private func tile(_ label: String, _ value: String, help: String = "") -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(Theme.label(11)).foregroundStyle(Theme.chalkMuted)
            Text(value).font(Theme.number(18, weight: .bold)).foregroundStyle(Theme.chalk)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panel()
        .help(help)
    }

    private func gameRow(_ game: TeamGame) -> some View {
        let m = game.match
        return HStack(spacing: 10) {
            Text(Self.shortDate.string(from: m.date))
                .font(Theme.number(12)).foregroundStyle(Theme.chalkMuted).frame(width: 44, alignment: .leading)
            Text(game.isHome ? "Koti" : "Vieras")
                .font(Theme.label(11)).foregroundStyle(Theme.chalkMuted).frame(width: 42, alignment: .leading)
            TeamBadge(name: game.opponent, size: 28)
            Text(game.opponent).font(Theme.label(14, weight: .semibold)).foregroundStyle(Theme.chalk)
            Spacer(minLength: 0)
            if let h = m.homeHalf, let a = m.awayHalf {
                Text("(\(h)–\(a))").font(Theme.number(12)).foregroundStyle(Theme.chalkMuted)
                    .help("Puoliaikatulos: \(m.home) \(h)–\(a) \(m.away)")
            }
            Text("\(m.homeGoals ?? 0) – \(m.awayGoals ?? 0)")
                .font(Theme.number(15, weight: .bold)).foregroundStyle(Theme.chalk)
                .frame(width: 58)
            ResultBadge(kind: game.code == "W" ? .win : (game.code == "D" ? .draw : .loss),
                        help: "\(m.home) \(m.homeGoals ?? 0)–\(m.awayGoals ?? 0) \(m.away)")
        }
        .padding(.horizontal, 14)
        .frame(height: 50)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.stroke).frame(height: 1) }
        .contentShape(Rectangle())
        .onTapGesture { openMatch = m }
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Avaa ottelun tilastot")
    }
}
