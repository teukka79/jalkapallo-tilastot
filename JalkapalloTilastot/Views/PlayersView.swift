import SwiftUI

enum PlayerSort: String, Codable {
    case name, team, appearances, goals, shots, onTarget, onTargetOutside, outside, onTargetPercent, perGame, xG, xGDiff
}

/// Sarakkeiden leveydet jaetaan otsikon ja rivien kesken, ettei mikään karkaa kohdalta.
private enum Col {
    static let nationality: CGFloat = 48
    static let position: CGFloat = 90
    static let appearances: CGFloat = 56
    static let goals: CGFloat = 56
    static let shots: CGFloat = 76
    static let onTarget: CGFloat = 76
    static let onTargetOutside: CGFloat = 104
    static let outside: CGFloat = 94
    static let percent: CGFloat = 66
    static let perGame: CGFloat = 62
    static let xG: CGFloat = 52
    static let xGDiff: CGFloat = 70
    static let mix: CGFloat = 80
    static let stars: CGFloat = 84
}

struct PlayersView: View {
    @Environment(AppStore.self) private var store
    @AppStorage("showXGColumns") private var showXG = true
    @State private var search = ""
    @State private var team: String?
    @State private var position: String?
    @State private var watchOnly = false
    @State private var ratedOnly = false
    @State private var minApps = 0
    @State private var minMinutes = 0
    @State private var sortKey: PlayerSort = .goals
    @State private var ascending = false
    @State private var selected: Player?
    @State private var savingView = false
    @State private var newViewName = ""

    var body: some View {
        let rows = filteredRows

        VStack(spacing: 12) {
            if store.playersAreSample { sampleBanner }
            filterBar(count: rows.count)
            VStack(spacing: 0) {
                if rows.isEmpty {
                    headerRow
                    Divider().overlay(Theme.stroke)
                    emptyState
                } else {
                    // Otsikko on osa vieritettävää aluetta, jotta sarakkeet pysyvät kohdillaan vierityspalkin kanssa
                    ScrollView {
                        LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                            Section {
                                ForEach(rows) { player in
                                    PlayerRow(player: player, sortKey: sortKey, showXG: showXG,
                                              rating: store.rating(for: player.id),
                                              watched: store.isWatched(player.id),
                                              hasNote: store.hasNote(player.id),
                                              onRate: { stars in store.setRating(player.id, stars) },
                                              onOpen: { selected = player })
                                }
                            } header: {
                                VStack(spacing: 0) {
                                    headerRow
                                    Divider().overlay(Theme.stroke)
                                }
                                .background(Theme.panel)
                            }
                        }
                    }
                }
            }
            .panel()
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .sheet(item: $selected) { PlayerDetailView(player: $0) }
        .alert("Tallenna näkymä", isPresented: $savingView) {
            TextField("Nimi", text: $newViewName)
            Button("Tallenna") { saveCurrentView() }
            Button("Peruuta", role: .cancel) {}
        } message: {
            Text("Tallentaa nykyiset rajaukset ja lajittelun.")
        }
    }

    // MARK: Suodatus ja lajittelu

    private var scoped: [Player] {
        guard let league = store.selectedLeague else { return store.players }
        return store.players.filter { $0.league == league.rawValue }
    }

    private var teamOptions: [String] {
        Array(Set(scoped.map { $0.team })).sorted()
    }

    private var filteredRows: [Player] {
        var list = scoped
        if let team { list = list.filter { $0.team == team } }
        if let position { list = list.filter { $0.position.rawValue == position } }
        if watchOnly { list = list.filter { store.isWatched($0.id) } }
        if ratedOnly { list = list.filter { store.rating(for: $0.id) > 0 } }
        if minApps > 0 { list = list.filter { $0.appearances >= minApps } }
        if minMinutes > 0 { list = list.filter { ($0.minutes ?? 0) >= minMinutes } }
        let query = search.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty {
            list = list.filter { $0.name.localizedCaseInsensitiveContains(query)
                || $0.team.localizedCaseInsensitiveContains(query) }
        }
        return list.sorted { a, b in
            switch sortKey {
            case .name: return ascending ? a.name < b.name : a.name > b.name
            case .team: return ascending ? a.team < b.team : a.team > b.team
            default:
                let x = sortValue(a), y = sortValue(b)
                if x != y { return ascending ? x < y : x > y }
                if a.goals != b.goals { return a.goals > b.goals }
                return a.name < b.name
            }
        }
    }

