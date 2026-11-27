#!/usr/bin/env python3
"""Hakee pelaajien kausitilastot (Understat, varalla WhoScored) ja kirjoittaa ne sovelluksen tuontimuotoon (JSON).

Käyttö:
    pip3 install soccerdata pandas
    python3 tools/fetch_players.py                  # kuluva kausi -> players.json
    python3 tools/fetch_players.py --season 2526    # tietty kausi (2025-26)

Sovelluksessa Päivitä pelaajat -nappi ajaa tämän skriptin itse. Käsin ajettuna: Asetukset -> Tuo JSON… -> players.json
(laukauskartta tarvitsee lisäksi shots.json:n, jonka sovellus asentaa itse päivityksen yhteydessä).

Rangaistusalueen ulkopuoliset laukaukset lasketaan Understatin laukauskohtaisista
koordinaateista (x, y: 0-1, maali on x = 1). Rangaistusalue = x >= 88,5/105 ja
y välillä 0,2035-0,7965. Maalia kohti = maali tai torjuttu laukaus (torjuttu
puolustajaan ja ohi/tolppaan eivät ole maalia kohti).

Ensimmäinen ajo lataa jokaisen ottelun laukaukset (satoja kyselyjä per sarja) ja kestää
tovin; soccerdata tallentaa ne ~/soccerdata-kansioon, joten seuraavat ajot ovat nopeita.
Understat kattaa viisi suurta sarjaa. Mestarien liigaa ei ole, joten sen sarakkeet jäävät tyhjiksi.

Lähde (--source): auto (oletus) kokeilee Understatia ja siirtyy WhoScoreen, jos Understat ei vastaa;
understat tai whoscored pakottaa lähteen. WhoScore antaa laukausten koordinaatit (laukauskartta,
rangaistusalueen ulkopuoliset laukaukset), mutta ei xG:tä. Se käyttää Chrome-selainta (Selenium):
ensimmäinen ajo avaa jokaisen ottelun sivun ja kestää tunteja, mutta soccerdata tallentaa sivut
~/soccerdata-kansioon ja keskeytetty ajo jatkuu siitä mihin jäi.
"""
import argparse
import json
import re
import os
import ssl
import sys
import time
import urllib.request
from collections import Counter
from datetime import date
from pathlib import Path

try:  # macOS-Pythonilla ei aina ole SSL-varmenteita
    import certifi
    os.environ.setdefault("SSL_CERT_FILE", certifi.where())
except ImportError:
    pass

import pandas as pd
import soccerdata as sd

LEAGUES = {
    "ENG-Premier League": "PL",
    "ESP-La Liga": "PD",
    "ITA-Serie A": "SA",
    "FRA-Ligue 1": "FL1",
    "GER-Bundesliga": "BL1",
}

# FotMobin sarjatunnukset (MLS vain FotMobista ja ASA:sta)
FOTMOB_IDS = {"ENG-Premier League": 47, "ESP-La Liga": 87, "ITA-Serie A": 55, "FRA-Ligue 1": 53,
              "GER-Bundesliga": 54, "USA-MLS": 130}
ALL_CODES = {**LEAGUES, "USA-MLS": "MLS"}

# Understatin joukkuenimet -> sovelluksen nimet (muut nimet kulkevat sellaisenaan)
TEAM_NAMES = {
    "Manchester City": "Man City",
    "Manchester United": "Man United",
    "Newcastle United": "Newcastle",
    "Wolverhampton Wanderers": "Wolves",
    "Atletico Madrid": "Atlético Madrid",
    "Real Betis": "Betis",
    "Alaves": "Alavés",
    "AC Milan": "Milan",
    "Parma Calcio 1913": "Parma",
    "Paris Saint Germain": "PSG",
    "Bayern Munich": "Bayern München",
    "Borussia Dortmund": "Dortmund",
    "Bayer Leverkusen": "Leverkusen",
    "RasenBallsport Leipzig": "RB Leipzig",
    "VfB Stuttgart": "Stuttgart",
    "Borussia M.Gladbach": "Gladbach",
    "Mainz 05": "Mainz",
    "FC Heidenheim": "Heidenheim",
    "FC Cologne": "Köln",
    # WhoScored-nimet
    "Manchester City": "Man City",
    "Newcastle United": "Newcastle",
    "Paris Saint-Germain": "PSG",
    "Atletico Madrid": "Atlético Madrid",
    "Real Betis": "Betis",
    "Bayern Munich": "Bayern München",
    "RB Leipzig": "RB Leipzig",
    "Borussia Mönchengladbach": "Gladbach",
    "Borussia Monchengladbach": "Gladbach",
    "1. FSV Mainz 05": "Mainz",
    "FC Köln": "Köln",
    "1. FC Köln": "Köln",
    "1. FC Heidenheim": "Heidenheim",
    "FC St. Pauli": "St. Pauli",
    "VfL Wolfsburg": "Wolfsburg",
    "Eintracht Frankfurt": "Frankfurt",
    "SC Freiburg": "Freiburg",
    "TSG Hoffenheim": "Hoffenheim",
    "Werder Bremen": "Werder Bremen",
    "FC Augsburg": "Augsburg",
    "Union Berlin": "Union Berlin",
}

