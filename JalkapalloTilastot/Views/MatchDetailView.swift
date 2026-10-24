import SwiftUI

/// Ottelun tilastoikkuna: avautuu otteluohjelmasta pelatun tai käynnissä olevan ottelun rivistä.
struct MatchDetailView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let match: Match

    @State private var stats: MatchStats?
    @State private var errorText: String?
    @State private var loading = true
    @State private var period: StatPeriod = .full
    @State private var goals: [GoalEvent] = []

    private var league: League? { League(rawValue: match.league) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.stroke)
            content
        }
        .frame(width: 640, height: 740)
        .background { PitchBackground() }
        .preferredColorScheme(.dark)
        .task(id: match.id) { await load() }
        .task(id: match.id) { goals = await store.loadGoals(for: match) }
    }

    // MARK: Yläosa

    private var header: some View {
        VStack(spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(league?.flag ?? "") \(league?.name ?? "")")
                        .font(Theme.label(12, weight: .semibold))
                        .foregroundStyle(Theme.chalk)
                    Text("Kierros \(match.matchday) · \(Format.day(match.date)) \(Format.time(match.date))")
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
                team(match.home)
                VStack(spacing: 4) {
                    Text("\(match.homeGoals ?? 0) – \(match.awayGoals ?? 0)")
                        .font(Theme.number(34, weight: .bold))
                        .foregroundStyle(match.status == .live ? Theme.negative : Theme.chalk)
                    Text(match.status == .live ? "Käynnissä" : "Päättynyt")
                        .font(Theme.label(11, weight: .semibold))
                        .foregroundStyle(match.status == .live ? Theme.negative : Theme.chalkMuted)
                }
                .frame(width: 130)
                team(match.away)
            }

            HStack(alignment: .top) {
                formChips(for: match.home)
                Color.clear.frame(width: 130, height: 1)
                formChips(for: match.away)
            }

            if let stats, stats.availablePeriods.count > 1 {
                ThemedToggle(options: stats.availablePeriods.map { (value: $0, label: $0.title) },
                             selection: $period)
            }
        }
        .padding(20)
    }

    /// Joukkueen viisi viimeisintä ottelua (V = voitto, T = tasapeli, H = häviö)
    private func formChips(for team: String) -> some View {
        let results = store.recentForm(team: team, league: match.league, before: match.date)
        return VStack(spacing: 4) {
            if !results.isEmpty {
                Text("Viimeisimmät").font(Theme.label(10)).foregroundStyle(Theme.chalkMuted)
                HStack(spacing: 4) {
                    ForEach(results) { result in
                        Text(result.code == "W" ? "V" : (result.code == "D" ? "T" : "H"))
                            .font(Theme.label(10, weight: .bold))
                            .foregroundStyle(Color.black.opacity(0.85))
                            .frame(width: 18, height: 18)
                            .background(Circle().fill(result.code == "W" ? Theme.positive
                                                      : (result.code == "D" ? Theme.chalkMuted : Theme.negative)))
                            .help(result.text)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func goalLabel(_ goal: GoalEvent) -> String {
        var text = "\(goal.minute)'"
        if let extra = goal.extra, extra > 0 { text = "\(goal.minute)+\(extra)'" }
        text += " \(goal.scorer)"
        if goal.kind == "OWN" { text += " (oma maali)" }
        if goal.kind == "PENALTY" { text += " (rp)" }
        return text
    }

    private var goalsPanel: some View {
        VStack(spacing: 0) {
            Text("MAALIT")
                .font(Theme.label(10, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(Theme.chalkMuted)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(Theme.panelRaised.opacity(0.7))
            VStack(spacing: 8) {
                ForEach(goals) { goal in
                    HStack(spacing: 10) {
                        Text(goal.isHome ? goalLabel(goal) : "")
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        Image(systemName: "soccerball").foregroundStyle(Theme.floodlight)
                        Text(goal.isHome ? "" : goalLabel(goal))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .font(Theme.label(12, weight: .medium))
                    .foregroundStyle(Theme.chalk)
                    .help(goal.assist.map { "Syöttö: \($0)" } ?? "")
                }
            }
            .padding(16)
        }
        .panel()
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func team(_ name: String) -> some View {
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

    // MARK: Sisältö

    @ViewBuilder
    private var content: some View {
        if loading {
            ProgressView().controlSize(.large)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorText {
            Text(errorText)
                .font(Theme.label(13))
                .foregroundStyle(Theme.chalkMuted)
                .multilineTextAlignment(.center)
                .padding(40)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let stats {
            let values = stats.values(for: period)
            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    if !goals.isEmpty { goalsPanel }
                    ForEach(StatGroup.all) { group in
                        let keys = group.keys.filter { values[$0] != nil }
                        if !keys.isEmpty {
                            groupPanel(group.title, keys: keys, values: values)
                        }
                    }
                    Text(stats.isSample
                         ? "Esimerkkidata: luvut on generoitu eivätkä kuvaa oikeaa ottelua."
                         : "Tilastot: API-Football")
                        .font(Theme.label(11))
                        .foregroundStyle(Theme.chalkMuted)
                        .padding(.top, 4)
                }
                .padding(20)
            }
        }
    }

    private func groupPanel(_ title: String, keys: [StatKey], values: [StatKey: StatPair]) -> some View {
        VStack(spacing: 0) {
            Text(title.uppercased())
                .font(Theme.label(10, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(Theme.chalkMuted)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(Theme.panelRaised.opacity(0.7))
            VStack(spacing: 16) {
                ForEach(keys, id: \.self) { key in
                    if let pair = values[key] { StatRowView(key: key, pair: pair) }
                }
            }
            .padding(16)
        }
        .panel()
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func load() async {
        loading = true
        errorText = nil
        do {
            let loaded = try await store.loadStats(for: match)
            stats = loaded
            period = loaded.availablePeriods.first ?? .full
        } catch {
            stats = nil
            errorText = error.localizedDescription
        }
        loading = false
    }
}

/// Yksi tilastorivi: arvot reunoilla, nimi keskellä, palkit keskeltä ulospäin. Suurempi arvo korostetaan.
private struct StatRowView: View {
    let key: StatKey
    let pair: StatPair

    var body: some View {
        let home = pair.home.share(for: key.kind)
        let away = pair.away.share(for: key.kind)

        VStack(spacing: 7) {
            ZStack {
                HStack(spacing: 6) {
                    valueView(pair.home, leading: true)
                    Spacer(minLength: 0)
                    valueView(pair.away, leading: false)
                }
                HStack(spacing: 4) {
                    Text(key.label)
                        .font(Theme.label(12, weight: .semibold))
                        .foregroundStyle(Theme.chalk)
                    if key.hint != nil {
                        Image(systemName: "info.circle")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.chalkMuted)
                    }
                }
                .help(key.hint ?? key.label)
            }
            bars(home: home, away: away)
        }
    }

    private func bars(home: Double, away: Double) -> some View {
        let total = home + away
        return GeometryReader { geo in
            let half = max(0, (geo.size.width - 4) / 2)
            HStack(spacing: 4) {
                ZStack(alignment: .trailing) {
                    Capsule().fill(Theme.chalk.opacity(0.06))
                    Capsule().fill(color(leading: home > away))
                        .frame(width: total > 0 ? half * home / total : 0)
                }
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.chalk.opacity(0.06))
                    Capsule().fill(color(leading: away > home))
                        .frame(width: total > 0 ? half * away / total : 0)
                }
            }
        }
        .frame(height: 6)
    }

    private func color(leading: Bool) -> Color {
        leading ? Theme.floodlight : Theme.chalk.opacity(0.55)
    }

    @ViewBuilder
    private func valueView(_ value: StatValue, leading: Bool) -> some View {
        let main = mainText(value)
        let detail = detailText(value)
        HStack(spacing: 4) {
            if leading {
                Text(main).font(Theme.number(13, weight: .bold)).foregroundStyle(Theme.chalk)
                if let detail { Text(detail).font(Theme.number(10)).foregroundStyle(Theme.chalkMuted) }
            } else {
                if let detail { Text(detail).font(Theme.number(10)).foregroundStyle(Theme.chalkMuted) }
                Text(main).font(Theme.number(13, weight: .bold)).foregroundStyle(Theme.chalk)
            }
        }
    }

    private func mainText(_ value: StatValue) -> String {
        switch key.kind {
        case .count:
            return "\(Int(value.value.rounded()))"
        case .decimal:
            return value.value.formatted(.number.precision(.fractionLength(2)).locale(Locale(identifier: "fi_FI")))
        case .percent:
            return "\(Int(value.value.rounded()))%"
        case .ratio:
            guard let attempts = value.attempts, attempts > 0 else { return "–" }
            return "\(Int((value.value / attempts * 100).rounded()))%"
        }
    }

    private func detailText(_ value: StatValue) -> String? {
        guard key.kind == .ratio, let attempts = value.attempts, attempts > 0 else { return nil }
        return "(\(Int(value.value))/\(Int(attempts)))"
    }
}