    private func sortValue(_ p: Player) -> Double {
        switch sortKey {
        case .appearances: return Double(p.appearances)
        case .goals: return Double(p.goals)
        case .shots: return Double(p.shots)
        case .onTarget: return Double(p.shotsOnTarget)
        case .onTargetOutside: return Double(p.shotsOnTargetOutsideBox)
        case .outside: return Double(p.shotsOutsideBox)
        case .onTargetPercent: return p.onTargetPercent
        case .perGame: return p.shotsPerGame
        case .xG: return p.xG ?? -1
        case .xGDiff: return p.xGDifference ?? -999
        case .name, .team: return 0
        }
    }

    // MARK: Näkymät

    private func apply(_ saved: SavedPlayerView) {
        store.selectedLeague = saved.league.flatMap { League(rawValue: $0) }
        team = saved.team
        position = saved.position
        minApps = saved.minApps
        minMinutes = saved.minMinutes
        watchOnly = saved.watchOnly
        ratedOnly = saved.ratedOnly
        sortKey = PlayerSort(rawValue: saved.sort) ?? .goals
        ascending = saved.ascending
    }

    private func saveCurrentView() {
        let name = newViewName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        store.saveView(SavedPlayerView(name: name, league: store.selectedLeague?.rawValue, team: team,
                                       position: position, minApps: minApps, minMinutes: minMinutes,
                                       watchOnly: watchOnly, ratedOnly: ratedOnly,
                                       sort: sortKey.rawValue, ascending: ascending))
    }

    private func resetFilters() {
        search = ""; team = nil; position = nil
        watchOnly = false; ratedOnly = false; minApps = 0; minMinutes = 0
    }

    // MARK: Osat

