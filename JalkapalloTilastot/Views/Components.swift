import SwiftUI
import AppKit

/// Joukkueen merkki: live-datassa logo, muuten nimikirjaimet joukkueen nimestä johdetulla sävyllä.
struct TeamBadge: View {
    @Environment(AppStore.self) private var store
    let name: String
    var size: CGFloat = 28
    @State private var logo: NSImage?

    private var initials: String {
        let words = name.split(separator: " ")
        if words.count >= 2 {
            return String(words.prefix(2).compactMap { $0.first }).uppercased()
        }
        return String(name.prefix(3)).uppercased()
    }

    private var hue: Double {
        let h = name.unicodeScalars.reduce(5381) { ($0 &* 33 &+ Int($1.value)) % 360 }
        return Double(h) / 360
    }

    var body: some View {
        let url = store.crestURL(for: name)
        ZStack {
            if let logo {
                Circle().fill(Color.white.opacity(0.1))
                Image(nsImage: logo)
                    .resizable()
                    .scaledToFit()
                    .padding(size * 0.12)
            } else {
                Circle().fill(Color(hue: hue, saturation: 0.45, brightness: 0.5))
                Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                Text(initials)
                    .font(.system(size: size * 0.34, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.chalk)
            }
        }
        .frame(width: size, height: size)
        .task(id: url) {
            guard let url else { logo = nil; return }
            logo = await CrestLoader.shared.image(for: url)
        }
    }
}

struct ThemedToggle<Option: Hashable>: View {
    let options: [(value: Option, label: String)]
    @Binding var selection: Option
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options.indices, id: \.self) { index in
                let option = options[index]
                let isSelected = selection == option.value
                Button {
                    withAnimation(.snappy(duration: 0.22)) { selection = option.value }
                } label: {
                    Text(option.label)
                        .font(Theme.label(13, weight: .semibold))
                        .foregroundStyle(isSelected ? Color.black.opacity(0.85) : Theme.chalkMuted)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background {
                            if isSelected {
                                Capsule().fill(Theme.floodlight).matchedGeometryEffect(id: "pill", in: pill)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Capsule().fill(Theme.panelRaised))
        .overlay(Capsule().strokeBorder(Theme.stroke, lineWidth: 1))
    }
}

struct LeagueChip: View {
    let title: String
    let flag: String?
    let accent: Color
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let flag { Text(flag) }
                Text(title).font(Theme.label(13, weight: .semibold))
            }
            .foregroundStyle(selected ? Color.black.opacity(0.85) : Theme.chalk)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(selected ? accent : Theme.panelRaised))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Theme.stroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

struct GhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.label(13, weight: .medium))
            .foregroundStyle(Theme.chalk)
            .padding(.horizontal, 12)
            .frame(height: 32)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(configuration.isPressed ? Theme.panelRaised.opacity(0.6) : Theme.panelRaised))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Theme.stroke, lineWidth: 1))
    }
}

struct StarRating: View {
    let value: Int
    let onChange: (Int) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...3, id: \.self) { star in
                Button { onChange(value == star ? 0 : star) } label: {
                    Image(systemName: star <= value ? "star.fill" : "star")
                        .font(.system(size: 13))
                        .foregroundStyle(star <= value ? Theme.floodlight : Theme.chalkMuted.opacity(0.5))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Laukausten jakauma yhdellä silmäyksellä:
/// kirkas = maalia kohti ulkopuolelta, himmeä = muut ulkopuolelta, harmaa = rangaistusalueen sisältä.
struct ShotMixBar: View {
    let player: Player

    var body: some View {
        let total = Double(max(player.shots, 1))
        let hotOutside = Double(player.shotsOnTargetOutsideBox) / total
        let otherOutside = Double(max(0, player.shotsOutsideBox - player.shotsOnTargetOutsideBox)) / total
        let inside = max(0, 1 - hotOutside - otherOutside)

        GeometryReader { geo in
            HStack(spacing: 0) {
                Rectangle().fill(Theme.floodlight).frame(width: geo.size.width * hotOutside)
                Rectangle().fill(Theme.floodlight.opacity(0.35)).frame(width: geo.size.width * otherOutside)
                Rectangle().fill(Theme.chalk.opacity(0.2)).frame(width: geo.size.width * inside)
            }
            .clipShape(Capsule())
        }
        .frame(width: 64, height: 6)
        .help("Kirkas: maalia kohti ulkopuolelta · himmeä: muut ulkopuolelta · harmaa: rangaistusalueen sisältä")
    }
}

struct FilterMenu: View {
    let title: String
    let options: [String]
    @Binding var selection: String?

    var body: some View {
        Menu {
            Button("Kaikki") { selection = nil }
            Divider()
            ForEach(options, id: \.self) { option in
                Button(option) { selection = option }
            }
        } label: {
            HStack(spacing: 6) {
                Text(selection ?? title)
                    .font(Theme.label(13))
                    .foregroundStyle(selection == nil ? Theme.chalkMuted : Theme.chalk)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.chalkMuted)
            }
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.panelRaised))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.stroke, lineWidth: 1))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}