# Rangaistusalue Understatin koordinaateissa (kenttä 105 x 68 m, alue 16,5 m x 40,32 m)
BOX_X = (105 - 16.5) / 105
BOX_Y_MIN = (68 - 40.32) / 2 / 68
BOX_Y_MAX = 1 - BOX_Y_MIN


def default_season() -> str:
    today = date.today()
    start = today.year if today.month >= 7 else today.year - 1
    return f"{start % 100:02d}{(start + 1) % 100:02d}"


def map_position(raw) -> str:
    tokens = [t for t in str(raw).split() if t.upper() != "S"]
    first = (tokens[0] if tokens else "M").upper()
    if first.startswith("GK"):
        return "Maalivahti"
    if first.startswith("D"):
        return "Puolustaja"
    if first.startswith("F"):
        return "Hyökkääjä"
    return "Keskikenttä"


def require(df: pd.DataFrame, columns, label: str) -> None:
    missing = [c for c in columns if c not in df.columns]
    if missing:
        sys.exit(f"{label}: puuttuvat sarakkeet {missing}. Saatavilla: {list(df.columns)}")


def understat_alive() -> bool:
    """Nopea tarkistus: vastaako Understat ja onko sivusto päällä (se on ollut poissa käytöstä "We will come back soon")."""
    try:
        import certifi
        context = ssl.create_default_context(cafile=certifi.where())
    except ImportError:
        context = None
    try:
        request = urllib.request.Request("https://understat.com/league/EPL", headers={"User-Agent": "Mozilla/5.0"})
        with urllib.request.urlopen(request, timeout=15, context=context) as response:
            text = response.read(200_000).decode("utf-8", "ignore")
        return "come back soon" not in text and ("teamsData" in text or "playersData" in text)
    except Exception:
        return False


def load_understat(args):
    """Palauttaa (kausitilastot, laukaukset, funktio joka hakee ottelukohtaiset minuutit)."""
    understat = sd.Understat(leagues=selected_leagues(args), seasons=args.season)

    print("Haetaan pelaajien kausitilastot (Understat)…")
    season_stats = understat.read_player_season_stats().reset_index()
    require(season_stats, ["league", "team", "player", "position", "matches", "goals"], "Kausitilastot")

    print("Haetaan laukaustapahtumat (ensimmäinen ajo kestää)…")
    shots = understat.read_shot_events().reset_index()
    require(shots, ["league", "team", "player", "result", "location_x", "location_y"], "Laukaukset")
    return season_stats, shots, lambda: understat.read_player_match_stats().reset_index()


# ---------------------------------------------------------------- WhoScored

WS_RESULTS = {"Goal": "goal", "SavedShot": "savedshot", "MissedShots": "missedshots", "ShotOnPost": "shotonpost"}


def ws_position_code(raw: str) -> str:
    raw = str(raw or "")
    if raw == "GK":
        return "GK"
    if raw.startswith("FW"):
        return "F"
    if raw.startswith("D") and not raw.startswith("DM"):
        return "D"
    return "M"


def ws_situation(names: set) -> str:
    if "Penalty" in names:
        return "penalty"
    if "DirectFreekick" in names:
        return "directfreekick"
    if "FromCorner" in names:
        return "fromcorner"
    if "SetPiece" in names:
        return "setpiece"
    return "openplay"


def parse_ws_game(data: dict, league: str, game: str, home: str, away: str):
    """WhoScoredin matchCentreData -> (pelaajarivit, laukausrivit)."""
    events = [e for e in (data.get("events") or [])
              if (e.get("period") or {}).get("displayName") != "PenaltyShootout"]
    end = max([int(e.get("minute") or 0) for e in events] + [90])
    names = {int(k): v for k, v in (data.get("playerIdNameDictionary") or {}).items()}
    teams = {int(data[side]["teamId"]): (side, name) for side, name in (("home", home), ("away", away))}

    subs_on, subs_off, reds = {}, {}, {}
    for e in events:
        kind = (e.get("type") or {}).get("displayName")
        pid = e.get("playerId")
        if pid is None:
            continue
        minute = int(e.get("minute") or 0)
        if kind == "SubstitutionOn":
            subs_on[int(pid)] = minute
        elif kind == "SubstitutionOff":
            subs_off[int(pid)] = minute
        elif kind == "Card" and ((e.get("cardType") or {}).get("displayName") in ("Red", "SecondYellow")):
            reds[int(pid)] = minute

    rows, shot_rows = [], []
    for side, team, opponent in (("home", home, away), ("away", away, home)):
        for p in data[side].get("players") or []:
            pid = p.get("playerId")
            if pid is None:
                continue
            pid = int(pid)
            if p.get("isFirstEleven"):
                start = 0
            elif pid in subs_on:
                start = subs_on[pid]
            else:
                continue
            stop = min(subs_off.get(pid, end), reds.get(pid, end))
            rows.append({"league": league, "game": game, "team": team, "opponent": opponent,
                         "player_id": pid, "player": p.get("name") or names.get(pid, str(pid)),
                         "pos": str(p.get("position") or ""), "minutes": max(0, stop - start)})

    for e in events:
        if not e.get("isShot") or e.get("playerId") is None:
            continue
        qualifiers = {((q.get("type") or {}).get("displayName") or "") for q in (e.get("qualifiers") or [])}
        if "OwnGoal" in qualifiers:
            continue
        kind = (e.get("type") or {}).get("displayName")
        result = WS_RESULTS.get(kind)
        if result is None or e.get("x") is None or e.get("y") is None:
            continue
        if result == "savedshot" and "Blocked" in qualifiers:
            result = "blockedshot"
        team_id = e.get("teamId")
        if team_id is None or int(team_id) not in teams:
            continue
        side, team = teams[int(team_id)]
        pid = int(e["playerId"])
        shot_rows.append({"league": league, "game": game, "team": team, "player_id": pid,
                          "player": names.get(pid, str(pid)), "result": result,
                          "location_x": float(e["x"]) / 100.0, "location_y": float(e["y"]) / 100.0,
                          "xg": 0.0, "minute": int(e.get("minute") or 0), "situation": ws_situation(qualifiers)})
    return rows, shot_rows


