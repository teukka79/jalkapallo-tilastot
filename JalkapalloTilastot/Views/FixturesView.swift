import SwiftUI

struct FixturesView: View {
    @Environment(AppStore.self) private var store
    @State private var matchday = 1
    @State private var selected: Match?
    @State private var hovered: String?
    /// Oletuksena näytetään vain kuluva päivä ja tulevat ottelut.
    @AppStorage("hidePastDays") private var hidePastDays = true
    /// Näyttää vain meneillään olevat ottelut.
    @State private var liveOnly = false

    private var league: League { store.focusLeague }
    private var allMatches: [Match] { store.matches[league.rawValue] ?? [] }
    private var matchdays: [Int] { Array(Set(allMatches.map { $0.matchday })).sorted() }
    private var hasLive: Bool {
        (allLeagues ? store.todayMatches : allMatches).contains { $0.status == .live }
    }
    /// Ilman sarjavalintaa: tämän päivän ottelut kaikista sarjoista.
    private var allLeagues: Bool { store.selectedLeague == nil }
    private var current: [Match] {
        let base: [Match]
        if allLeagues {
            base = store.todayMatches
        } else if liveOnly {
            base = allMatches   // meneillään olevat kaikilta kierroksilta
        } else {
            base = allMatches.filter { $0.matchday == matchday }
        }
        return base.filter { !liveOnly || $0.status == .live }.sorted { $0.date < $1.date }
    }
    private var emptyMessage: String {
        if liveOnly { return "Ei meneillään olevia otteluita" }
        if allLeagues { return "Ei otteluita tänään" }
        return current.isEmpty ? "Otteluita ei ole vielä saatavilla"
                               : "Kierroksen ottelut on jo pelattu.\nNäytä ne kytkimellä \"Näytä menneet päivät\"."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            navigator
            if visibleGroups.isEmpty {
                Text(emptyMessage)
                    .multilineTextAlignment(.center)
                    .font(Theme.label(14))
                    .foregroundStyle(Theme.chalkMuted)
                    .frame(maxWidth: .infinity, minHeight: 200)
                    .panel()
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(visibleGroups) { group in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(group.title)
                                    .font(Theme.label(12, weight: .semibold))
                                    .foregroundStyle(Theme.chalkMuted)
                                VStack(spacing: 0) {
                                    ForEach(group.matches) { match in matchRow(match) }
                                }
                                .panel()
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                        }
                    }
                    .frame(maxWidth: 860, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .onAppear(perform: pickCurrentMatchday)
        .task(id: store.selectedLeague) {
            if store.selectedLeague == nil { await store.refreshToday() }
        }
        .task(id: oddsTaskID) {
            await store.loadOdds(for: oddsLeagues)
        }
        .onChange(of: store.focusLeague) { _, _ in pickCurrentMatchday() }
        .onChange(of: allMatches.count) { _, _ in pickCurrentMatchday() }
        .sheet(item: $selected) { MatchDetailView(match: $0) }
        .task(id: "\(hasLive)-\(allLeagues)") {
            // Käynnissä olevien otteluiden tulokset päivittyvät minuutin välein
            guard hasLive else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                if Task.isCancelled { break }
                if allLeagues { await store.refreshToday() } else { await store.refresh(force: true) }
            }
        }
    }

    // MARK: Kertoimet

    /// Sarjat, joiden kertoimia tarvitaan: valittu sarja tai kaikki sarjat, joilla on ottelu tänään.
    private var oddsLeagues: [League] {
        if allLeagues {
            let ids = Set(store.todayMatches.filter { $0.status == .scheduled }.map { $0.league })
            return League.allCases.filter { ids.contains($0.rawValue) }
        }
        return [league]
    }
    private var oddsTaskID: String {
        "\(store.hasOddsKey)-" + oddsLeagues.map { $0.rawValue }.joined(separator: ",")
    }

    private func oddsText(_ odds: MatchOdds) -> String {
        func f(_ v: Double?) -> String { v.map { String(format: "%.2f", $0) } ?? "–" }
        return "\(f(odds.home))  \(f(odds.draw))  \(f(odds.away))"
    }

    private func oddsHelp(_ odds: MatchOdds) -> String {
        func f(_ v: Double?) -> String { v.map { String(format: "%.2f", $0) } ?? "–" }
        var text = "1 (koti) \(f(odds.home)) · X (tasapeli) \(f(odds.draw)) · 2 (vieras) \(f(odds.away))"
        if odds.over != nil || odds.under != nil {
            text += "\nYli \(String(format: "%.1f", odds.line)) maalia \(f(odds.over)) · Alle \(f(odds.under))"
        }
        text += "\nKeskiarvo \(odds.bookmakers) vedonvälittäjältä"
        return text
    }

    // MARK: Osat

    private var navigator: some View {
        HStack(spacing: 10) {
            if allLeagues {
                Text("Tänään")
                    .font(Theme.title(20))
                    .foregroundStyle(Theme.chalk)
                Text("· kaikki sarjat")
                    .font(Theme.label(12))
                    .foregroundStyle(Theme.chalkMuted)
            } else {
                Text("\(league.flag) \(league.name)")
                    .font(Theme.title(20))
                    .foregroundStyle(Theme.chalk)
            }
            Spacer()
            Toggle("Vain meneillään", isOn: $liveOnly)
                .toggleStyle(ThemedSwitchStyle())
                .font(Theme.label(12))
                .foregroundStyle(Theme.chalkMuted)
                .padding(.trailing, 8)
            if !allLeagues {
                leagueControls
            }
        }
    }

