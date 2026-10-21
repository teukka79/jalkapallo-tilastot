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
            .padding(.horizontal, 28)
            .padding(.top, 34)
            .padding(.bottom, 20)
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .onAppear { store.applyAppIcon() }
        .task(id: store.focusLeague) { await store.refresh() }
    }

    // MARK: Osat

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Jalkapallon Laukaustilasto")
                    .font(Theme.title(32))
                    .foregroundStyle(Theme.chalk)
                Text("Kausi 2026/2027 · \(store.players.count) pelaajaa · \(store.ratedCount) arvosteltu")
                    .font(Theme.label(13))
                    .foregroundStyle(Theme.chalkMuted)
            }
            Spacer()
            Text(statusText)
                .font(Theme.label(12))
                .foregroundStyle(store.isLive(store.focusLeague) ? Theme.positive : Theme.floodlight)
                .multilineTextAlignment(.trailing)
                .padding(.top, 8)
            Button {
                Task { await store.refresh(force: true) }
            } label: {
                Label(store.isLoading ? "Haetaan…" : "Päivitä", systemImage: "arrow.clockwise")
            }
            .buttonStyle(GhostButtonStyle())
            .disabled(store.isLoading || !store.hasAPIKey)
            Button { showSettings = true } label: { Image(systemName: "gearshape") }
                .buttonStyle(GhostButtonStyle())
        }
    }

    private var statusText: String {
        let league = store.focusLeague
        if store.isLive(league), let date = store.updatedAt[league.rawValue] {
            return "\(league.name): live-data, päivitetty \(Format.time(date))"
        }
        return store.hasAPIKey ? "Taulukot ja ottelut: esimerkkidata, haetaan…"
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