    private var sampleBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle.fill").foregroundStyle(Theme.floodlight)
            Text("Esimerkkidata: pelaajat ja luvut on generoitu havainnollistamiseen. Paina Päivitä pelaajat tai tuo omat tilastot asetuksista.")
                .font(Theme.label(12))
                .foregroundStyle(Theme.chalkMuted)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.floodlight.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.floodlight.opacity(0.25), lineWidth: 1))
    }

    private func filterBar(count: Int) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.chalkMuted)
                    TextField("Hae pelaajaa tai joukkuetta", text: $search)
                        .textFieldStyle(.plain)
                        .font(Theme.label(13))
                        .foregroundStyle(Theme.chalk)
                }
                .padding(.horizontal, 10)
                .frame(width: 250, height: 32)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.panelRaised))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))

                FilterMenu(title: "Kaikki joukkueet", options: teamOptions, selection: $team)
                FilterMenu(title: "Kaikki asemat", options: Position.allCases.map { $0.rawValue }, selection: $position)
                ThresholdMenu(title: "Ottelut", options: [3, 5, 8, 10, 15], value: $minApps)
                ThresholdMenu(title: "Minuutit", options: [90, 270, 450, 900, 1350], value: $minMinutes)

                Spacer()
                Text("\(count) pelaajaa")
                    .font(Theme.label(12))
                    .foregroundStyle(Theme.chalkMuted)
            }

            HStack(spacing: 10) {
                viewsMenu

                Button { watchOnly.toggle() } label: {
                    Label("Seurattavat", systemImage: watchOnly ? "bookmark.fill" : "bookmark")
                        .foregroundStyle(watchOnly ? Theme.floodlight : Theme.chalk)
                }
                .buttonStyle(GhostButtonStyle())

                Button { ratedOnly.toggle() } label: {
                    Label("Arvostellut", systemImage: ratedOnly ? "star.fill" : "star")
                        .foregroundStyle(ratedOnly ? Theme.floodlight : Theme.chalk)
                }
                .buttonStyle(GhostButtonStyle())

                Button { showXG.toggle() } label: {
                    Label("xG", systemImage: showXG ? "checkmark.square.fill" : "square")
                        .foregroundStyle(showXG ? Theme.floodlight : Theme.chalk)
                }
                .buttonStyle(GhostButtonStyle())
                .help("Näytä tai piilota xG-sarakkeet")

                Spacer()
            }
        }
        .onChange(of: store.selectedLeague) { _, _ in
            if let current = team, !teamOptions.contains(current) { team = nil }
        }
    }

    private var viewsMenu: some View {
        Menu {
            if store.savedViews.isEmpty {
                Text("Ei tallennettuja näkymiä")
            }
            ForEach(store.savedViews) { saved in
                Button(saved.name) { apply(saved) }
            }
            Divider()
            Button("Tallenna nykyinen näkymä…") {
                newViewName = ""
                savingView = true
            }
            if !store.savedViews.isEmpty {
                Menu("Poista näkymä") {
                    ForEach(store.savedViews) { saved in
                        Button(saved.name, role: .destructive) { store.deleteView(saved.id) }
                    }
                }
            }
            Divider()
            Button("Tyhjennä rajaukset") { resetFilters() }
        } label: {
            MenuLabel(text: "Näkymät", icon: "rectangle.stack")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private var headerRow: some View {
        HStack(spacing: 0) {
            sortButton("Pelaaja", .name, width: nil, alignment: .leading)
            sortButton("Maa", nil, width: Col.nationality)
            sortButton("Asema", nil, width: Col.position)
            sortButton("Ottelut", .appearances, width: Col.appearances)
            sortButton("Maalit", .goals, width: Col.goals)
            sortButton("Laukaukset", .shots, width: Col.shots)
            sortButton("Maalia kohti", .onTarget, width: Col.onTarget)
            sortButton("Maalia kohti\nulkopuolelta", .onTargetOutside, width: Col.onTargetOutside,
                       help: "Maalia kohti -laukaukset rangaistusalueen ulkopuolelta")
            sortButton("Laukaukset\nulkopuolelta", .outside, width: Col.outside,
                       help: "Kaikki laukaukset rangaistusalueen ulkopuolelta")
            sortButton("Maalia\nkohti %", .onTargetPercent, width: Col.percent)
            sortButton("Lauk.\n/ ott.", .perGame, width: Col.perGame)
            if showXG {
                sortButton("xG", .xG, width: Col.xG, help: "Maaliodottama: laukausten laadusta laskettu odotettu maalimäärä")
                sortButton("Maalit\n– xG", .xGDiff, width: Col.xGDiff,
                           help: "Maalit miinus xG. Positiivinen = tehnyt enemmän kuin laukausten laatu antaisi odottaa")
            }
            sortButton("Jakauma", nil, width: Col.mix)
            sortButton("Tähdet", nil, width: Col.stars)
        }
        .padding(.horizontal, 16)
    }

    private func sortButton(_ title: String, _ key: PlayerSort?, width: CGFloat?,
                            alignment: Alignment = .center, help: String? = nil) -> some View {
        let active = key != nil && sortKey == key
        return Button {
            guard let key else { return }
            if sortKey == key {
                ascending.toggle()
            } else {
                sortKey = key
                ascending = (key == .name || key == .team)
            }
        } label: {
            HStack(spacing: 3) {
                Text(title)
                    .multilineTextAlignment(alignment == .leading ? .leading : .center)
                    .lineLimit(2)
                if active {
                    Image(systemName: ascending ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                }
            }
            .font(Theme.label(11, weight: .semibold))
            .foregroundStyle(active ? Theme.floodlight : Theme.chalkMuted)
            .frame(minWidth: width == nil ? 220 : nil, maxWidth: width == nil ? .infinity : nil, alignment: alignment)
            .frame(width: width, height: 42, alignment: alignment)
        }
        .buttonStyle(.plain)
        .help(help ?? title.replacingOccurrences(of: "\n", with: " "))
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "sportscourt").font(.system(size: 28)).foregroundStyle(Theme.chalkMuted)
            Text("Ei pelaajia valituilla rajauksilla").font(Theme.label(14, weight: .semibold)).foregroundStyle(Theme.chalk)
            if let league = store.selectedLeague, !league.hasPlayerStats, !store.playersAreSample {
                Text("\(league.name): pelaajakohtaisia laukaustilastoja ei ole saatavilla. Taulukko ja ottelut löytyvät omilta välilehdiltään.")
                    .font(Theme.label(12)).foregroundStyle(Theme.chalkMuted)
                    .multilineTextAlignment(.center).frame(maxWidth: 380)
            }
            Button("Tyhjennä rajaukset") { resetFilters() }
                .buttonStyle(GhostButtonStyle())
        }
        .frame(maxWidth: .infinity, minHeight: 220)
    }
}