def ws_cache_file(ws, game_row) -> Path:
    return Path(ws.data_dir) / "events" / f"{game_row['league']}_{game_row['season']}" / f"{game_row['game_id']}.json"


def ws_cache_state(path: Path) -> str:
    """'ok' = ottelun data tallessa, 'empty' = tyhjä tuore vastaus (ottelua ei vielä pelattu/peruttu), 'missing' = haettava."""
    try:
        if not path.exists():
            return "missing"
        text = path.read_text(encoding="utf-8", errors="ignore").strip()
        if text and text != "null":
            return "ok"
        return "empty" if time.time() - path.stat().st_mtime < 20 * 3600 else "missing"
    except OSError:
        return "missing"


# ---------------------------------------------------------------- FotMob

FM_POS = {0: "GK", 1: "DC", 2: "MC", 3: "FW"}
FM_SITUATIONS = {"RegularPlay": "openplay", "FastBreak": "openplay", "FromCorner": "fromcorner", "FreeKick": "directfreekick",
                 "SetPiece": "setpiece", "ThrowInSetPiece": "setpiece", "Penalty": "penalty"}


def fm_get(url: str) -> str:
    headers = {"User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36",
               "Accept-Language": "en-US,en;q=0.9"}
    try:
        import tls_requests
        response = tls_requests.get(url, headers=headers, timeout=40)
        if response.status_code != 200:
            raise ConnectionError(f"HTTP {response.status_code}")
        return response.text
    except ImportError:
        request = urllib.request.Request(url, headers=headers)
        with urllib.request.urlopen(request, timeout=40) as response:
            return response.read().decode("utf-8", "ignore")


def fm_next_data(html: str):
    match = re.search(r'<script id="__NEXT_DATA__"[^>]*>(.*?)</script>', html, re.S)
    if not match:
        raise ValueError("sivun dataa ei löytynyt")
    return json.loads(match.group(1))


def fm_walk(obj, visit) -> None:
    if isinstance(obj, dict):
        visit(obj)
        for value in obj.values():
            fm_walk(value, visit)
    elif isinstance(obj, list):
        for value in obj:
            fm_walk(value, visit)


def fm_window(code: str, season: str):
    """Kauden aikaväli: MLS kalenterivuosi, muut heinäkuusta kesäkuuhun."""
    start_year = 2000 + int(season[:2])
    today = date.today()
    if code == "MLS":
        year = today.year if season == default_season() and today.month >= 3 else start_year
        return f"{year}-01-01", f"{year}-12-31"
    return f"{start_year}-07-01", f"{start_year + 1}-06-30"


def fm_cache_dir() -> Path:
    path = Path.home() / "soccerdata" / "data" / "FotMob"
    path.mkdir(parents=True, exist_ok=True)
    return path


def fm_fixtures(league_id: int, window) -> list:
    page = fm_next_data(fm_get(f"https://www.fotmob.com/leagues/{league_id}/overview/x"))
    found = {}

    def visit(d):
        status = d.get("status")
        if "pageUrl" in d and isinstance(status, dict) and status.get("finished") and not status.get("cancelled"):
            when = str(status.get("utcTime") or "")[:10]
            match_id = str(d.get("matchId") or d.get("id") or d["pageUrl"].split("#")[-1])
            if window[0] <= when <= window[1]:
                found[match_id] = {"id": match_id, "url": d["pageUrl"], "date": when}

    fm_walk(page, visit)
    return sorted(found.values(), key=lambda f: f["date"])


