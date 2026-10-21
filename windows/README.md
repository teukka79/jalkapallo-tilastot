# Jalkapallon Laukaustilasto – Windows

Windows-versio samasta sovelluksesta kuin macOS-versio (Electron + HTML/CSS/JS).
Ulkoasu, pelaajataulukko, sarjataulukot, otteluohjelmat, tähtiarvostelut ja kuvakevalitsin ovat samat.

## Asennuspaketin rakennus GitHub Actionsilla

1. Luo GitHubiin uusi (yksityinen) repo, esim. `jalkapallo-tilastot`.
2. Aja Macilla projektin kansiossa (ensimmäinen komento siirtää työnkulkutiedoston paikalleen):

   ```bash
   cd ~/Developer/"Jalkapallo Tilastot"
   mkdir -p .github/workflows && mv windows/build-windows.yml .github/workflows/
   git init -b main
   git add .
   git commit -m "Jalkapallon Laukaustilasto"
   git remote add origin https://github.com/teukka79/jalkapallo-tilastot.git
   git push -u origin main
   ```

3. GitHubissa: **Actions → Build Windows installer**. Rakennus käynnistyy pushista (tai painikkeesta *Run workflow*) ja kestää muutaman minuutin.
4. Valmis `Setup.exe` löytyy ajon sivun alaosasta kohdasta **Artifacts**.
5. Julkaisun saat tekemällä version tagin: `git tag v0.1.0 && git push origin v0.1.0`. Silloin asennustiedosto liitetään GitHubin Releases-sivulle.

Asennusohjelmaa ei ole allekirjoitettu, joten Windows SmartScreen voi varoittaa ("Lisätietoja → Suorita joka tapauksessa").

## Rakennus omalla Windows-koneella

Tarvitaan Node.js 20+.

```bash
cd windows
npm install
npm start        # kokeile sovellusta
npm run dist     # tekee dist\Jalkapallon-Laukaustilasto-Setup-<versio>.exe
```

## Data

- Sarjataulukot ja otteluohjelmat: ilmainen API-avain osoitteesta football-data.org/client/register, lisätään sovelluksen asetuksiin (⚙). Avain tallennetaan Windowsin salauksella. Ilman avainta näkyy esimerkkidata.
- Pelaajatilastot: esimerkkidata tai oma JSON (Asetukset → Tuo JSON). Vie ensin esimerkki, niin saat oikean rakenteen. JSON on sama kuin macOS-versiossa.
- Joukkueiden logot tulevat live-datan mukana; muuten näytetään nimikirjainmerkki.
- Asetukset ja tuodut pelaajat tallentuvat kansioon `%APPDATA%\Jalkapallon Laukaustilasto`.

## Rakenne

- `main.js` – ikkuna, tallennus, API-kutsut (vain sallitut football-data.org-osoitteet), tiedostodialogit
- `preload.js` – suojattu silta käyttöliittymän ja pääprosessin välillä
- `renderer/` – käyttöliittymä (`app.js`, `sample.js`, `styles.css`)
- `assets/icons/` – kolme kuvaketta; `build/icon.ico` on asennusohjelman ja pikakuvakkeen kuvake
