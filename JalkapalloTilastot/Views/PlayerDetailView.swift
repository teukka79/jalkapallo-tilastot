import SwiftUI

/// Pelaajan yksityiskohdat: tunnusluvut, laukauskartta, seuranta ja muistiinpanot.
struct PlayerDetailView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let player: Player

    @State private var shots: [Shot] = []
    @State private var loading = true
    @State private var filter: ShotFilter = .all
    @State private var note = ""

    enum ShotFilter: CaseIterable {
        case all, goals, onTarget, outside

        var title: String {
            switch self {
            case .all: return "Kaikki"
            case .goals: return "Maalit"
            case .onTarget: return "Maalia kohti"
            case .outside: return "Ulkopuolelta"
            }
        }
    }

    private var visible: [Shot] {
        switch filter {
        case .all: return shots
        case .goals: return shots.filter { $0.result == .goal }
        case .onTarget: return shots.filter { $0.result.onTarget }
        case .outside: return shots.filter { $0.isOutsideBox }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.stroke)
            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    tiles
                    shotSection
                    noteSection
                }
                .padding(20)
            }
        }
        .frame(width: 700, height: 760)
        .background { PitchBackground() }
        .preferredColorScheme(.dark)
        .task(id: player.id) {
            note = store.note(for: player.id)
            loading = true
            shots = await store.shots(for: player)
            loading = false
        }
        .onChange(of: note) { _, new in store.setNote(player.id, new) }
    }

    // MARK: Yläosa

    private var header: some View {
        HStack(spacing: 14) {
            TeamBadge(name: player.team, size: 46)
            VStack(alignment: .leading, spacing: 3) {
                Text(player.name).font(Theme.title(24)).foregroundStyle(Theme.chalk)
                Text("\(player.nationality) \(player.leagueFlag) \(player.team) · \(player.position.rawValue)")
                    .font(Theme.label(12))
                    .foregroundStyle(Theme.chalkMuted)
            }
            Spacer()
            StarRating(value: store.rating(for: player.id)) { store.setRating(player.id, $0) }
            Button { store.toggleWatch(player.id) } label: {
                Image(systemName: store.isWatched(player.id) ? "bookmark.fill" : "bookmark")
                    .foregroundStyle(store.isWatched(player.id) ? Theme.floodlight : Theme.chalk)
            }
            .buttonStyle(GhostButtonStyle())
            .help("Seuraa pelaajaa")
            .accessibilityLabel(store.isWatched(player.id) ? "Lopeta pelaajan seuraaminen" : "Seuraa pelaajaa")
            Button { dismiss() } label: { Image(systemName: "xmark") }
                .buttonStyle(GhostButtonStyle())
                .keyboardShortcut(.cancelAction)
                .help("Sulje (Esc)")
                .accessibilityLabel("Sulje")
        }
        .padding(20)
    }

    // MARK: Tunnusluvut

    private typealias Tile = (title: String, value: String, color: Color)

    private var tileData: [Tile] {
        var list: [Tile] = []
        let diff = player.xGDifference
        var diffColor = Theme.chalk
        var diffText = "–"
        if let diff {
            diffColor = diff >= 0 ? Theme.positive : Theme.negative
            diffText = (diff >= 0 ? "+" : "") + Format.one(diff)
        }
        let minutesText = player.minutes.map { String($0) } ?? "–"
        let xgText = player.xG.map { Format.one($0) } ?? "–"
        var per90 = Format.one(player.shotsPerGame) + " / ott."
        if let value = player.shotsPer90 { per90 = Format.one(value) }
        var xgPerShot = "–"
        if let value = player.xGPerShot { xgPerShot = String(format: "%.2f", value).replacingOccurrences(of: ".", with: ",") }
        var outsideShare = "–"
        if player.shots > 0 { outsideShare = Format.percent(Double(player.shotsOutsideBox) / Double(player.shots) * 100) }

        list.append((title: "Ottelut", value: String(player.appearances), color: Theme.chalk))
        list.append((title: "Minuutit", value: minutesText, color: Theme.chalk))
        list.append((title: "Maalit", value: String(player.goals), color: Theme.chalk))
        list.append((title: "xG", value: xgText, color: Theme.chalk))
        list.append((title: "Maalit – xG", value: diffText, color: diffColor))
        list.append((title: "Laukaukset", value: String(player.shots), color: Theme.chalk))
        list.append((title: "Lauk. / 90 min", value: per90, color: Theme.chalk))
        list.append((title: "xG / laukaus", value: xgPerShot, color: Theme.chalk))
        list.append((title: "Maalia kohti", value: Format.percent(player.onTargetPercent), color: Theme.chalk))
        list.append((title: "Ulkopuolelta", value: String(player.shotsOutsideBox), color: Theme.floodlight))
        list.append((title: "Ulkop. maalia kohti", value: String(player.shotsOnTargetOutsideBox), color: Theme.floodlight))
        list.append((title: "Ulkopuolen osuus", value: outsideShare, color: Theme.floodlight))
        return list
    }

    private var tiles: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
            ForEach(Array(tileData.enumerated()), id: \.offset) { _, tile in
                VStack(alignment: .leading, spacing: 4) {
                    Text(tile.title).font(Theme.label(11)).foregroundStyle(Theme.chalkMuted)
                    Text(tile.value).font(Theme.number(20, weight: .bold)).foregroundStyle(tile.color)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .panel(radius: 10)
            }
        }
    }

    // MARK: Laukauskartta

    private var shotSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Laukauskartta").font(Theme.title(18)).foregroundStyle(Theme.chalk)
                Spacer()
                ThemedToggle(options: ShotFilter.allCases.map { (value: $0, label: $0.title) }, selection: $filter)
            }

            if loading {
                ProgressView().frame(maxWidth: .infinity, minHeight: 200)
            } else if shots.isEmpty {
                Text("Pelaajan laukaustietoja ei ole. Paina Päivitä pelaajat Pelaajat-välilehdellä, niin kartta täyttyy.")
                    .font(Theme.label(12))
                    .foregroundStyle(Theme.chalkMuted)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                ShotMapView(shots: visible)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Laukauskartta")
                    .accessibilityValue("\(visible.count) laukausta, joista \(visible.filter { $0.result == .goal }.count) maalia")
                    .frame(maxWidth: 470)
                    .frame(maxWidth: .infinity)
                legend
                Text(summary)
                    .font(Theme.label(12))
                    .foregroundStyle(Theme.chalkMuted)
            }
        }
        .padding(16)
        .panel()
    }

    private var summary: String {
        let xg = visible.reduce(0) { $0 + $1.xG }
        let outside = visible.filter { $0.isOutsideBox }.count
        return "\(visible.count) laukausta · xG \(Format.one(xg)) · rangaistusalueen ulkopuolelta \(outside). Pallon koko kertoo laukauksen xG:n."
    }

    private var legend: some View {
        HStack(spacing: 16) {
            legendItem("Maali") { Circle().fill(Theme.floodlight).overlay(Circle().stroke(Color.white.opacity(0.9), lineWidth: 1)) }
            legendItem("Maalia kohti") { Circle().fill(Theme.positive.opacity(0.75)) }
            legendItem("Ohi") { Circle().stroke(Theme.chalkMuted, lineWidth: 1.2) }
            legendItem("Blokattu") { Circle().fill(Theme.negative.opacity(0.55)) }
            legendItem("Tolppa") { Circle().stroke(Theme.floodlight, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2])) }
        }
        .frame(maxWidth: .infinity)
    }

    private func legendItem<S: View>(_ title: String, @ViewBuilder _ symbol: () -> S) -> some View {
        HStack(spacing: 5) {
            symbol().frame(width: 11, height: 11)
            Text(title).font(Theme.label(11)).foregroundStyle(Theme.chalkMuted)
        }
    }

    // MARK: Muistiinpano

    private var noteSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Muistiinpanot").font(Theme.title(18)).foregroundStyle(Theme.chalk)
            TextEditor(text: $note)
                .font(Theme.label(13))
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(minHeight: 90)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.panelRaised))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
        }
        .padding(16)
        .panel()
    }
}

