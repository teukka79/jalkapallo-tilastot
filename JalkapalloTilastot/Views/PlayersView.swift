import SwiftUI

enum PlayerSort {
    case name, team, appearances, goals, shots, onTarget, onTargetOutside, outside, onTargetPercent, perGame
}

/// Sarakkeiden leveydet jaetaan otsikon ja rivien kesken, ettei mikään karkaa kohdalta.
private enum Col {
    static let nationality: CGFloat = 52
    static let position: CGFloat = 96
    static let appearances: CGFloat = 58
    static let goals: CGFloat = 58
    static let shots: CGFloat = 78
    static let onTarget: CGFloat = 78
    static let onTargetOutside: CGFloat = 108
    static let outside: CGFloat = 98
    static let percent: CGFloat = 70
    static let perGame: CGFloat = 66
    static let mix: CGFloat = 84
    static let stars: CGFloat = 84
}

struct PlayersView: View {
    @Environment(AppStore.self) private var store
    @State private var search = ""
    @State private var team: String?
    @State private var position: String?
    @State private var favoritesOnly = false
    @State private var sortKey: PlayerSort = .goals
    @State private var ascending = false

    var body: some View {
        let rows = filteredRows

        VStack(spacing: 12) {
            if store.playersAreSample { sampleBanner }
            filterBar(count: rows.count)
            VStack(spacing: 0) {
                headerRow
                Divider().overlay(Theme.stroke)
                if rows.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(rows) { player in
                                PlayerRow(player: player, sortKey: sortKey,
                                          rating: store.rating(for: player.id)) { stars in
                                    store.setRating(player.id, stars)
                                }
                            }
                        }
                    }
                }
            }
            .panel()
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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
        if favoritesOnly { list = list.filter { store.rating(for: $0.id) > 0 } }
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
        case .name, .team: return 0
        }
    }

    // MARK: Osat

    private var sampleBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle.fill").foregroundStyle(Theme.floodlight)
            Text("Esimerkkidata: pelaajat ja luvut on generoitu havainnollistamiseen. Tuo omat tilastot asetuksista (JSON).")
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
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.chalkMuted)
                TextField("Hae pelaajaa tai joukkuetta", text: $search)
                    .textFieldStyle(.plain)
                    .font(Theme.label(13))
                    .foregroundStyle(Theme.chalk)
            }
            .padding(.horizontal, 10)
            .frame(width: 290, height: 32)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.panelRaised))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))

            FilterMenu(title: "Kaikki joukkueet", options: teamOptions, selection: $team)
            FilterMenu(title: "Kaikki asemat", options: Position.allCases.map { $0.rawValue }, selection: $position)

            Button { favoritesOnly.toggle() } label: {
                Label("Suosikit", systemImage: favoritesOnly ? "star.fill" : "star")
                    .foregroundStyle(favoritesOnly ? Theme.floodlight : Theme.chalk)
            }
            .buttonStyle(GhostButtonStyle())

            Spacer()
            Text("\(count) pelaajaa")
                .font(Theme.label(12))
                .foregroundStyle(Theme.chalkMuted)
        }
        .onChange(of: store.selectedLeague) { _, _ in team = nil }
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
            Button("Tyhjennä rajaukset") {
                search = ""; team = nil; position = nil; favoritesOnly = false
            }
            .buttonStyle(GhostButtonStyle())
        }
        .frame(maxWidth: .infinity, minHeight: 220)
    }
}

private struct PlayerRow: View {
    let player: Player
    let sortKey: PlayerSort
    let rating: Int
    let onRate: (Int) -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 10) {
                TeamBadge(name: player.team, size: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(player.name)
                        .font(Theme.label(14, weight: .semibold))
                        .foregroundStyle(Theme.chalk)
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
            ShotMixBar(player: player).frame(width: Col.mix)
            StarRating(value: rating, onChange: onRate).frame(width: Col.stars)
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .background(hovering ? Color.white.opacity(0.04) : Color.clear)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.stroke).frame(height: 1) }
        .onHover { hovering = $0 }
    }

    private func number(_ text: String, _ key: PlayerSort, _ width: CGFloat) -> some View {
        let active = sortKey == key
        return Text(text)
            .font(Theme.number(14, weight: active ? .bold : .medium))
            .foregroundStyle(active ? Theme.floodlight : Theme.chalk)
            .frame(width: width)
    }
}
