import SwiftUI

private enum StandingsMode: Hashable {
    case table, overUnder, halfFull
}

/// Lajitteluperuste kaikissa kolmessa näkymässä.
private enum SortKey: Hashable {
    case position, team, played, won, drawn, lost, goalsFor, goalDifference, points
    case form, over, under, average, recentOver, firstHalf
    case combo(String)
}

/// Sarakeotsikko: teksti, leveys (nil = joustava), lajitteluperuste, vihje ja tasaus.
private struct Column {
    let title: String
    let width: CGFloat?
    let key: SortKey?
    let help: String
    var alignment: Alignment = .center
}

struct StandingsView: View {
    @Environment(AppStore.self) private var store
    @State private var mode: StandingsMode = .table
    @State private var venue: Venue = .all
    @State private var line: Double = 2.5
    @State private var selected: TeamSelection?
    @State private var sort: SortKey = .position
    @State private var ascending = true

    private enum Zone { case champions, europe, relegation, none }

    private var league: League { store.focusLeague }
    private var rows: [StandingRow] { store.standings[league.rawValue] ?? [] }
    private var matches: [Match] { store.matches[league.rawValue] ?? [] }

    var body: some View {
        let games = TeamGames(matches: matches, venue: venue)
        VStack(alignment: .leading, spacing: 12) {
            titleRow
            controls
            VStack(spacing: 0) {
                switch mode {
                case .table: tableContent(games)
                case .overUnder: overUnderContent(games)
                case .halfFull: halfFullContent(games)
                }
            }
            .panel()
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            if mode == .table { legend }
        }
        .sheet(item: $selected) { TeamDetailView(team: $0.name, league: league) }
        .onChange(of: mode) { _, newMode in
            // Jokaisella näkymällä on oma oletusjärjestys
            switch newMode {
            case .table: sort = .position; ascending = true
            case .overUnder: sort = .over; ascending = false
            case .halfFull: sort = .points; ascending = false
            }
        }
    }

    // MARK: Yläosa

