import SwiftUI

struct FixturesView: View {
    @Environment(AppStore.self) private var store
    @State private var matchday = 1

    private var league: League { store.focusLeague }
    private var allMatches: [Match] { store.matches[league.rawValue] ?? [] }
    private var matchdays: [Int] { Array(Set(allMatches.map { $0.matchday })).sorted() }
    private var current: [Match] { allMatches.filter { $0.matchday == matchday }.sorted { $0.date < $1.date } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            navigator
            if current.isEmpty {
                Text("Otteluita ei ole vielä saatavilla")
                    .font(Theme.label(14))
                    .foregroundStyle(Theme.chalkMuted)
                    .frame(maxWidth: .infinity, minHeight: 200)
                    .panel()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(groupedDays) { group in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(Format.day(group.day))
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
                }
            }
        }
        .onAppear(perform: pickCurrentMatchday)
        .onChange(of: store.focusLeague) { _, _ in pickCurrentMatchday() }
        .onChange(of: allMatches.count) { _, _ in pickCurrentMatchday() }
    }

    // MARK: Osat

    private var navigator: some View {
        HStack(spacing: 10) {
            Text("\(league.flag) \(league.name)")
                .font(Theme.title(20))
                .foregroundStyle(Theme.chalk)
            if store.selectedLeague == nil {
                Text("· valitse sarja yläpalkista")
                    .font(Theme.label(12))
                    .foregroundStyle(Theme.chalkMuted)
            }
            Spacer()
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
    }

    private struct DayGroup: Identifiable {
        let day: Date
        let matches: [Match]
        var id: Date { day }
    }

    private var groupedDays: [DayGroup] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: current) { calendar.startOfDay(for: $0.date) }
        return grouped.keys.sorted().map { DayGroup(day: $0, matches: grouped[$0] ?? []) }
    }

    private func matchRow(_ match: Match) -> some View {
        HStack(spacing: 12) {
            HStack(spacing: 10) {
                Spacer(minLength: 0)
                Text(match.home).font(Theme.label(14, weight: .semibold)).foregroundStyle(Theme.chalk)
                TeamBadge(name: match.home, size: 28)
            }
            .frame(maxWidth: .infinity)

            centerBox(match)

            HStack(spacing: 10) {
                TeamBadge(name: match.away, size: 28)
                Text(match.away).font(Theme.label(14, weight: .semibold)).foregroundStyle(Theme.chalk)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.stroke).frame(height: 1) }
    }

    @ViewBuilder
    private func centerBox(_ match: Match) -> some View {
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