def fm_parse(page: dict) -> dict:
    """FotMobin ottelusivu -> tiivis ottelutietue (laukaukset ja pelaajat)."""
    props = page["props"]["pageProps"]
    general, content = props["general"], props["content"]
    home, away = general["homeTeam"], general["awayTeam"]
    names = {int(home["id"]): home["name"], int(away["id"]): away["name"]}
    shots_in = [x for x in ((content.get("shotmap") or {}).get("shots") or []) if x.get("period") != "PenaltyShootout"]
    end = max([90] + [int(x.get("min") or 0) for x in shots_in])
    reds = {}
    for event in ((content.get("matchFacts") or {}).get("events") or {}).get("events", []) or []:
        if event.get("type") == "Card" and event.get("card") in ("Red", "YellowRed") and event.get("playerId"):
            reds[int(event["playerId"])] = int(event.get("time") or end)

    minutes = {}
    for pid, stats in (content.get("playerStats") or {}).items():
        for group in stats.get("stats") or []:
            value = ((group.get("stats") or {}).get("Minutes played") or {}).get("stat", {}).get("value")
            if value is not None:
                minutes[int(pid)] = int(value)

    players = []
    for side in ("homeTeam", "awayTeam"):
        team = (content.get("lineup") or {}).get(side) or {}
        team_id = int(team.get("id") or 0)
        for kind in ("starters", "subs"):
            for p in team.get(kind) or []:
                pid = int(p["id"])
                events = (p.get("performance") or {}).get("substitutionEvents") or []
                sub_in = next((int(e["time"]) for e in events if e.get("type") == "subIn"), None)
                sub_out = next((int(e["time"]) for e in events if e.get("type") == "subOut"), None)
                if kind == "starters":
                    start = 0
                elif sub_in is not None:
                    start = sub_in
                elif minutes.get(pid, 0) > 0:
                    start = end - minutes[pid]
                else:
                    continue
                stop = min(sub_out if sub_out is not None else end, reds.get(pid, end))
                played = minutes.get(pid) if minutes.get(pid) else max(0, stop - start)
                players.append({"id": pid, "name": p.get("name") or str(pid), "team": names.get(team_id, team.get("name", "")),
                                "pos": FM_POS.get(p.get("usualPlayingPositionId"), "MC"), "min": int(played)})

    shots = []
    for x in shots_in:
        if x.get("isOwnGoal") or x.get("x") is None or x.get("y") is None or x.get("playerId") is None:
            continue
        kind = x.get("eventType")
        if kind == "Goal":
            result = "goal"
        elif kind == "Post":
            result = "shotonpost"
        elif kind == "Miss":
            result = "missedshots"
        elif kind == "AttemptSaved":
            result = "blockedshot" if x.get("isBlocked") else "savedshot"
        elif kind and "block" in kind.lower():
            result = "blockedshot"
        else:
            result = "missedshots"
        shots.append({"pid": int(x["playerId"]), "name": x.get("fullName") or x.get("playerName") or str(x["playerId"]),
                      "team": names.get(int(x.get("teamId") or 0), ""), "res": result,
                      "x": float(x["x"]) / 105.0, "y": float(x["y"]) / 68.0, "xg": float(x.get("expectedGoals") or 0.0),
                      "min": int(x.get("min") or 0), "sit": FM_SITUATIONS.get(x.get("situation"), "openplay"),
                      "inside": bool(x.get("isFromInsideBox"))})
    return {"id": str(general["matchId"]), "date": str(general["matchTimeUTCDate"])[:10],
            "home": home["name"], "away": away["name"], "shots": shots, "players": players}


def fm_fetch_match(fixture: dict) -> dict:
    """Hakee ottelun ja varmistaa, että sivu on juuri pyydetty ottelu (FotMob ohittaa osoitteen #id-osan
    ja voi muuten palauttaa saman joukkueparin toisen ottelun)."""
    base = "https://www.fotmob.com" + fixture["url"].split("#")[0]
    last = None
    for url in (f"{base}?matchId={fixture['id']}", f"https://www.fotmob.com/match/{fixture['id']}"):
        try:
            record = fm_parse(fm_next_data(fm_get(url)))
        except Exception as exc:
            last = exc
            continue
        if record["id"] == str(fixture["id"]):
            return record
        last = ValueError(f"väärä ottelu ({record['id']})")
    raise last or ValueError("ottelua ei saatu")


def fm_cached(cache: Path, fixture: dict):
    """Välimuistin ottelu, jos tiedosto on olemassa ja sen id täsmää; muuten None."""
    path = cache / f"{fixture['id']}.json"
    try:
        record = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None
    return record if record.get("id") == str(fixture["id"]) else None


