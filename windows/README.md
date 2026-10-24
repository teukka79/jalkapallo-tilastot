# Jalkapallotilastot – Windows

Windows-versio samasta sovelluksesta kuin macOS-versio (Electron + HTML/CSS/JS).

## Mitä sovelluksessa on

- **Yksitoista sarjaa:** Mestarien liiga, Eurooppa-liiga, Konferenssiliiga, Valioliiga, La Liga, Serie A, Ligue 1, Bundesliiga, Saudi Pro League, MLS ja Süper Lig.
- **Sarjataulukko:** Taulukko (Kunto-merkit V/T/H ja ? = seuraava ottelu), Yli/Alle (rajat 0.5–6.5) ja HT/FT. Kaikissa lajittelu otsikoista ja selitteet hiirellä, rajaus yhteensä / kotona / vieraissa. Rivin napautus avaa joukkueen viimeiset ottelut.
- **Otteluohjelma:** menneet päivät piilossa oletuksena (kytkimestä näkyviin), "Kaikki"-valinta näyttää vain tämän päivän ottelut, "Vain meneillään" -suodatin ja vedonlyöntikertoimet pelaamattomille otteluille.
- **Ottelun tilastoikkuna:** pelatun tai käynnissä olevan ottelun rivin klikkaus avaa tilastot (pallonhallinta, laukaukset, kulmat, syötöt, kortit jne.), maalintekijät ja joukkueiden viimeisimmät tulokset. Tilastot haetaan ESPN:ltä kaikille sarjoille, ja valmiit ottelut tallentuvat välimuistiin.
- **Pelaajatilastot:** viidelle suurimmalle liigalle (esimerkkidata tai oma JSON).

## Asennuspaketin rakennus GitHub Actionsilla

Työnkulku on tiedostossa `.github/workflows/build-windows.yml`. Kun muutokset on pushattu `main`-haaraan:

1. GitHubissa: **Actions → Build Windows installer** käynnistyy pushista (tai painikkeesta *Run workflow*) ja kestää muutaman minuutin.
2. Valmis `Jalkapallotilastot-Setup-<versio>.exe` löytyy ajon sivun alaosasta kohdasta **Artifacts**.
3. Julkaisun saat tekemällä version tagin: `git tag v0.2.0 && git push origin v0.2.0`. Silloin asennustiedosto liitetään GitHubin Releases-sivulle.

Asennusohjelmaa ei ole allekirjoitettu, joten Windows SmartScreen voi varoittaa ("Lisätietoja → Suorita joka tapauksessa").

## Rakennus omalla Windows-koneella

Tarvitaan Node.js 20+.

```bash
cd windows
npm install
npm start        # kokeile sovellusta
npm run dist     # tekee dist\Jalkapallotilastot-Setup-<versio>.exe
```

## Data

- **football-data.org** (Mestarien liiga, Valioliiga, La Liga, Serie A, Ligue 1, Bundesliiga): ilmainen API-avain osoitteesta football-data.org/client/register, lisätään asetuksiin (⚙).
- **ESPN** (Eurooppa-liiga, Konferenssiliiga, Saudi Pro League, MLS, Süper Lig): julkinen, epävirallinen rajapinta ilman avainta. Puoliaikatulokset ja logot tulevat samasta lähteestä.
- **Kertoimet:** valinnainen The Odds API -avain (the-odds-api.com, ilmainen taso ~500 krediittiä kuussa). Yksi sarjan haku maksaa 2 krediittiä, ja haetut kertoimet tallennetaan 6 tunniksi.
- Avaimet tallennetaan Windowsin salauksella. Ilman avaimia näkyy esimerkkidata niille sarjoille, joille live-dataa ei saada.
- Pelaajatilastot: esimerkkidata tai oma JSON (Asetukset → Tuo JSON). Vie ensin esimerkki, niin saat oikean rakenteen. JSON on sama kuin macOS-versiossa.
- Asetukset, kertoimien välimuisti ja tuodut pelaajat tallentuvat kansioon `%APPDATA%\Jalkapallon Laukaustilasto` (vanha kansio säilytetään, jotta avain ja arvostelut eivät katoa nimenvaihdossa).

## Rakenne

- `main.js` – ikkuna, tallennus, API-kutsut (vain sallitut osoitteet: football-data.org, ESPN, The Odds API), kertoimien välimuisti, tiedostodialogit
- `preload.js` – suojattu silta käyttöliittymän ja pääprosessin välillä
- `renderer/` – käyttöliittymä (`app.js`, `sample.js`, `styles.css`)
- `assets/icons/` – kolme kuvaketta; `build/icon.ico` on asennusohjelman ja pikakuvakkeen kuvake
