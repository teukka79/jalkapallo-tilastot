import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var importing = false
    @State private var exporting = false
    @State private var message: String?

    var body: some View {
        @Bindable var store = store

        VStack(alignment: .leading, spacing: 18) {
            Text("Asetukset").font(Theme.title(24)).foregroundStyle(Theme.chalk)

            VStack(alignment: .leading, spacing: 6) {
                Text("football-data.org API-avain").font(Theme.label(13, weight: .semibold))
                SecureField("Liitä avain tähän", text: $store.apiKey)
                    .textFieldStyle(.roundedBorder)
                Text("Ilmainen avain: football-data.org/client/register. Se antaa live-sarjataulukot ja otteluohjelmat kaikille kuudelle sarjalle (10 kyselyä minuutissa).")
                    .font(Theme.label(11))
                    .foregroundStyle(Theme.chalkMuted)
            }

            Divider().overlay(Theme.stroke)

            VStack(alignment: .leading, spacing: 8) {
                Text("Pelaajatilastot").font(Theme.label(13, weight: .semibold))
                Text(store.playersAreSample ? "Käytössä esimerkkidata" : "Käytössä tuotu data · \(store.players.count) pelaajaa")
                    .font(Theme.label(12))
                    .foregroundStyle(Theme.chalkMuted)
                HStack {
                    Button("Tuo JSON…") { importing = true }
                    Button("Vie JSON…") { exporting = true }
                    Button("Palauta esimerkkidata") {
                        store.resetToSample()
                        message = "Esimerkkidata palautettu"
                    }
                }
                .buttonStyle(GhostButtonStyle())
                if let message {
                    Text(message).font(Theme.label(12)).foregroundStyle(Theme.floodlight)
                }
            }

            Divider().overlay(Theme.stroke)

            VStack(alignment: .leading, spacing: 8) {
                Text("Sovelluksen kuvake").font(Theme.label(13, weight: .semibold))
                HStack(spacing: 14) {
                    ForEach(AppIconChoice.allCases) { choice in
                        Button { store.appIcon = choice } label: {
                            VStack(spacing: 6) {
                                Image(nsImage: NSImage(named: choice.imageName) ?? NSImage())
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 72, height: 72)
                                    .padding(6)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .strokeBorder(store.appIcon == choice ? Theme.floodlight : Color.clear, lineWidth: 2)
                                    )
                                Text(choice.title)
                                    .font(Theme.label(11))
                                    .foregroundStyle(store.appIcon == choice ? Theme.floodlight : Theme.chalkMuted)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                Text("Valinta näkyy Dockissa, kun appi on käynnissä. Finderissa näkyy aina Yökenttä.")
                    .font(Theme.label(11))
                    .foregroundStyle(Theme.chalkMuted)
            }

            HStack {
                Spacer()
                Button("Valmis") { dismiss() }.buttonStyle(GhostButtonStyle())
            }
        }
        .padding(24)
        .frame(width: 520)
        .background(Theme.background)
        .preferredColorScheme(.dark)
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            handleImport(result)
        }
        .fileExporter(isPresented: $exporting, document: PlayersDocument(data: store.exportData()),
                      contentType: .json, defaultFilename: "pelaajat") { result in
            if case .success = result { message = "Pelaajat viety" }
        }
    }

    private func handleImport(_ result: Result<URL, Error>) {
        switch result {
        case .failure(let error):
            message = error.localizedDescription
        case .success(let url):
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                try store.importPlayers(data: try Data(contentsOf: url))
                message = "Tuotu \(store.players.count) pelaajaa"
            } catch {
                message = "Tiedostoa ei voitu lukea. Tarkista rakenne viemällä esimerkki ensin."
            }
        }
    }
}