def load_fotmob(args):
    wanted = None
    if args.leagues:
        wanted = {c.strip().upper() for c in args.leagues.split(",") if c.strip()}
    leagues = [(name, ALL_CODES[name], league_id) for name, league_id in FOTMOB_IDS.items()
               if wanted is None or ALL_CODES[name] in wanted]
    if not leagues:
        sys.exit("FotMob: ei valittuja sarjoja")

    cache = fm_cache_dir()
    tasks = []
    for name, code, league_id in leagues:
        print(f"Haetaan ottelulista (FotMob): {code}…", flush=True)
        try:
            fixtures = fm_fixtures(league_id, fm_window(code, args.season))
        except Exception as exc:
            print(f"{code}: ottelulistaa ei saatu ({str(exc)[:80]})", flush=True)
            continue
        tasks += [(name, f) for f in fixtures]
    if not tasks:
        sys.exit("FotMob ei vastannut: otteluita ei löytynyt")

    missing = [t for t in tasks if fm_cached(cache, t[1]) is None]
    if args.max_new and len(missing) > args.max_new:
        missing = sorted(missing, key=lambda t: t[1]["date"], reverse=True)[: args.max_new]
    total, failures = len(missing), 0
    for i, (name, fixture) in enumerate(missing, 1):
        print(f"[{i}/{total}] FotMob: {fixture['date']} {fixture['url'].split('/')[2][:40]}", flush=True)
        try:
            record = fm_fetch_match(fixture)
            (cache / f"{fixture['id']}.json").write_text(json.dumps(record, ensure_ascii=False), encoding="utf-8")
        except Exception as exc:
            failures += 1
            print(f"Ottelun haku epäonnistui ({str(exc)[:80]})", flush=True)
            if failures >= 8 and failures == i:
                sys.exit("FotMob estää haun (8 ensimmäistä ottelua epäonnistui)")
        time.sleep(0.3)

    rows, shot_rows, parsed = [], [], 0
    for name, fixture in tasks:
        record = fm_cached(cache, fixture)
        if record is None:
            continue
        game = f"{record['date']} {record['home']}-{record['away']}"
        for p in record["players"]:
            rows.append({"league": name, "game": game, "team": p["team"],
                         "opponent": record["away"] if p["team"] == record["home"] else record["home"],
                         "player_id": p["id"], "player": p["name"], "pos": p["pos"], "minutes": p["min"]})
        for x in record["shots"]:
            shot_rows.append({"league": name, "game": game, "team": x["team"], "player_id": x["pid"], "player": x["name"],
                              "result": x["res"], "location_x": x["x"], "location_y": x["y"], "xg": x["xg"],
                              "minute": x["min"], "situation": x["sit"], "inside_box": x["inside"]})
        parsed += 1
    if parsed == 0 or not shot_rows:
        sys.exit("FotMob: otteludataa ei saatu luettua")
    print(f"FotMob: {parsed}/{len(tasks)} ottelua luettu", flush=True)
    return assemble_events(rows, shot_rows)


def selected_leagues(args) -> list:
    """--leagues PL,PD -> soccerdatan sarjanimet (oletus: kaikki viisi)."""
    if not args.leagues:
        return list(LEAGUES)
    wanted = {c.strip().upper() for c in args.leagues.split(",") if c.strip()}
    return [name for name, code in LEAGUES.items() if code in wanted]


def ws_open(args):
    leagues = selected_leagues(args)
    try:
        ws = sd.WhoScored(leagues=leagues, seasons=args.season, headless=not args.visible)
        schedule = ws.read_schedule().reset_index()
    except Exception as exc:
        sys.exit(f"WhoScored ei vastannut: {str(exc)[:150]}")
    require(schedule, ["league", "season", "game", "game_id", "date"], "WhoScored-otteluohjelma")
    when = pd.to_datetime(schedule["date"], utc=True, errors="coerce")
    finished = schedule[when < (pd.Timestamp.now(tz="UTC") - pd.Timedelta(hours=3))].copy()
    return ws, finished


def load_whoscored(args):
    import logging
    logging.getLogger("root").setLevel(logging.WARNING)  # soccerdatan omat "[1/1] Retrieving game" -rivit sotkisivat edistymispalkin
    print("Haetaan ottelulista (WhoScored)…")
    ws, finished = ws_open(args)
    if finished.empty:
        sys.exit("WhoScored: ei pelattuja otteluita valitulla kaudella")

    missing = [r for _, r in finished.iterrows() if ws_cache_state(ws_cache_file(ws, r)) == "missing"]
    if args.max_new and len(missing) > args.max_new:
        # uusimmat ensin, jotta tuoreet ottelut tulevat mukaan; loput haetaan seuraavilla ajoilla
        missing = sorted(missing, key=lambda r: str(r["date"]), reverse=True)[: args.max_new]
    total = len(missing)
    failures = 0
    for i, row in enumerate(missing, 1):
        print(f"[{i}/{total}] WhoScored: {str(row['game'])[:60]}", flush=True)
        try:
            ws.read_events(match_id=int(row["game_id"]), force_cache=True, output_fmt=None, on_error="skip")
        except Exception as exc:
            failures += 1
            print(f"Ottelun haku epäonnistui ({str(exc)[:80]})", flush=True)
            if failures >= 8 and failures == i:
                sys.exit("WhoScored estää haun (8 ensimmäistä ottelua epäonnistui). Kokeile --visible tai myöhemmin uudelleen.")

    rows, shot_rows, parsed = [], [], 0
    for _, row in finished.iterrows():
        path = ws_cache_file(ws, row)
        if ws_cache_state(path) != "ok":
            continue
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
            if not data:
                continue
            r, sh = parse_ws_game(data, row["league"], str(row["game"]), str(row["home_team"]), str(row["away_team"]))
        except Exception as exc:
            print(f"Ottelua {row['game_id']} ei voitu lukea: {str(exc)[:80]}", flush=True)
            continue
        rows += r
        shot_rows += sh
        parsed += 1
    if parsed == 0:
        sys.exit("WhoScored: yhtään ottelua ei saatu luettua")
    print(f"WhoScored: {parsed}/{len(finished)} ottelua luettu", flush=True)

    return assemble_events(rows, shot_rows)


