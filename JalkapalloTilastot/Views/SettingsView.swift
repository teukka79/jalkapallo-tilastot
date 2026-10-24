import SwiftUI
import UniformTypeIdentifiers

/// Vientitiedosto (JSON tai CSV)
struct ExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json, .commaSeparatedText] }
    var data: Data

    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var importingPlayers = false
    @State private var importingBackup = false
    @State private var choosingFolder = false
    @State private var exporting = false
    @State private var exportDocument = ExportDocument(data: Data())
    @State private var exportType: UTType = .json
    @State private var exportName = "pelaajat"
    @State private var message: String?

    var body: some View {
        @Bindable var store = store

        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Asetukset").font(Theme.title(24)).foregroundStyle(Theme.chalk)

                    keySection(title: "football-data.org API-avain", text: $store.apiKey,
                               hint: "Ilmainen avain: football-data.org/client/register. Antaa live-sarjataulukot, otteluohjelmat, maalit ja pelaajien kansallisuudet (10 kyselyä minuutissa).")

                    keySection(title: "API-Football -avain (ottelutilastot)", text: $store.apiFootballKey,
                               hint: "Valinnainen. Ilmainen tili osoitteessa api-football.com (100 kyselyä päivässä). Tarvitaan oikeiden otteluiden tilastoihin; kaksi kyselyä per ottelu, haetut tallennetaan.")

                    keySection(title: "The Odds API -avain (vedonlyöntikertoimet)", text: $store.oddsKey,
                               hint: "Valinnainen. Ilmainen avain osoitteessa the-odds-api.com (noin 500 krediittiä kuussa). Yksi sarjan haku maksaa 2 krediittiä; kertoimet tallennetaan 6 tunniksi, joten kiintiö riittää normaalikäyttöön."
                               + (store.oddsRemaining.map { " Krediittejä jäljellä: \($0)." } ?? "")
                               + (store.oddsError.map { "\n\($0)" } ?? ""))

                    Divider().overlay(Theme.stroke)
                    playersSection(autoUpdate: $store.autoUpdatePlayers, folder: $store.toolsFolder)

                    Divider().overlay(Theme.stroke)
                    userDataSection

                    Divider().overlay(Theme.stroke)
                    iconSection
                }
                .padding(24)
            }

            Divider().overlay(Theme.stroke)
            HStack {
                if let message {
                    Text(message).font(Theme.label(12)).foregroundStyle(Theme.floodlight)
                }
                Spacer()
                Button("Valmis") { dismiss() }.buttonStyle(GhostButtonStyle())
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
        }
        .frame(width: 560, height: 700)
        .background(Theme.background)
        .preferredColorScheme(.dark)
        .background {
            Color.clear.fileImporter(isPresented: $importingPlayers, allowedContentTypes: [.json]) { result in
                handleImport(result, backup: false)
            }
        }
        .background {
            Color.clear.fileImporter(isPresented: $importingBackup, allowedContentTypes: [.json]) { result in
                handleImport(result, backup: true)
            }
        }
        .background {
            Color.clear.fileImporter(isPresented: $choosingFolder, allowedContentTypes: [.folder]) { result in
                if case .success(let url) = result { store.toolsFolder = url.path }
            }
        }
        .background {
            Color.clear.fileExporter(isPresented: $exporting, document: exportDocument,
                                     contentType: exportType, defaultFilename: exportName) { result in
                if case .success = result { message = "Tiedosto tallennettu" }
            }
        }
    }

    // MARK: Osiot

    private func keySection(title: String, text: Binding<String>, hint: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(Theme.label(13, weight: .semibold))
            SecureField("Liitä avain tähän", text: text)
                .themedField()
            Text(hint).font(Theme.label(11)).foregroundStyle(Theme.chalkMuted)
        }
    }

    private func playersSection(autoUpdate: Binding<Bool>, folder: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Pelaajatilastot").font(Theme.label(13, weight: .semibold))
            Text(store.playersAreSample ? "Käytössä esimerkkidata" : "Käytössä tuotu data · \(store.players.count) pelaajaa")
                .font(Theme.label(12))
                .foregroundStyle(Theme.chalkMuted)
            HStack {
                Button("Tuo JSON…") { importingPlayers = true }
                Button("Vie JSON…") { startExport(store.exportData(), .json, "pelaajat") }
                Button("Vie CSV…") { startExport(store.exportCSV(), .commaSeparatedText, "pelaajat") }
                Button("Palauta esimerkkidata") {
                    store.resetToSample()
                    message = "Esimerkkidata palautettu"
                }
            }
            .buttonStyle(GhostButtonStyle())

            Text("Päivityksen projektikansio").font(Theme.label(12, weight: .semibold)).padding(.top, 6)
            HStack {
                TextField("~/Developer/Jalkapallo Tilastot", text: folder)
                    .themedField()
                Button("Valitse…") { choosingFolder = true }.buttonStyle(GhostButtonStyle())
            }
            Text("Kansio, jossa .venv ja tools/fetch_players.py ovat. Pelaajat-välilehden Päivitä pelaajat -nappi ajaa skriptin ja tuo tulokset.")
                .font(Theme.label(11))
                .foregroundStyle(Theme.chalkMuted)

            Toggle("Päivitä pelaajat automaattisesti käynnistyessä, kun data on yli vuorokauden vanhaa", isOn: autoUpdate)
                .toggleStyle(ThemedSwitchStyle())
                .font(Theme.label(12))
        }
    }

    private var userDataSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Omat tiedot").font(Theme.label(13, weight: .semibold))
            Text("\(store.ratedCount) arvosteltua · \(store.watchlist.count) seurattavaa · \(store.notes.count) muistiinpanoa · \(store.savedViews.count) näkymää")
                .font(Theme.label(12))
                .foregroundStyle(Theme.chalkMuted)
            HStack {
                Button("Vie varmuuskopio…") { startExport(store.exportUserData(), .json, "omat-tiedot") }
                Button("Tuo varmuuskopio…") { importingBackup = true }
            }
            .buttonStyle(GhostButtonStyle())
            Text("Tähdet, seurattavat, muistiinpanot ja tallennetut näkymät. Tuonti korvaa nykyiset.")
                .font(Theme.label(11))
                .foregroundStyle(Theme.chalkMuted)
        }
    }

    private var iconSection: some View {
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
    }

    // MARK: Toiminnot

    private func startExport(_ data: Data, _ type: UTType, _ name: String) {
        exportDocument = ExportDocument(data: data)
        exportType = type
        exportName = name
        exporting = true
    }

    private func handleImport(_ result: Result<URL, Error>, backup: Bool) {
        switch result {
        case .failure(let error):
            message = error.localizedDescription
        case .success(let url):
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                if backup {
                    try store.importUserData(data)
                    message = "Omat tiedot tuotu"
                } else {
                    try store.importPlayers(data: data)
                    message = "Tuotu \(store.players.count) pelaajaa"
                }
            } catch {
                message = "Tiedostoa ei voitu lukea. Tarkista rakenne viemällä esimerkki ensin."
            }
        }
    }
}