/// Hyökkäyspuolisko pystyssä, maali ylhäällä. Rangaistusalue on korostettu, joten ulkopuoliset laukaukset erottuvat heti.
struct ShotMapView: View {
    let shots: [Shot]

    var body: some View {
        Canvas { ctx, size in
            let w = size.width
            let h = size.height
            let line = Color.white.opacity(0.28)

            func point(_ x: Double, _ y: Double) -> CGPoint {
                CGPoint(x: w * y, y: h * (1 - x) / 0.5)
            }
            func rect(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) -> CGRect {
                let a = point(x1, y1), b = point(x2, y2)
                return CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
            }

            let field = CGRect(origin: .zero, size: size)
            ctx.fill(Path(roundedRect: field, cornerRadius: 10), with: .color(Theme.panelRaised.opacity(0.55)))

            // Rangaistusalue (korostettu) ja maalialue
            let box = rect(1, Shot.boxYMin, Shot.boxX, Shot.boxYMax)
            ctx.fill(Path(box), with: .color(Theme.floodlight.opacity(0.07)))
            ctx.stroke(Path(box), with: .color(line), lineWidth: 1.5)
            ctx.stroke(Path(rect(1, 0.3653, 0.9476, 0.6347)), with: .color(line), lineWidth: 1.5)

            // Rangaistuspiste ja kaari
            let spot = point(1 - 11.0 / 105.0, 0.5)
            ctx.fill(Path(ellipseIn: CGRect(x: spot.x - 2, y: spot.y - 2, width: 4, height: 4)), with: .color(line))
            let radius = 9.15 * (w / 68.0)
            var arc = Path()
            var first = true
            for step in 0...40 {
                let angle = (36.9 + 106.2 * Double(step) / 40.0) * Double.pi / 180
                let p = CGPoint(x: spot.x + radius * cos(angle), y: spot.y + radius * sin(angle))
                if first { arc.move(to: p); first = false } else { arc.addLine(to: p) }
            }
            ctx.stroke(arc, with: .color(line), lineWidth: 1.5)

            // Maali
            let goalLeft = point(1, 0.4462)
            ctx.fill(Path(CGRect(x: goalLeft.x, y: 0, width: w * 0.1076, height: 5)), with: .color(Color.white.opacity(0.7)))
            ctx.stroke(Path(roundedRect: field, cornerRadius: 10), with: .color(line), lineWidth: 1.5)

            // Laukaukset: maalit päällimmäisenä
            let ordered = shots.sorted { ($0.result == .goal ? 1 : 0) < ($1.result == .goal ? 1 : 0) }
            for shot in ordered {
                let p = point(shot.x, shot.y)
                let r = 3.5 + sqrt(max(shot.xG, 0)) * 11
                let circle = Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
                switch shot.result {
                case .goal:
                    ctx.fill(circle, with: .color(Theme.floodlight))
                    ctx.stroke(circle, with: .color(Color.white.opacity(0.9)), lineWidth: 1.5)
                case .saved:
                    ctx.fill(circle, with: .color(Theme.positive.opacity(0.75)))
                case .missed:
                    ctx.stroke(circle, with: .color(Theme.chalkMuted), lineWidth: 1.2)
                case .blocked:
                    ctx.fill(circle, with: .color(Theme.negative.opacity(0.55)))
                case .post:
                    ctx.stroke(circle, with: .color(Theme.floodlight), style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
                }
            }
        }
        .aspectRatio(68.0 / 52.5, contentMode: .fit)
    }
}