def assemble_events(rows: list, shot_rows: list):
    """Pelaajarivit + laukausrivit -> (kausitilastot, laukaukset, ottelukohtaiset minuutit)."""
    played = pd.DataFrame(rows)
    shots = pd.DataFrame(shot_rows)
    if shots.empty:
        sys.exit("WhoScored: laukauksia ei löytynyt")

    # Pelaaja kuuluu kauden viimeisimpään joukkueeseensa (siirrot kesken kauden)
    played = played.sort_values("game")
    latest = played.groupby(["league", "player_id"])["team"].last()
    played["game_team"] = played["team"]
    played["team"] = [latest[(l, p)] for l, p in zip(played["league"], played["player_id"])]
    shots["team"] = [latest.get((l, p), t) for l, p, t in zip(shots["league"], shots["player_id"], shots["team"])]

    goals = shots[shots["result"] == "goal"].groupby(["league", "player_id"]).size()
    position = played[played["pos"].isin(["", "Sub"]) == False].groupby(["league", "player_id"])["pos"].agg(
        lambda s: Counter(ws_position_code(x) for x in s).most_common(1)[0][0])
    season = (played.groupby(["league", "player_id", "player"], as_index=False)
              .agg(team=("team", "last"), matches=("game", "size"), minutes=("minutes", "sum")))
    season["goals"] = [int(goals.get((l, p), 0)) for l, p in zip(season["league"], season["player_id"])]
    season["position"] = [position.get((l, p), "M") for l, p in zip(season["league"], season["player_id"])]
    if shots["xg"].sum() > 0:
        xg_sum = shots.groupby(["league", "player_id"])["xg"].sum()
        season["xg"] = [float(xg_sum.get((l, p), 0.0)) for l, p in zip(season["league"], season["player_id"])]
    return season, shots, lambda: played.drop(columns=["pos"])


def probe(args) -> None:
    """Hakee yhden pelatun ottelun ja tulostaa, mitä WhoScoredista saatiin (diagnostiikka)."""
    print("Avataan WhoScored (ensimmäinen kerta voi viedä minuutin)…")
    ws, finished = ws_open(args)
    row = finished.sort_values("date").iloc[-1]
    print(f"Ottelu: {row['game']} (id {row['game_id']}), pelattuja otteluita listassa: {len(finished)}")
    ws.read_events(match_id=int(row["game_id"]), force_cache=True, output_fmt=None, on_error="raise")
    path = ws_cache_file(ws, row)
    data = json.loads(path.read_text(encoding="utf-8"))
    print("Avaimet:", sorted(data.keys())[:25])
    rows, shot_rows = parse_ws_game(data, row["league"], str(row["game"]), str(row["home_team"]), str(row["away_team"]))
    print(f"Pelaajarivejä: {len(rows)}, laukauksia: {len(shot_rows)}")
    for r in rows[:4]:
        print("  pelaaja:", r)
    for r in shot_rows[:6]:
        print("  laukaus:", r)
    types = Counter((e.get("type") or {}).get("displayName") for e in data.get("events", []) if e.get("isShot"))
    print("Laukaustyypit:", dict(types))
    print("Joukkueet:", row["home_team"], "/", row["away_team"], "->", TEAM_NAMES.get(str(row["home_team"]), "(ei muunnosta)"))