private struct PlayerRow: View {
    let player: Player
    let sortKey: PlayerSort
    let showXG: Bool
    let rating: Int
    let watched: Bool
    let hasNote: Bool
    let onRate: (Int) -> Void
    let onOpen: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 10) {
                TeamBadge(name: player.team, size: 38)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(player.name)
                            .font(Theme.label(14, weight: .semibold))
                            .foregroundStyle(Theme.chalk)
                        if watched {
                            Image(systemName: "bookmark.fill").font(.system(size: 10)).foregroundStyle(Theme.floodlight)
                        }
                        if hasNote {
                            Image(systemName: "text.bubble.fill").font(.system(size: 10)).foregroundStyle(Theme.chalkMuted)
                        }
                    }
                    Text("\(player.leagueFlag) \(player.team)")
                        .font(Theme.label(11))
                        .foregroundStyle(Theme.chalkMuted)
                }
                Spacer(minLength: 0)
            }
            .frame(minWidth: 220, maxWidth: .infinity, alignment: .leading)

            Text(player.nationality).font(.system(size: 16)).frame(width: Col.nationality)
            Text(player.position.rawValue)
                .font(Theme.label(12))
                .foregroundStyle(Theme.chalkMuted)
                .frame(width: Col.position)
            number("\(player.appearances)", .appearances, Col.appearances)
            number("\(player.goals)", .goals, Col.goals)
            number("\(player.shots)", .shots, Col.shots)
            number("\(player.shotsOnTarget)", .onTarget, Col.onTarget)
            number("\(player.shotsOnTargetOutsideBox)", .onTargetOutside, Col.onTargetOutside)
            number("\(player.shotsOutsideBox)", .outside, Col.outside)
            number(Format.one(player.onTargetPercent), .onTargetPercent, Col.percent)
            number(Format.one(player.shotsPerGame), .perGame, Col.perGame)
            if showXG {
                number(player.xG.map { Format.one($0) } ?? "–", .xG, Col.xG)
                diffCell
            }
            ShotMixBar(player: player).frame(width: Col.mix)
            StarRating(value: rating, onChange: onRate).frame(width: Col.stars)
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .background(hovering ? Color.white.opacity(0.04) : Color.clear)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.stroke).frame(height: 1) }
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Avaa pelaajan tiedot")
        .onHover { hovering = $0 }
        .help("Avaa pelaajan laukauskartta")
    }

    private func number(_ text: String, _ key: PlayerSort, _ width: CGFloat) -> some View {
        let active = sortKey == key
        return Text(text)
            .font(Theme.number(14, weight: active ? .bold : .medium))
            .foregroundStyle(active ? Theme.floodlight : Theme.chalk)
            .frame(width: width)
    }

    private var diffCell: some View {
        let active = sortKey == .xGDiff
        let diff = player.xGDifference
        let color: Color
        if active {
            color = Theme.floodlight
        } else if let diff {
            color = diff >= 0 ? Theme.positive : Theme.negative
        } else {
            color = Theme.chalkMuted
        }
        let text = diff.map { ($0 >= 0 ? "+" : "") + Format.one($0) } ?? "–"
        return Text(text)
            .font(Theme.number(14, weight: active ? .bold : .medium))
            .foregroundStyle(color)
            .frame(width: Col.xGDiff)
    }
}
