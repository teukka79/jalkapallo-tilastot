# Jalkapallotilastot (macOS, SwiftUI)

Tumma pelaajataulukko kuudelle sarjalle (Mestarien liiga, Valioliiga, La Liga, Serie A, Ligue 1, Bundesliiga)
sekä sarjataulukot ja otteluohjelmat. Samaa sukua kuin Jääkiekon Pistepörssi.

## Xcode-projektin luonti

```bash
brew install xcodegen
cd "~/Developer/Jalkapallo Tilastot"
xcodegen
open JalkapalloTilastot.xcodeproj
```

Valitse Signing & Capabilities -välilehdeltä oma Team ja paina Run. Vaatii macOS 14:n tai uudemman.

## Data

| Osa | Lähde |
|---|---|
| Sarjataulukot, otteluohjelmat | football-data.org (ilmainen API-avain, asetetaan appin asetuksissa). Ilman avainta esimerkkidata |
| Pelaajatilastot | Esimerkkidata tai oma JSON (Asetukset → Tuo JSON). Vie ensin esimerkki, niin saat oikean rakenteen |

Pelaajakohtaisia laukauksia rangaistusalueen ulkopuolelta ei löytynyt ilmaisesta rajapinnasta. Jos hankit
lähteen (esim. oma skripti NAS:lla), kirjoita sen tulos samaan JSON-muotoon.

## Rakenne

- `Models/` League, Player, Match + sarjataulukon laskenta
- `Services/` AppStore (tila, tallennus), FootballDataService (HTTP), SampleData
- `Views/` Players, Standings, Fixtures, Settings, yhteiset komponentit
- `Utilities/` Theme (värit, tausta), Format (suomalainen desimaalipilkku ja päivämäärät)

## Pelaajatilastojen päivitys (Understat)

Pelaajat-välilehden **Päivitä pelaajat** -nappi ajaa `tools/fetch_players.py`:n (virtuaaliympäristö `.venv`, `pip install soccerdata pandas`)
ja tuo tuloksen: laukaukset, xG, minuutit ja laukauskartan tiedot. Sovellus täydentää kansallisuudet football-data.orgista
(vaatii API-avaimen) ja päivittää tiedot käynnistyessä, jos ne ovat yli vuorokauden vanhat (asetuksista pois päältä).
Sandbox on poissa päältä, jotta sovellus voi käynnistää Pythonin.