def prepare_shots(shots: pd.DataFrame):
    result = shots["result"].astype(str).str.lower().str.replace(r"[^a-z]", "", regex=True)
    shots = shots[result != "owngoal"].copy()
    result = result[result != "owngoal"]
    shots["on_target"] = result.isin(["goal", "savedshot"])
    if "inside_box" in shots.columns:
        inside_box = shots["inside_box"].fillna(False).astype(bool)
    else:
        inside_box = (shots["location_x"] >= BOX_X) & shots["location_y"].between(BOX_Y_MIN, BOX_Y_MAX)
    shots["outside"] = ~inside_box
    shots["outside_on"] = shots["outside"] & shots["on_target"]
    return shots, result


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--season", default=default_season(), help="esim. 2526 = kausi 2025-26")
    parser.add_argument("--out", default="players.json")
    parser.add_argument("--shots-out", default=None, help="laukaustapahtumat (laukauskartta); oletus: shots.json --out-tiedoston viereen")
    parser.add_argument("--matches-out", default=None, help="pelatut ottelut (Viim. ottelut -sarake); oletus: matches.json --out-tiedoston viereen")
    parser.add_argument("--min-apps", type=int, default=1, help="pienin otteluiden määrä")
    parser.add_argument("--source", choices=["auto", "understat", "fotmob", "whoscored"], default="auto",
                        help="auto: Understat, jos se vastaa, muuten FotMob ja sen jälkeen WhoScored")
    parser.add_argument("--leagues", default=None, help="vain nämä sarjat, esim. PL,PD")
    parser.add_argument("--visible", action="store_true", help="WhoScored: näytä Chrome-ikkuna (headless-tilan esto)")
    parser.add_argument("--max-new", type=int, default=0, help="WhoScored: hae enintään näin monta uutta ottelua per ajo (0 = kaikki)")
    parser.add_argument("--probe", action="store_true", help="WhoScored: hae yksi ottelu ja tulosta rakenne")
    args = parser.parse_args()
    sys.stdout.reconfigure(line_buffering=True)  # sovellus näyttää etenemisen rivi kerrallaan

    if args.probe:
        probe(args)
        return

    wanted = {c.strip().upper() for c in args.leagues.split(",") if c.strip()} if args.leagues else None
    big5 = [c for c in LEAGUES.values() if wanted is None or c in wanted]
    loaders = {"understat": load_understat, "fotmob": load_fotmob, "whoscored": load_whoscored}
    if args.source == "auto":
        chain = []
        if big5 and understat_alive():
            chain.append("understat")
        else:
            print("Understat ei ole käytössä – haetaan FotMobista…", flush=True)
        chain.append("fotmob")
        if big5:
            chain.append("whoscored")
    else:
        chain = [args.source]
    loaded, last_error = None, None
    for source in chain:
        try:
            loaded = loaders[source](args)
            print(f"Lähde: {source}", flush=True)
            break
        except (Exception, SystemExit) as exc:
            last_error = exc
            print(f"{source}: {exc}", flush=True)
    if loaded is None:
        sys.exit(str(last_error) if last_error else "Yksikään lähde ei vastannut")
    season_stats, shots, get_match_stats = loaded

    shots, result = prepare_shots(shots)

    keys = ["league", "team", "player"]
    per_player = (
        shots.groupby(keys)
        .agg(shot_count=("on_target", "size"), on_target=("on_target", "sum"),
             outside=("outside", "sum"), outside_on=("outside_on", "sum"))
        .reset_index()
    )
    merged = season_stats.merge(per_player, on=keys, how="left").fillna(
        {"shot_count": 0, "on_target": 0, "outside": 0, "outside_on": 0}
    )

    players = []
    id_by_key = {}
    for row in merged.itertuples(index=False):
        league = ALL_CODES.get(row.league)
        if league is None or int(row.matches) < args.min_apps:
            continue
        pid = getattr(row, "player_id", None)
        team = TEAM_NAMES.get(row.team, row.team)
        player_id = f"{league}-{int(pid) if pd.notna(pid) else row.player}"
        id_by_key[(row.league, row.team, row.player)] = player_id
        id_by_key.setdefault((row.league, None, row.player), player_id)
        xg = getattr(row, "xg", None)
        minutes = getattr(row, "minutes", None)
        entry = {
            "id": player_id,
            "name": str(row.player),
            "team": team,
            "league": league,
            "nationality": "",
            "position": map_position(row.position),
            "appearances": int(row.matches),
            "goals": int(row.goals),
            # Maali on aina laukaus ja kohti maalia, joten luvut pidetään keskenään johdonmukaisina.
            "shots": int(max(row.shot_count, row.goals)),
            "shotsOnTarget": int(min(max(row.on_target, row.goals), max(row.shot_count, row.goals))),
            "shotsOutsideBox": int(row.outside),
            "shotsOnTargetOutsideBox": int(row.outside_on),
        }
        if xg is not None and pd.notna(xg):
            entry["xG"] = round(float(xg), 2)
        if minutes is not None and pd.notna(minutes):
            entry["minutes"] = int(minutes)
        players.append(entry)

    if not players:
        sys.exit("Ei pelaajia. Tarkista kausi (--season) ja verkkoyhteys.")

    with open(args.out, "w", encoding="utf-8") as f:
        json.dump(players, f, ensure_ascii=False, indent=1)
    print(f"Valmis: {len(players)} pelaajaa -> {args.out}", flush=True)

    shots_out = args.shots_out or os.path.join(os.path.dirname(os.path.abspath(args.out)), "shots.json")
    write_shots(shots, id_by_key, result, shots_out)

    matches_out = args.matches_out or os.path.join(os.path.dirname(os.path.abspath(args.out)), "matches.json")
    try:
        write_matches(get_match_stats(), shots, id_by_key, result, matches_out)
    except Exception as exc:  # sarake jää tyhjäksi, mutta pelaajat ja laukaukset on jo tallennettu
        print(f"Ottelukohtaisia tietoja ei saatu: {exc}", flush=True)


