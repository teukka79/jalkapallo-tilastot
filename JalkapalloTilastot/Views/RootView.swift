import SwiftUI

struct RootView: View {
    @Environment(AppStore.self) private var store
    @State private var showSettings = false

    var body: some View {
        @Bindable var store = store

        ZStack {
            PitchBackground()
            VStack(alignment: .leading, spacing: 16) {
                header
                leagueBar
                HStack {
                    ThemedToggle(options: AppSection.allCases.map { (value: $0, label: $0.rawValue) },
                                 selection: $store.section)
                    Spacer()
                    if let message = store.errorMessage {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .font(Theme.label(12))
                            .foregroundStyle(Theme.negative)
                            .lineLimit(1)
                    }
                }
                content
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 28)
            .padding(.top, 34)
            .padding(.bottom, 20)
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .onAppear { store.applyAppIcon() }
        .task(id: store.focusLeague) { await store.refresh() }
        .task { await store.autoUpdatePlayersIfNeeded() }
    }

    // MARK: Osat

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Jalkapallotilastot")
                    .font(Theme.title(32))
                    .foregroundStyle(Theme.chalk)
                Text("Kausi 2026/2027 · \(store.players.count) pelaajaa · \(store.ratedCount) arvosteltu")
                    .font(Theme.label(13))
                    .foregroundStyle(Theme.chalkMuted)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                Text(statusText)
                    .font(Theme.label(12))
                    .foregroundStyle(statusColor)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
                if store.isUpdatingPlayers {
                    if let progress = store.playerUpdateProgress {
                        ProgressView(value: progress).tint(Theme.floodlight).frame(width: 220)
                    } else {
                        ProgressView().controlSize(.small)
                    }
                }
            }
            .frame(maxWidth: 360, alignment: .trailing)
            .padding(.top, 8)
            Button {
                Task {
                    if store.section == .players { await store.updatePlayers() }
                    else if showsToday { await store.refreshToday() }
                    else { await store.refresh(force: true) }
                }
            } label: {
                Label(refreshTitle, systemImage: "arrow.clockwise")
            }
            .buttonStyle(GhostButtonStyle())
            .disabled(refreshDisabled)
            .help(store.section == .players
                  ? "Hakee pelaajien uudet laukaustilastot Understatista (ensimmäinen kerta kestää)"
                  : "Hakee sarjataulukon ja otteluohjelman")
            Button { showSettings = true } label: { Image(systemName: "gearshape") }
                .buttonStyle(GhostButtonStyle())
                .accessibilityLabel("Asetukset")
                .help("Asetukset")
        }
    }

    private var refreshTitle: String {
        if store.section == .players { return store.isUpdatingPlayers ? "Päivitetään…" : "Päivitä pelaajat" }
        return (showsToday ? store.isLoadingToday : store.isLoading) ? "Haetaan…" : "Päivitä"
    }

    /// Otteluohjelma ilman sarjavalintaa näyttää tämän päivän ottelut kaikista sarjoista.
    private var showsToday: Bool { store.section == .fixtures && store.selectedLeague == nil }

    private var refreshDisabled: Bool {
        if store.section == .players { return store.isUpdatingPlayers }
        if showsToday { return store.isLoadingToday }
        return store.isLoading || !store.hasKey(for: store.focusLeague)
    }

    private var statusColor: Color {
        if store.section == .players { return store.isUpdatingPlayers ? Theme.floodlight : Theme.chalkMuted }
        if showsToday { return store.liveToday.isEmpty ? Theme.floodlight : Theme.positive }
        return store.isLive(store.focusLeague) ? Theme.positive : Theme.floodlight
    }

    private var statusText: String {
        if store.section == .players {
            if let status = store.playerUpdateStatus { return status }
            if let date = store.lastPlayersUpdate {
                return "Pelaajatilastot päivitetty \(Format.day(date)) \(Format.time(date))"
            }
            return store.playersAreSample ? "Pelaajat: esimerkkidata" : "Pelaajat: tuotu data"
        }
        if showsToday {
            guard let date = store.todayUpdated else { return "Haetaan tämän päivän otteluita…" }
            return store.liveToday.isEmpty ? "Tänään: esimerkkidata"
                                           : "Tänään: live-data, päivitetty \(Format.time(date))"
        }
        let league = store.focusLeague
        if store.isLive(league), let date = store.updatedAt[league.rawValue] {
            return "\(league.name): live-data, päivitetty \(Format.time(date))"
        }
        if store.hasKey(for: league) { return "Taulukot ja ottelut: esimerkkidata, haetaan…" }
        return league.source == .apiFootball
            ? "Taulukot ja ottelut: esimerkkidata\nTämä sarja tarvitsee API-Football-avaimen (asetukset)"
            : "Taulukot ja ottelut: esimerkkidata\nLisää API-avain asetuksissa"
    }

    private var leagueBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                LeagueChip(title: "Kaikki", flag: nil, accent: Theme.floodlight,
                           selected: store.selectedLeague == nil) {
                    store.selectedLeague = nil
                }
                ForEach(League.allCases) { league in
                    LeagueChip(title: league.name, flag: league.flag, accent: league.accent,
                               selected: store.selectedLeague == league) {
                        store.selectedLeague = league
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch store.section {
        case .players: PlayersView()
        case .standings: StandingsView()
        case .fixtures: FixturesView()
        }
    }
}
