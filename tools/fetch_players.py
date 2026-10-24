#!/usr/bin/env python3
"""Hakee pelaajien kausitilastot Understatista ja kirjoittaa ne sovelluksen tuontimuotoon (JSON).

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
"""
import argparse
import json
import os
import sys
from datetime import date

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


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--season", default=default_season(), help="esim. 2526 = kausi 2025-26")
    parser.add_argument("--out", default="players.json")
    parser.add_argument("--shots-out", default=None, help="laukaustapahtumat (laukauskartta); oletus: shots.json --out-tiedoston viereen")
    parser.add_argument("--matches-out", default=None, help="pelatut ottelut (Viim. ottelut -sarake); oletus: matches.json --out-tiedoston viereen")
    parser.add_argument("--min-apps", type=int, default=1, help="pienin otteluiden määrä")
    args = parser.parse_args()
    sys.stdout.reconfigure(line_buffering=True)  # sovellus näyttää etenemisen rivi kerrallaan

    understat = sd.Understat(leagues=list(LEAGUES), seasons=args.season)

    print("Haetaan pelaajien kausitilastot…")
    season_stats = understat.read_player_season_stats().reset_index()
    require(season_stats, ["league", "team", "player", "position", "matches", "goals"], "Kausitilastot")

    print("Haetaan laukaustapahtumat (ensimmäinen ajo kestää)…")
    shots = understat.read_shot_events().reset_index()
    require(shots, ["league", "team", "player", "result", "location_x", "location_y"], "Laukaukset")

    result = shots["result"].astype(str).str.lower().str.replace(r"[^a-z]", "", regex=True)
    shots = shots[result != "owngoal"].copy()
    result = result[result != "owngoal"]
    shots["on_target"] = result.isin(["goal", "savedshot"])
    inside_box = (shots["location_x"] >= BOX_X) & shots["location_y"].between(BOX_Y_MIN, BOX_Y_MAX)
    shots["outside"] = ~inside_box
    shots["outside_on"] = shots["outside"] & shots["on_target"]

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
        league = LEAGUES.get(row.league)
        if league is None or int(row.matches) < args.min_apps:
            continue
        pid = getattr(row, "player_id", None)
        team = TEAM_NAMES.get(row.team, row.team)
        player_id = f"{league}-{int(pid) if pd.notna(pid) else row.player}"
        id_by_key[(row.league, row.team, row.player)] = player_id
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
        write_matches(understat, shots, id_by_key, result, matches_out)
    except Exception as exc:  # sarake jää tyhjäksi, mutta pelaajat ja laukaukset on jo tallennettu
        print(f"Ottelukohtaisia tietoja ei saatu: {exc}", flush=True)


RESULT_CODES = {"goal": "G", "savedshot": "S", "missedshots": "M", "missedshot": "M",
                "blockedshot": "B", "shotonpost": "P"}
SITUATION_CODES = {"openplay": "O", "fromcorner": "C", "setpiece": "S", "directfreekick": "F", "penalty": "P"}


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
        pid = id_by_key.get((league, team, player))
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


def write_matches(understat, shots: pd.DataFrame, id_by_key: dict, normalized_result: pd.Series, path: str) -> None:
    """Pelaajan pelatut ottelut: {"matches": {pelaajan_id: [[päivä, vastustaja, maalit, laukaukset, maalia kohti,
    ulkopuolelta, ulkopuolelta maalia kohti, minuutit], ...]}} aikajärjestyksessä."""
    stats = understat.read_player_match_stats().reset_index()
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
    merged = stats[keys + ["minutes"]].merge(per, on=keys, how="left").fillna(
        {"s_goals": 0, "s_count": 0, "s_on": 0, "s_out": 0, "s_outon": 0}
    )

    by_player = {}
    for row in merged.itertuples(index=False):
        minutes = int(row.minutes) if pd.notna(row.minutes) else 0
        if minutes <= 0 and row.s_count == 0:
            continue
        pid = id_by_key.get((row.league, row.team, row.player))
        if pid is None:
            continue
        game = str(row.game)
        opp = opponent_of(game, str(row.team)) or "?"
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
