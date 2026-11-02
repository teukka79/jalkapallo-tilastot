import SwiftUI

/// Alkamattoman ottelun esikatselu: kunto, sarjasijoitus, keskinäiset ottelut, kovimmat pelaajat ja tilastovertailu.
struct MatchPreviewView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let match: Match

    @State private var selectedPlayer: Player?

    /// Joukkueen tiedot esikatselua varten.
    private struct Side {
        let name: String
        let all: [TeamGame]
        /// Kotijoukkueen kotiottelut / vierasjoukkueen vierasottelut
        let atVenue: [TeamGame]
        let standing: StandingRow?
        let players: [Player]
        var played: Int { all.isEmpty ? (standing?.played ?? 0) : all.count }
    }

    private var league: League? { League(rawValue: match.league) }

    private func sameTeam(_ a: String, _ b: String) -> Bool {
        let x = TeamNames.key(a), y = TeamNames.key(b)
        return x == y || TeamNames.related(x, y)
    }

    private func side(_ name: String, home: Bool) -> Side {
        let matches = store.matches[match.league] ?? []
        let all = TeamGames(matches: matches, venue: .all).games(for: name)
        let atVenue = TeamGames(matches: matches, venue: home ? .home : .away).games(for: name)
        let standing = (store.standings[match.league] ?? []).first { sameTeam($0.team, name) }
        let players = store.playersAreSample ? [] : store.players.filter { $0.league == match.league && sameTeam($0.team, name) }
        return Side(name: name, all: all, atVenue: atVenue, standing: standing, players: players)
    }

    var body: some View {
        let h = side(match.home, home: true)
        let a = side(match.away, home: false)
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.stroke)
            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    formSection(h, a)
                    standingSection(h, a)
                    headToHeadSection
                    topPlayersSection(h, a)
                    goalSection(h, a)
                    strengthSection(h, a)
                }
                .padding(20)
            }
        }
        .frame(width: 640, height: 740)
        .background { PitchBackground() }
        .preferredColorScheme(.dark)
        .task { await store.loadMatchLines() }
        .sheet(item: $selectedPlayer) { PlayerDetailView(player: $0) }
    }

    // MARK: Yläosa

    private var header: some View {
        VStack(spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(league?.flag ?? "") \(league?.name ?? "")")
                        .font(Theme.label(12, weight: .semibold))
                        .foregroundStyle(Theme.chalk)
                    Text("Kierros \(match.matchday) · \(Format.day(match.date))")
                        .font(Theme.label(11))
                        .foregroundStyle(Theme.chalkMuted)
                }
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark") }
                    .buttonStyle(GhostButtonStyle())
                    .keyboardShortcut(.cancelAction)
                    .help("Sulje (Esc)")
            }
            HStack(spacing: 18) {
                teamBlock(match.home)
                VStack(spacing: 4) {
                    Text(Format.time(match.date))
                        .font(Theme.number(30, weight: .bold))
                        .foregroundStyle(Theme.chalk)
                    Text("Alkaa")
                        .font(Theme.label(11, weight: .semibold))
                        .foregroundStyle(Theme.chalkMuted)
                }
                .frame(width: 130)
                teamBlock(match.away)
            }
            oddsRow
        }
        .padding(20)
    }

    private func teamBlock(_ name: String) -> some View {
        VStack(spacing: 8) {
            TeamBadge(name: name, size: 48)
            Text(name)
                .font(Theme.label(14, weight: .semibold))
                .foregroundStyle(Theme.chalk)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var oddsRow: some View {
        if let odds = store.odds(for: match), odds.hasMatchOdds {
            HStack(spacing: 8) {
                oddsPill("1", odds.home)
                oddsPill("X", odds.draw)
                oddsPill("2", odds.away)
                if odds.over != nil || odds.under != nil {
                    let line = String(format: "%.1f", odds.line).replacingOccurrences(of: ".", with: ",")
                    oddsPill("Yli \(line)", odds.over)
                    oddsPill("Alle \(line)", odds.under)
                }
            }
        }
    }

    private func oddsPill(_ label: String, _ value: Double?) -> some View {
        HStack(spacing: 5) {
            Text(label).font(Theme.label(11, weight: .semibold)).foregroundStyle(Theme.chalkMuted)
            Text(value.map { String(format: "%.2f", $0).replacingOccurrences(of: ".", with: ",") } ?? "–")
                .font(Theme.number(13, weight: .bold))
                .foregroundStyle(Theme.floodlight)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Theme.panelRaised.opacity(0.8), in: Capsule())
    }

    // MARK: Osiot

    private func section<Content: View>(_ title: String, hint: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(title.uppercased())
                    .font(Theme.label(10, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(Theme.chalkMuted)
                Spacer()
                if let hint {
                    Text(hint).font(Theme.label(10)).foregroundStyle(Theme.chalkMuted)
                }
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .panel()
    }

    private func compareHead(_ h: Side, _ a: Side) -> some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Text(h.name).font(Theme.label(11, weight: .semibold)).foregroundStyle(Theme.chalk).lineLimit(1)
                TeamBadge(name: h.name, size: 20)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            Color.clear.frame(width: 170, height: 1)
            HStack(spacing: 6) {
                TeamBadge(name: a.name, size: 20)
                Text(a.name).font(Theme.label(11, weight: .semibold)).foregroundStyle(Theme.chalk).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func compare(_ label: String, _ h: String, _ a: String) -> some View {
        HStack(spacing: 12) {
            Text(h).font(Theme.number(14, weight: .semibold)).foregroundStyle(Theme.chalk)
                .frame(maxWidth: .infinity, alignment: .trailing)
            Text(label).font(Theme.label(11)).foregroundStyle(Theme.chalkMuted)
                .multilineTextAlignment(.center)
                .frame(width: 170)
            Text(a).font(Theme.number(14, weight: .semibold)).foregroundStyle(Theme.chalk)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: 1. Kunto

    private func formSection(_ h: Side, _ a: Side) -> some View {
        section("Kunto", hint: "uusin vasemmalla") {
            HStack(alignment: .top, spacing: 16) {
                formColumn(h, venueLabel: "Kotona")
                formColumn(a, venueLabel: "Vieraissa")
            }
        }
    }

    private func formColumn(_ s: Side, venueLabel: String) -> some View {
        VStack(spacing: 12) {
            Text(s.name).font(Theme.label(12, weight: .semibold)).foregroundStyle(Theme.chalk).lineLimit(1)
            chips(s.all, caption: "Viimeiset 5")
            chips(s.atVenue, caption: venueLabel)
        }
        .frame(maxWidth: .infinity)
    }

    private func chips(_ games: [TeamGame], caption: String) -> some View {
        let last = Array(games.suffix(5).reversed())
        let points = last.reduce(0) { $0 + ($1.code == "W" ? 3 : ($1.code == "D" ? 1 : 0)) }
        return VStack(spacing: 5) {
            Text(last.isEmpty ? caption : "\(caption) · \(points)/\(last.count * 3) p")
                .font(Theme.label(10))
                .foregroundStyle(Theme.chalkMuted)
            HStack(spacing: 4) {
                if last.isEmpty {
                    Text("–").font(Theme.label(12)).foregroundStyle(Theme.chalkMuted)
                }
                ForEach(last) { game in
                    ResultBadge(kind: game.code == "W" ? .win : (game.code == "D" ? .draw : .loss),
                                help: "\(game.match.home) \(game.match.homeGoals ?? 0)–\(game.match.awayGoals ?? 0) \(game.match.away)")
                }
            }
        }
    }

    // MARK: 2. Sarjasijoitus

    private func signed(_ value: Int) -> String { (value >= 0 ? "+" : "") + "\(value)" }

    @ViewBuilder
    private func standingSection(_ h: Side, _ a: Side) -> some View {
        if h.standing != nil || a.standing != nil {
            section("Sarjasijoitus") {
                VStack(spacing: 9) {
                    compareHead(h, a)
                    compare("Sija", h.standing.map { "\($0.position)." } ?? "–", a.standing.map { "\($0.position)." } ?? "–")
                    compare("Pisteet", h.standing.map { "\($0.points)" } ?? "–", a.standing.map { "\($0.points)" } ?? "–")
                    compare("Ottelut", h.standing.map { "\($0.played)" } ?? "–", a.standing.map { "\($0.played)" } ?? "–")
                    compare("Voitot–tasapelit–häviöt",
                            h.standing.map { "\($0.won)–\($0.drawn)–\($0.lost)" } ?? "–",
                            a.standing.map { "\($0.won)–\($0.drawn)–\($0.lost)" } ?? "–")
                    compare("Maalit", h.standing.map { "\($0.goalsFor):\($0.goalsAgainst)" } ?? "–",
                            a.standing.map { "\($0.goalsFor):\($0.goalsAgainst)" } ?? "–")
                    compare("Maaliero", h.standing.map { signed($0.goalDifference) } ?? "–",
                            a.standing.map { signed($0.goalDifference) } ?? "–")
                }
            }
        }
    }

    // MARK: 4. Keskinäiset ottelut

    private var headToHead: [Match] {
        (store.matches[match.league] ?? [])
            .filter { m in
                guard m.status == .finished, m.homeGoals != nil, m.awayGoals != nil else { return false }
                let straight = sameTeam(m.home, match.home) && sameTeam(m.away, match.away)
                let swapped = sameTeam(m.home, match.away) && sameTeam(m.away, match.home)
                return straight || swapped
            }
            .sorted { $0.date > $1.date }
    }

    private var headToHeadSection: some View {
        section("Keskinäiset ottelut", hint: "tämä kausi") {
            let list = headToHead
            if list.isEmpty {
                Text("Joukkueet eivät ole vielä kohdanneet tällä kaudella.")
                    .font(Theme.label(12))
                    .foregroundStyle(Theme.chalkMuted)
            } else {
                VStack(spacing: 8) {
                    ForEach(list) { m in
                        HStack(spacing: 10) {
                            Text(m.date.formatted(Date.FormatStyle(date: .numeric, time: .omitted).locale(Locale(identifier: "fi_FI"))))
                                .font(Theme.label(11))
                                .foregroundStyle(Theme.chalkMuted)
                                .frame(width: 80, alignment: .leading)
                            Text(m.home).font(Theme.label(12, weight: .semibold)).foregroundStyle(Theme.chalk)
                                .lineLimit(1).frame(maxWidth: .infinity, alignment: .trailing)
                            Text("\(m.homeGoals ?? 0) – \(m.awayGoals ?? 0)")
                                .font(Theme.number(14, weight: .bold)).foregroundStyle(Theme.floodlight)
                                .frame(width: 54)
                            Text(m.away).font(Theme.label(12, weight: .semibold)).foregroundStyle(Theme.chalk)
                                .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
        }
    }

    // MARK: 5. Kovimmat pelaajat

    @ViewBuilder
    private func topPlayersSection(_ h: Side, _ a: Side) -> some View {
        if !h.players.isEmpty || !a.players.isEmpty {
            section("Kovimmat pelaajat", hint: "ruudut: laukaukset maalia kohti, uusin vasemmalla") {
                HStack(alignment: .top, spacing: 14) {
                    playerColumn(h)
                    playerColumn(a)
                }
            }
        }
    }

    private func playerColumn(_ s: Side) -> some View {
        let top = Array(s.players.sorted { l, r in
            l.goals != r.goals ? l.goals > r.goals : l.shotsOnTarget > r.shotsOnTarget
        }.prefix(3))
        return VStack(spacing: 6) {
            Text(s.name).font(Theme.label(11, weight: .semibold)).foregroundStyle(Theme.chalkMuted).lineLimit(1)
            if top.isEmpty {
                Text("Ei pelaajatietoja").font(Theme.label(11)).foregroundStyle(Theme.chalkMuted)
            }
            ForEach(top) { player in playerRow(player) }
        }
        .frame(maxWidth: .infinity)
    }

    private func playerRow(_ p: Player) -> some View {
        let lines = store.matchLines[p.id] ?? []
        let recent = Array(lines.suffix(5).reversed())
        let fire = lines.isOnFire
        return Button { selectedPlayer = p } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(p.name).font(Theme.label(12, weight: .semibold)).foregroundStyle(Theme.chalk).lineLimit(1)
                        if fire {
                            Image(systemName: "flame.fill").font(.system(size: 11)).foregroundStyle(Color(hex: 0xFF8A3D))
                        }
                    }
                    Text("\(p.goals) maalia · \(p.shotsOnTarget)/\(p.shots) maalia kohti")
                        .font(Theme.label(10)).foregroundStyle(Theme.chalkMuted).lineLimit(1)
                }
                Spacer(minLength: 0)
                HStack(spacing: 2) {
                    ForEach(Array(recent.enumerated()), id: \.offset) { _, line in
                        Text("\(line.onTarget)")
                            .font(Theme.number(9, weight: .bold))
                            .foregroundStyle(line.onTarget == 0 ? Theme.chalkMuted : Color.black.opacity(0.85))
                            .frame(width: 16, height: 16)
                            .background(RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(line.onTarget == 0 ? Color.white.opacity(0.06)
                                      : (line.onTarget >= 2 ? Theme.floodlight : Theme.floodlight.opacity(0.45))))
                            .help("\(line.shortDate) · \(line.opponent): \(line.onTarget) maalia kohti, \(line.goals) maalia")
                    }
                }
            }
            .padding(8)
            .background(Theme.panelRaised.opacity(0.5), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Avaa pelaajan laukauskartta")
    }

    // MARK: 6. Maalitilastot

    private func pct(_ n: Int, _ d: Int) -> String { d == 0 ? "–" : Format.percent(Double(n) / Double(d) * 100) }
    private func avg(_ n: Int, _ d: Int) -> String { d == 0 ? "–" : Format.one(Double(n) / Double(d)) }

    private func goalValues(_ s: Side) -> [String] {
        let g = s.all
        let n = g.count
        return [
            avg(g.reduce(0) { $0 + $1.goalsFor }, n),
            avg(g.reduce(0) { $0 + $1.goalsAgainst }, n),
            pct(g.filter { $0.total > 2 }.count, n),
            pct(g.filter { $0.goalsFor > 0 && $0.goalsAgainst > 0 }.count, n),
            pct(g.filter { $0.goalsAgainst == 0 }.count, n)
        ]
    }

    @ViewBuilder
    private func goalSection(_ h: Side, _ a: Side) -> some View {
        if !h.all.isEmpty || !a.all.isEmpty {
            let hv = goalValues(h), av = goalValues(a)
            section("Maalitilastot", hint: "kaikki kauden ottelut") {
                VStack(spacing: 9) {
                    compareHead(h, a)
                    compare("Tehdyt maalit / ottelu", hv[0], av[0])
                    compare("Päästetyt maalit / ottelu", hv[1], av[1])
                    compare("Yli 2,5 maalia", hv[2], av[2])
                    compare("Molemmat tekevät (BTTS)", hv[3], av[3])
                    compare("Nollapelit", hv[4], av[4])
                }
            }
        }
    }

    // MARK: 7. Tilastoerot (pelaajien yhteenlasketut Understat-luvut)

    private func strengthValues(_ s: Side) -> [String] {
        let n = s.played
        let shots = s.players.reduce(0) { $0 + $1.shots }
        let onTarget = s.players.reduce(0) { $0 + $1.shotsOnTarget }
        let goals = s.players.reduce(0) { $0 + $1.goals }
        let xgs = s.players.compactMap(\.xG)
        let xg = xgs.isEmpty ? nil : xgs.reduce(0, +)
        func per(_ v: Double) -> String { n == 0 ? "–" : Format.one(v / Double(n)) }
        return [
            per(Double(shots)),
            per(Double(onTarget)),
            xg.map { per($0) } ?? "–",
            xg.map { (x: Double) -> String in
                let d = Double(goals) - x
                return (d >= 0 ? "+" : "") + Format.one(d)
            } ?? "–"
        ]
    }

    @ViewBuilder
    private func strengthSection(_ h: Side, _ a: Side) -> some View {
        if !h.players.isEmpty || !a.players.isEmpty {
            let hv = strengthValues(h), av = strengthValues(a)
            section("Tilastoerot", hint: "pelaajien yhteenlasketut luvut, Understat") {
                VStack(spacing: 9) {
                    compareHead(h, a)
                    compare("Laukauksia / ottelu", hv[0], av[0])
                    compare("Maalia kohti / ottelu", hv[1], av[1])
                    compare("xG / ottelu", hv[2], av[2])
                    compare("Maalit miinus xG", hv[3], av[3])
                }
            }
        }
    }
}