    private var titleRow: some View {
        HStack(spacing: 8) {
            Text("\(league.flag) \(league.name)")
                .font(Theme.title(20))
                .foregroundStyle(Theme.chalk)
            if store.selectedLeague == nil {
                Text("· valitse sarja yläpalkista")
                    .font(Theme.label(12))
                    .foregroundStyle(Theme.chalkMuted)
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 14) {
            ThemedToggle(options: [(value: StandingsMode.table, label: "Taulukko"),
                                   (value: StandingsMode.overUnder, label: "Yli/Alle"),
                                   (value: StandingsMode.halfFull, label: "HT/FT")],
                         selection: $mode)
            ThemedToggle(options: Venue.allCases.map { (value: $0, label: $0.title) }, selection: $venue)
            if mode == .overUnder {
                ThemedToggle(options: [0.5, 1.5, 2.5, 3.5, 4.5, 5.5, 6.5].map { (value: $0, label: String(format: "%.1f", $0)) },
                             selection: $line)
                    .accessibilityLabel("Maalirajan valinta")
            }
            Spacer()
        }
    }

    // MARK: Otsikot ja lajittelu

    private func headerBar(_ columns: [Column]) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(columns.enumerated()), id: \.offset) { _, column in
                if let key = column.key {
                    sortHead(column, key)
                } else {
                    plainHead(column)
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private func plainHead(_ column: Column) -> some View {
        Text(column.title)
            .font(Theme.label(11, weight: .semibold))
            .foregroundStyle(Theme.chalkMuted)
            .frame(maxWidth: column.width == nil ? .infinity : nil, alignment: column.alignment)
            .frame(width: column.width, height: 36, alignment: column.alignment)
            .help(column.help)
    }

    private func sortHead(_ column: Column, _ key: SortKey) -> some View {
        Button { toggleSort(key) } label: {
            HStack(spacing: 2) {
                Text(column.title)
                if sort == key {
                    Image(systemName: ascending ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                }
            }
            .font(Theme.label(11, weight: .semibold))
            .foregroundStyle(sort == key ? Theme.floodlight : Theme.chalkMuted)
            .frame(maxWidth: column.width == nil ? .infinity : nil, alignment: column.alignment)
            .frame(width: column.width, height: 36, alignment: column.alignment)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(column.help)
        .accessibilityLabel("\(column.title), \(column.help)")
    }

    private func toggleSort(_ key: SortKey) {
        if sort == key {
            ascending.toggle()
        } else {
            sort = key
            ascending = key == .team || key == .position
        }
    }

    /// Vertaa kahta lukuarvoa valitun suunnan mukaan; nil = tasan, jolloin käytetään toissijaista järjestystä.
    private func ordered(_ a: Double, _ b: Double) -> Bool? {
        a == b ? nil : (ascending ? a < b : a > b)
    }

    private func formPoints(_ games: [TeamGame]) -> Double {
        Double(games.suffix(5).reduce(0) { $0 + ($1.code == "W" ? 3 : ($1.code == "D" ? 1 : 0)) })
    }

    // MARK: Taulukko

    /// Kokonaistaulukko tulee rajapinnasta (virallinen järjestys); kotona/vieraissa lasketaan otteluista.
    private func displayRows(_ games: TeamGames) -> [StandingRow] {
        if venue == .all && !rows.isEmpty { return rows }
        let names = rows.isEmpty ? games.teamNames : rows.map(\.team)
        let computed = names.map { name -> (String, TeamRecord) in
            (name, TeamRecord(games: games.games(for: name)))
        }
        let sorted = computed.sorted { l, r in
            let a = l.1, b = r.1
            if a.points != b.points { return a.points > b.points }
            if a.goalDifference != b.goalDifference { return a.goalDifference > b.goalDifference }
            if a.goalsFor != b.goalsFor { return a.goalsFor > b.goalsFor }
            return l.0 < r.0
        }
        return sorted.enumerated().map { index, entry in
            let r = entry.1
            return StandingRow(position: index + 1, team: entry.0, played: r.played, won: r.won, drawn: r.drawn,
                               lost: r.lost, goalsFor: r.goalsFor, goalsAgainst: r.goalsAgainst,
                               points: r.points, form: [])
        }
    }

    private func sortedTable(_ list: [StandingRow], _ games: TeamGames) -> [StandingRow] {
        func value(_ row: StandingRow) -> Double {
            switch sort {
            case .played: return Double(row.played)
            case .won: return Double(row.won)
            case .drawn: return Double(row.drawn)
            case .lost: return Double(row.lost)
            case .goalsFor: return Double(row.goalsFor)
            case .goalDifference: return Double(row.goalDifference)
            case .points: return Double(row.points)
            case .form: return formPoints(games.games(for: row.team))
            default: return Double(row.position)
            }
        }
        return list.sorted { l, r in
            if sort == .team { return ascending ? l.team < r.team : l.team > r.team }
            if let result = ordered(value(l), value(r)) { return result }
            return l.position < r.position
        }
    }

    @ViewBuilder
    private func tableContent(_ games: TeamGames) -> some View {
        let list = sortedTable(displayRows(games), games)
        headerBar([
            Column(title: "#", width: 40, key: .position, help: "Sija sarjataulukossa"),
            Column(title: "Joukkue", width: nil, key: .team, help: "Joukkueen nimi", alignment: .leading),
            Column(title: "O", width: 44, key: .played, help: "Pelatut ottelut"),
            Column(title: "V", width: 44, key: .won, help: "Voitot"),
            Column(title: "T", width: 44, key: .drawn, help: "Tasapelit"),
            Column(title: "H", width: 44, key: .lost, help: "Tappiot"),
            Column(title: "Maalit", width: 80, key: .goalsFor, help: "Tehdyt ja päästetyt maalit (lajittelu tehtyjen mukaan)"),
            Column(title: "ME", width: 54, key: .goalDifference, help: "Maaliero: tehdyt maalit miinus päästetyt"),
            Column(title: "P", width: 58, key: .points, help: "Pisteet (voitto 3, tasapeli 1)"),
            Column(title: "Kunto", width: 200, key: .form,
                   help: "Viiden viimeisimmän ottelun tulokset vanhimmasta uusimpaan. ? = seuraava ottelu",
                   alignment: .leading)
        ])
        Divider().overlay(Theme.stroke)
        if list.isEmpty {
            emptyMessage("Sarjataulukkoa ei ole vielä saatavilla")
        } else {
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(list) { row in standingRow(row, games) }
                }
            }
        }
    }

    private func head(_ title: String, _ width: CGFloat?, _ alignment: Alignment = .center) -> some View {
        Text(title)
            .font(Theme.label(11, weight: .semibold))
            .foregroundStyle(Theme.chalkMuted)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: alignment)
            .frame(width: width, height: 36, alignment: alignment)
    }

    private func standingRow(_ row: StandingRow, _ games: TeamGames) -> some View {
        let rowZone = venue == .all ? zone(for: row.position) : Zone.none
        return HStack(spacing: 0) {
            Text("\(row.position)").font(Theme.number(14, weight: .semibold)).foregroundStyle(Theme.chalk).frame(width: 40)
            teamCell(row.team)
            cell("\(row.played)", 44); cell("\(row.won)", 44); cell("\(row.drawn)", 44); cell("\(row.lost)", 44)
            cell("\(row.goalsFor):\(row.goalsAgainst)", 80)
            Text(row.goalDifference > 0 ? "+\(row.goalDifference)" : "\(row.goalDifference)")
                .font(Theme.number(14))
                .foregroundStyle(row.goalDifference > 0 ? Theme.positive : (row.goalDifference < 0 ? Theme.negative : Theme.chalkMuted))
                .frame(width: 54)
            Text("\(row.points)").font(Theme.number(15, weight: .bold)).foregroundStyle(Theme.floodlight).frame(width: 58)
            formStrip(games.games(for: row.team), next: games.next(for: row.team))
                .frame(width: 200, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .frame(height: 46)
        .overlay(alignment: .leading) { Rectangle().fill(color(for: rowZone)).frame(width: 3) }
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.stroke).frame(height: 1) }
        .openable { selected = TeamSelection(name: row.team) }
    }

    private func teamCell(_ team: String) -> some View {
        HStack(spacing: 10) {
            TeamBadge(name: team, size: 34)
            Text(team).font(Theme.label(14, weight: .semibold)).foregroundStyle(Theme.chalk)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func cell(_ text: String, _ width: CGFloat) -> some View {
        Text(text).font(Theme.number(14)).foregroundStyle(Theme.chalk).frame(width: width)
    }

    /// "?" = seuraava ottelu (vihjeessä), sen jälkeen viisi viimeisintä tulosta vanhimmasta uusimpaan.
    private func formStrip(_ games: [TeamGame], next: Match?) -> some View {
        HStack(spacing: 4) {
            ResultBadge(kind: .unknown, help: nextText(next))
            ForEach(games.suffix(5)) { game in
                ResultBadge(kind: game.code == "W" ? .win : (game.code == "D" ? .draw : .loss), help: resultText(game))
            }
        }
    }

    // MARK: Yli/Alle

    private struct OverUnderRow: Identifiable {
        let team: String
        let games: [TeamGame]
        let over: Int
        let recentOver: Int
        var id: String { team }
        var played: Int { games.count }
        var under: Int { played - over }
        var goalsFor: Int { games.reduce(0) { $0 + $1.goalsFor } }
        var goalsAgainst: Int { games.reduce(0) { $0 + $1.goalsAgainst } }
        var average: Double { played == 0 ? 0 : Double(goalsFor + goalsAgainst) / Double(played) }
    }

    private func sortedOverUnder(_ list: [OverUnderRow]) -> [OverUnderRow] {
        func value(_ row: OverUnderRow) -> Double {
            switch sort {
            case .played: return Double(row.played)
            case .under: return Double(row.under)
            case .goalsFor: return Double(row.goalsFor)
            case .average: return row.average
            case .recentOver: return Double(row.recentOver)
            default: return Double(row.over)
            }
        }
        return list.sorted { l, r in
            if sort == .team { return ascending ? l.team < r.team : l.team > r.team }
            if let result = ordered(value(l), value(r)) { return result }
            if l.over != r.over { return l.over > r.over }
            if l.average != r.average { return l.average > r.average }
            return l.team < r.team
        }
    }

    @ViewBuilder
    private func overUnderContent(_ games: TeamGames) -> some View {
        let names = rows.isEmpty ? games.teamNames : rows.map(\.team)
        let limit = String(format: "%.1f", line)
        let list = sortedOverUnder(names.map { name -> OverUnderRow in
            let g = games.games(for: name)
            return OverUnderRow(team: name, games: g,
                                over: g.filter { Double($0.total) > line }.count,
                                recentOver: g.suffix(5).filter { Double($0.total) > line }.count)
        })
        headerBar([
            Column(title: "#", width: 40, key: nil, help: "Sija nykyisessä järjestyksessä"),
            Column(title: "Joukkue", width: nil, key: .team, help: "Joukkueen nimi", alignment: .leading),
            Column(title: "OTT", width: 44, key: .played, help: "Pelatut ottelut"),
            Column(title: "Yli", width: 44, key: .over, help: "Otteluita, joissa maaleja tehtiin yli \(limit)"),
            Column(title: "Alle", width: 44, key: .under, help: "Otteluita, joissa maaleja tehtiin alle \(limit)"),
            Column(title: "M", width: 80, key: .goalsFor, help: "Tehdyt ja päästetyt maalit (lajittelu tehtyjen mukaan)"),
            Column(title: "M/O", width: 60, key: .average, help: "Maaleja keskimäärin per ottelu (molempien joukkueiden maalit yhteensä)"),
            Column(title: "Viimeiset 5", width: 200, key: .recentOver,
                   help: "Viiden viimeisimmän ottelun yli/alle \(limit): + = yli, − = alle. ? = seuraava ottelu",
                   alignment: .leading)
        ])
        Divider().overlay(Theme.stroke)
        if list.allSatisfy({ $0.played == 0 }) {
            emptyMessage("Pelattuja otteluita ei ole vielä saatavilla")
        } else {
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(Array(list.enumerated()), id: \.element.id) { index, row in
                        HStack(spacing: 0) {
                            Text("\(index + 1)").font(Theme.number(14, weight: .semibold)).foregroundStyle(Theme.chalk).frame(width: 40)
                            teamCell(row.team)
                            cell("\(row.played)", 44)
                            cell("\(row.over)", 44)
                            cell("\(row.under)", 44)
                            cell("\(row.goalsFor):\(row.goalsAgainst)", 80)
                            Text(String(format: "%.1f", row.average))
                                .font(Theme.number(14, weight: .semibold)).foregroundStyle(Theme.floodlight).frame(width: 60)
                            overUnderStrip(row.games, next: games.next(for: row.team))
                                .frame(width: 200, alignment: .leading)
                        }
                        .padding(.horizontal, 16)
                        .frame(height: 46)
                        .overlay(alignment: .bottom) { Rectangle().fill(Theme.stroke).frame(height: 1) }
                        .openable { selected = TeamSelection(name: row.team) }
                    }
                }
            }
        }
    }

    private func overUnderStrip(_ games: [TeamGame], next: Match?) -> some View {
        HStack(spacing: 4) {
            ResultBadge(kind: .unknown, help: nextText(next))
            ForEach(games.suffix(5)) { game in
                ResultBadge(kind: Double(game.total) > line ? .over : .under,
                            help: "\(resultText(game)) · maaleja yhteensä \(game.total)")
            }
        }
    }

    // MARK: HT/FT

    private static let htftColumns = [("V/V", "WW"), ("V/T", "WD"), ("V/H", "WL"),
                                      ("T/V", "DW"), ("T/T", "DD"), ("T/H", "DL"),
                                      ("H/V", "LW"), ("H/T", "LD"), ("H/H", "LL")]

    private struct HTFTRow {
        let team: String
        let games: [TeamGame]
        let record: TeamRecord
        let counts: [String: Int]
        /// Viimeisen viiden ottelun ensimmäisen jakson omat maalit (nil = puoliaikatulos puuttuu).
        let firstHalf: [Int?]
        var firstHalfTotal: Int { firstHalf.compactMap { $0 }.reduce(0, +) }
    }

    @ViewBuilder
    private func halfFullContent(_ games: TeamGames) -> some View {
        let names = rows.isEmpty ? games.teamNames : rows.map(\.team)
        if !games.hasHalfTime {
            emptyMessage("Puoliaikatuloksia ei ole saatavilla tälle sarjalle")
        } else {
            let list = sortedHTFT(names.map { name -> HTFTRow in
                let g = games.games(for: name)
                return HTFTRow(team: name, games: g, record: TeamRecord(games: g), counts: htftCounts(g),
                               firstHalf: g.suffix(5).map { $0.halfFor })
            })
            headerBar(
                [Column(title: "#", width: 40, key: nil, help: "Sija nykyisessä järjestyksessä"),
                 Column(title: "Joukkue", width: nil, key: .team, help: "Joukkueen nimi", alignment: .leading),
                 Column(title: "OTT", width: 44, key: .played, help: "Pelatut ottelut")]
                + Self.htftColumns.map { Column(title: $0.0, width: 48, key: .combo($0.1), help: comboHelp($0.1)) }
                + [Column(title: "PIS", width: 52, key: .points, help: "Pisteet (voitto 3, tasapeli 1)"),
                   Column(title: "1. jakso", width: 170, key: .firstHalf,
                          help: "Joukkueen tekemät maalit ensimmäisellä puoliajalla viimeisessä viidessä ottelussa: summa ja ottelukohtaiset luvut",
                          alignment: .leading)]
            )
            Divider().overlay(Theme.stroke)
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(Array(list.enumerated()), id: \.element.team) { index, entry in
                        let best = entry.counts.values.max() ?? 0
                        HStack(spacing: 0) {
                            Text("\(index + 1)").font(Theme.number(14, weight: .semibold)).foregroundStyle(Theme.chalk).frame(width: 40)
                            teamCell(entry.team)
                            cell("\(entry.record.played)", 44)
                            ForEach(Self.htftColumns, id: \.0) { column in
                                let value = entry.counts[column.1] ?? 0
                                Text("\(value)")
                                    .font(Theme.number(14, weight: value == best && value > 0 ? .bold : .regular))
                                    .foregroundStyle(value == 0 ? Theme.chalkMuted : Theme.chalk)
                                    .frame(width: 30, height: 24)
                                    .background(RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        .fill(value == best && value > 0 ? Theme.panelRaised : Color.clear))
                                    .frame(width: 48)
                                    .help("\(entry.team): \(comboHelp(column.1)) – \(value) ottelua")
                                    .accessibilityLabel("\(column.0) \(value)")
                            }
                            Text("\(entry.record.points)").font(Theme.number(15, weight: .bold))
                                .foregroundStyle(Theme.floodlight).frame(width: 52)
                            firstHalfStrip(entry).frame(width: 170, alignment: .leading)
                        }
                        .padding(.horizontal, 16)
                        .frame(height: 46)
                        .overlay(alignment: .bottom) { Rectangle().fill(Theme.stroke).frame(height: 1) }
                        .openable { selected = TeamSelection(name: entry.team) }
                    }
                }
            }
        }
    }

    /// Ensimmäisen jakson maalit viimeisistä viidestä: summa ja ottelukohtaiset luvut vanhimmasta uusimpaan.
    private func firstHalfStrip(_ entry: HTFTRow) -> some View {
        HStack(spacing: 4) {
            Text("\(entry.firstHalfTotal)")
                .font(Theme.number(15, weight: .bold)).foregroundStyle(Theme.floodlight)
                .frame(width: 26, alignment: .leading)
            ForEach(Array(entry.games.suffix(5).enumerated()), id: \.offset) { _, game in
                let goals = game.halfFor
                Text(goals.map { "\($0)" } ?? "–")
                    .font(Theme.number(12, weight: .semibold))
                    .foregroundStyle(goals == nil ? Theme.chalkMuted : (goals == 0 ? Theme.chalkMuted : Theme.chalk))
                    .frame(width: 22, height: 22)
                    .background(RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill((goals ?? 0) > 0 ? Theme.panelRaised : Color.clear))
                    .help(goals.map { "\(game.opponent): \($0) maalia ensimmäisellä jaksolla" } ?? "Puoliaikatulos ei tiedossa")
            }
        }
    }

    private func sortedHTFT(_ list: [HTFTRow]) -> [HTFTRow] {
        func value(_ row: HTFTRow) -> Double {
            switch sort {
            case .played: return Double(row.record.played)
            case .firstHalf: return Double(row.firstHalfTotal)
            case .combo(let key): return Double(row.counts[key] ?? 0)
            default: return Double(row.record.points)
            }
        }
        return list.sorted { l, r in
            if sort == .team { return ascending ? l.team < r.team : l.team > r.team }
            if let result = ordered(value(l), value(r)) { return result }
            if l.record.points != r.record.points { return l.record.points > r.record.points }
            if l.record.goalDifference != r.record.goalDifference { return l.record.goalDifference > r.record.goalDifference }
            return l.team < r.team
        }
    }

    /// "WD" -> "Johti puoliajalla, ottelu päättyi tasan".
    private func comboHelp(_ code: String) -> String {
        let chars = Array(code)
        guard chars.count == 2 else { return code }
        let half: String
        switch chars[0] {
        case "W": half = "Johti puoliajalla"
        case "D": half = "Tasan puoliajalla"
        default: half = "Oli tappiolla puoliajalla"
        }
        let full: String
        switch chars[1] {
        case "W": full = "voitti ottelun"
        case "D": full = "ottelu päättyi tasan"
        default: full = "hävisi ottelun"
        }
        return "\(half), \(full)"
    }

    /// Avainten muoto: puoliaika + loppu ("WD" = johti puoliajalla, tasapeli lopussa).
    private func htftCounts(_ games: [TeamGame]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for game in games {
            guard let half = game.halfCode else { continue }
            counts[half + game.code, default: 0] += 1
        }
        return counts
    }

    // MARK: Tekstit

    private func emptyMessage(_ text: String) -> some View {
        Text(text)
            .font(Theme.label(14))
            .foregroundStyle(Theme.chalkMuted)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, minHeight: 200)
    }

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

    private func resultText(_ game: TeamGame) -> String {
        let m = game.match
        return "\(m.home) \(m.homeGoals ?? 0)–\(m.awayGoals ?? 0) \(m.away) · \(Self.shortDate.string(from: m.date))"
    }

    private func nextText(_ match: Match?) -> String {
        guard let match else { return "Ei tulevia otteluita" }
        return "Seuraava ottelu: \(match.home) – \(match.away), \(Self.longDate.string(from: match.date))"
    }

    // MARK: Selite ja vyöhykkeet

    private var legend: some View {
        HStack(spacing: 18) {
            if league.zoneStyle == .europeanCup {
                legendItem(Theme.positive, "Suoraan jatkoon")
                legendItem(Theme.european, "Jatkopelit")
            } else if league.zoneStyle == .none {
                EmptyView()
            } else {
                legendItem(Theme.positive, "Mestarien liiga")
                legendItem(Theme.european, "Eurooppa-sarjat")
                legendItem(Theme.negative, "Putoamisalue")
            }
            Spacer()
            Text("V = voitto · T = tasapeli · H = häviö · ? = seuraava ottelu")
                .font(Theme.label(11)).foregroundStyle(Theme.chalkMuted)
        }
    }

    private func legendItem(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 1).fill(color).frame(width: 3, height: 12)
            Text(text).font(Theme.label(11)).foregroundStyle(Theme.chalkMuted)
        }
    }

    private func zone(for position: Int) -> Zone {
        let count = rows.count
        switch league.zoneStyle {
        case .europeanCup:
            if position <= 8 { return .champions }
            return position <= 24 ? .europe : .none
        case .none:
            return .none
        case .domestic:
            break
        }
        if position <= 4 { return .champions }
        if position <= 6 { return .europe }
        if count > 0 && position > count - 3 { return .relegation }
        return .none
    }

    private func color(for zone: Zone) -> Color {
        switch zone {
        case .champions: return Theme.positive
        case .europe: return Theme.european
        case .relegation: return Theme.negative
        case .none: return .clear
        }
    }
}

private extension View {
    /// Rivi avaa joukkuenäkymän napautettaessa.
    func openable(_ action: @escaping () -> Void) -> some View {
        self
            .contentShape(Rectangle())
            .onTapGesture(perform: action)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Avaa joukkueen viimeisimmät ottelut")
    }
}

/// Pieni värillinen merkki: V/T/H, +/− tai ? (seuraava ottelu).
struct ResultBadge: View {
    enum Kind { case win, draw, loss, over, under, unknown }

    let kind: Kind
    let help: String

    private var symbol: String {
        switch kind {
        case .win: return "V"
        case .draw: return "T"
        case .loss: return "H"
        case .over: return "+"
        case .under: return "−"
        case .unknown: return "?"
        }
    }

    private var fill: Color {
        switch kind {
        case .win, .over: return Theme.positive
        case .draw: return Theme.floodlight
        case .loss, .under: return Theme.negative
        case .unknown: return Theme.panelRaised
        }
    }

    var body: some View {
        Text(symbol)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .foregroundStyle(kind == .unknown ? Theme.chalkMuted : Theme.background)
            .frame(width: 26, height: 24)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(fill))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(kind == .unknown ? Theme.stroke : Color.clear, lineWidth: 1))
            .help(help)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(help)
    }
}