    @ViewBuilder
    private var leagueControls: some View {
        HStack(spacing: 10) {
            if !liveOnly {
                Toggle("Näytä menneet päivät", isOn: showPast)
                    .toggleStyle(ThemedSwitchStyle())
                    .font(Theme.label(12))
                    .foregroundStyle(Theme.chalkMuted)
                    .padding(.trailing, 8)
            }
            Button { step(-1) } label: { Image(systemName: "chevron.left") }
                .buttonStyle(GhostButtonStyle())
                .disabled(matchday <= (matchdays.first ?? 1))
            Text("Kierros \(matchday)")
                .font(Theme.label(13, weight: .semibold))
                .foregroundStyle(Theme.chalk)
                .frame(minWidth: 80)
            Button { step(1) } label: { Image(systemName: "chevron.right") }
                .buttonStyle(GhostButtonStyle())
                .disabled(matchday >= (matchdays.last ?? 1))
        }
        .opacity(liveOnly ? 0.4 : 1)
        .disabled(liveOnly)
    }

    private struct DayGroup: Identifiable {
        let id: String
        let title: String
        let day: Date
        let matches: [Match]
    }

    private var groupedDays: [DayGroup] {
        if allLeagues {
            // Sarjoittain, sarjajärjestyksessä
            let grouped = Dictionary(grouping: current) { $0.league }
            return League.allCases.compactMap { league in
                guard let list = grouped[league.rawValue], !list.isEmpty else { return nil }
                return DayGroup(id: league.rawValue, title: "\(league.flag) \(league.name)",
                                day: Date(), matches: list)
            }
        }
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: current) { calendar.startOfDay(for: $0.date) }
        return grouped.keys.sorted().map {
            DayGroup(id: "\($0.timeIntervalSince1970)", title: Format.day($0), day: $0, matches: grouped[$0] ?? [])
        }
    }

    /// Kytkin on "näytä menneet", tallennettu arvo on "piilota menneet".
    private var showPast: Binding<Bool> {
        Binding(get: { !hidePastDays }, set: { hidePastDays = !$0 })
    }

    private var visibleGroups: [DayGroup] {
        guard hidePastDays, !allLeagues, !liveOnly else { return groupedDays }
        let today = Calendar.current.startOfDay(for: Date())
        return groupedDays.filter { $0.day >= today }
    }

    private func matchRow(_ match: Match) -> some View {
        HStack(spacing: 12) {
            HStack(spacing: 10) {
                Spacer(minLength: 0)
                Text(match.home).font(Theme.label(14, weight: .semibold)).foregroundStyle(Theme.chalk)
                TeamBadge(name: match.home, size: 36)
            }
            .frame(maxWidth: .infinity)

            centerBox(match)

            HStack(spacing: 10) {
                TeamBadge(name: match.away, size: 36)
                Text(match.away).font(Theme.label(14, weight: .semibold)).foregroundStyle(Theme.chalk)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, rowOdds(match) == nil ? 0 : 6)
        .frame(minHeight: 56)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.stroke).frame(height: 1) }
        .background(hovered == match.id && match.status != .scheduled ? Theme.panelRaised.opacity(0.7) : Color.clear)
        .contentShape(Rectangle())
        .onHover { inside in
            if inside { hovered = match.id } else if hovered == match.id { hovered = nil }
        }
        .onTapGesture { if match.status != .scheduled { selected = match } }
        .accessibilityAddTraits(match.status == .scheduled ? [] : .isButton)
        .help(match.status == .scheduled ? "" : "Näytä ottelun tilastot")
    }

    /// Kertoimet näytetään vain pelaamattomille otteluille.
    private func rowOdds(_ match: Match) -> MatchOdds? {
        guard match.status == .scheduled, let odds = store.odds(for: match), odds.hasMatchOdds else { return nil }
        return odds
    }

    private func centerBox(_ match: Match) -> some View {
        VStack(spacing: 4) {
            scoreBox(match)
            if let odds = rowOdds(match) {
                Text(oddsText(odds))
                    .font(Theme.number(11))
                    .foregroundStyle(Theme.chalkMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .help(oddsHelp(odds))
                    .accessibilityLabel("Kertoimet: \(oddsHelp(odds))")
            }
        }
        .frame(width: 130)
    }

    @ViewBuilder
    private func scoreBox(_ match: Match) -> some View {
        switch match.status {
        case .finished, .live:
            HStack(spacing: 6) {
                if match.status == .live { Circle().fill(Theme.negative).frame(width: 7, height: 7) }
                Text("\(match.homeGoals ?? 0) – \(match.awayGoals ?? 0)")
                    .font(Theme.number(16, weight: .bold))
                    .foregroundStyle(match.status == .live ? Theme.negative : Theme.chalk)
            }
            .frame(width: 90, height: 30)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.panelRaised))
        case .scheduled:
            Text(Format.time(match.date))
                .font(Theme.number(14, weight: .semibold))
                .foregroundStyle(Theme.floodlight)
                .frame(width: 90, height: 30)
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.floodlight.opacity(0.35), lineWidth: 1))
        }
    }

    // MARK: Kierrosvalinta

    private func step(_ delta: Int) {
        let days = matchdays
        guard let index = days.firstIndex(of: matchday) else { return }
        let next = index + delta
        if days.indices.contains(next) { matchday = days[next] }
    }

    /// Ensimmäinen kierros, jolla on vielä pelaamattomia otteluja; muuten viimeinen.
    private func pickCurrentMatchday() {
        let open = allMatches.filter { $0.status != .finished }.map { $0.matchday }.filter { $0 > 0 }.min()
        matchday = open ?? matchdays.last ?? 1
    }
}
