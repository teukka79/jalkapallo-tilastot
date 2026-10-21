import SwiftUI

struct StandingsView: View {
    @Environment(AppStore.self) private var store

    private enum Zone { case champions, europe, relegation, none }

    private var league: League { store.focusLeague }
    private var rows: [StandingRow] { store.standings[league.rawValue] ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            titleRow
            VStack(spacing: 0) {
                headerRow
                Divider().overlay(Theme.stroke)
                if rows.isEmpty {
                    Text("Sarjataulukkoa ei ole vielä saatavilla")
                        .font(Theme.label(14))
                        .foregroundStyle(Theme.chalkMuted)
                        .frame(maxWidth: .infinity, minHeight: 200)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(rows) { row in standingRow(row) }
                        }
                    }
                }
            }
            .panel()
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            legend
        }
    }

    // MARK: Osat

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

    private var headerRow: some View {
        HStack(spacing: 0) {
            head("#", 40)
            head("Joukkue", nil, .leading)
            head("O", 44); head("V", 44); head("T", 44); head("H", 44)
            head("Maalit", 80); head("ME", 54); head("P", 58)
            head("Muoto", 120)
        }
        .padding(.horizontal, 16)
    }

    private func head(_ title: String, _ width: CGFloat?, _ alignment: Alignment = .center) -> some View {
        Text(title)
            .font(Theme.label(11, weight: .semibold))
            .foregroundStyle(Theme.chalkMuted)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: alignment)
            .frame(width: width, height: 36, alignment: alignment)
    }

    private func standingRow(_ row: StandingRow) -> some View {
        let rowZone = zone(for: row.position)
        return HStack(spacing: 0) {
            Text("\(row.position)").font(Theme.number(14, weight: .semibold)).foregroundStyle(Theme.chalk).frame(width: 40)
            HStack(spacing: 10) {
                TeamBadge(name: row.team, size: 26)
                Text(row.team).font(Theme.label(14, weight: .semibold)).foregroundStyle(Theme.chalk)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            cell("\(row.played)", 44); cell("\(row.won)", 44); cell("\(row.drawn)", 44); cell("\(row.lost)", 44)
            cell("\(row.goalsFor):\(row.goalsAgainst)", 80)
            Text(row.goalDifference > 0 ? "+\(row.goalDifference)" : "\(row.goalDifference)")
                .font(Theme.number(14))
                .foregroundStyle(row.goalDifference > 0 ? Theme.positive : (row.goalDifference < 0 ? Theme.negative : Theme.chalkMuted))
                .frame(width: 54)
            Text("\(row.points)").font(Theme.number(15, weight: .bold)).foregroundStyle(Theme.floodlight).frame(width: 58)
            formDots(row.form).frame(width: 120)
        }
        .padding(.horizontal, 16)
        .frame(height: 46)
        .overlay(alignment: .leading) { Rectangle().fill(color(for: rowZone)).frame(width: 3) }
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.stroke).frame(height: 1) }
    }

    private func cell(_ text: String, _ width: CGFloat) -> some View {
        Text(text).font(Theme.number(14)).foregroundStyle(Theme.chalk).frame(width: width)
    }

    private func formDots(_ form: [String]) -> some View {
        HStack(spacing: 4) {
            ForEach(Array(form.enumerated()), id: \.offset) { _, code in
                Circle()
                    .fill(code == "W" ? Theme.positive : (code == "L" ? Theme.negative : Theme.chalkMuted.opacity(0.6)))
                    .frame(width: 9, height: 9)
            }
        }
    }

    private var legend: some View {
        HStack(spacing: 18) {
            if league == .championsLeague {
                legendItem(Theme.positive, "Suoraan jatkoon")
                legendItem(Theme.european, "Jatkopelit")
            } else {
                legendItem(Theme.positive, "Mestarien liiga")
                legendItem(Theme.european, "Eurooppa-sarjat")
                legendItem(Theme.negative, "Putoamisalue")
            }
            Spacer()
        }
    }

    private func legendItem(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 1).fill(color).frame(width: 3, height: 12)
            Text(text).font(Theme.label(11)).foregroundStyle(Theme.chalkMuted)
        }
    }

    // MARK: Vyöhykkeet

    private func zone(for position: Int) -> Zone {
        let count = rows.count
        if league == .championsLeague {
            if position <= 8 { return .champions }
            return position <= 24 ? .europe : .none
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