RESULT_CODES = {"goal": "G", "savedshot": "S", "missedshots": "M", "missedshot": "M",
                "blockedshot": "B", "shotonpost": "P"}
SITUATION_CODES = {"openplay": "O", "fromcorner": "C", "setpiece": "S", "directfreekick": "F", "penalty": "P"}


def player_id_for(id_by_key: dict, league, team, player):
    return id_by_key.get((league, team, player)) or id_by_key.get((league, None, player))


def write_shots(shots: pd.DataFrame, id_by_key: dict, normalized_result: pd.Series, path: str) -> None:
    """Kirjoittaa laukauskartan tiedot: {"shots": {pelaajan_id: [[x, y, xG, minuutti, tulos, tilanne], ...]}}."""
    situation = (shots["situation"].astype(str).str.lower().str.replace(r"[^a-z]", "", regex=True)
                 if "situation" in shots.columns else pd.Series("openplay", index=shots.index))
    xg = shots["xg"] if "xg" in shots.columns else pd.Series(0.0, index=shots.index)
    minute = shots["minute"] if "minute" in shots.columns else pd.Series(0, index=shots.index)

    by_player = {}
    for (league, team, player), x, y, g, m, res, sit in zip(
        zip(shots["league"], shots["team"], shots["player"]),
        shots["location_x"], shots["location_y"], xg, minute, normalized_result, situation,
    ):
        pid = player_id_for(id_by_key, league, team, player)
        if pid is None or pd.isna(x) or pd.isna(y):
            continue
        by_player.setdefault(pid, []).append([
            round(float(x), 3), round(float(y), 3),
            round(float(g), 3) if pd.notna(g) else 0.0,
            int(m) if pd.notna(m) else 0,
            RESULT_CODES.get(res, "M"), SITUATION_CODES.get(sit, "O"),
        ])
    with open(path, "w", encoding="utf-8") as f:
        json.dump({"shots": by_player}, f, separators=(",", ":"))
    print(f"Laukaukset: {sum(len(v) for v in by_player.values())} kpl -> {path}", flush=True)


def opponent_of(game: str, team: str) -> str:
    """soccerdatan ottelutunnus on muotoa 'YYYY-MM-DD Koti-Vieras'."""
    rest = game[11:] if len(game) > 11 else game
    if rest.startswith(team + "-"):
        return rest[len(team) + 1:]
    if rest.endswith("-" + team):
        return rest[: -len(team) - 1]
    return ""


def write_matches(stats: pd.DataFrame, shots: pd.DataFrame, id_by_key: dict, normalized_result: pd.Series, path: str) -> None:
    """Pelaajan pelatut ottelut: {"matches": {pelaajan_id: [[päivä, vastustaja, maalit, laukaukset, maalia kohti,
    ulkopuolelta, ulkopuolelta maalia kohti, minuutit], ...]}} aikajärjestyksessä."""
    keys = ["league", "game", "team", "player"]
    require(stats, keys + ["minutes"], "Ottelukohtaiset tilastot")
    require(shots, keys, "Laukaukset (ottelutunnus)")

    # Ottelukohtaisen tilaston omat sarakkeet (goals, shots, ...) eivät saa törmätä laukausten summiin, joten summat saavat s_-etuliitteen
    per = (
        shots.assign(is_goal=(normalized_result == "goal"))
        .groupby(keys)
        .agg(s_goals=("is_goal", "sum"), s_count=("on_target", "size"), s_on=("on_target", "sum"),
             s_out=("outside", "sum"), s_outon=("outside_on", "sum"))
        .reset_index()
    )
    wanted = keys + ["minutes"] + (["opponent"] if "opponent" in stats.columns else [])
    merged = stats[wanted].merge(per, on=keys, how="left").fillna(
        {"s_goals": 0, "s_count": 0, "s_on": 0, "s_out": 0, "s_outon": 0}
    )

    by_player = {}
    for row in merged.itertuples(index=False):
        minutes = int(row.minutes) if pd.notna(row.minutes) else 0
        if minutes <= 0 and row.s_count == 0:
            continue
        pid = player_id_for(id_by_key, row.league, row.team, row.player)
        if pid is None:
            continue
        game = str(row.game)
        opp = (getattr(row, "opponent", "") or opponent_of(game, str(row.team))) or "?"
        by_player.setdefault(pid, []).append([
            game[:10], TEAM_NAMES.get(opp, opp), int(row.s_goals), int(row.s_count), int(row.s_on),
            int(row.s_out), int(row.s_outon), minutes,
        ])
    for rows in by_player.values():
        rows.sort(key=lambda r: r[0])
    with open(path, "w", encoding="utf-8") as f:
        json.dump({"matches": by_player}, f, ensure_ascii=False, separators=(",", ":"))
    print(f"Ottelut: {sum(len(v) for v in by_player.values())} riviä -> {path}", flush=True)


if __name__ == "__main__":
    main()
