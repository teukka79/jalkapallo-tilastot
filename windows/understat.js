'use strict';
// Understat-pelaajahaku (sama logiikka kuin tools/fetch_players.py): kausitilastot + laukaustapahtumat otteluista.
// Verkkokutsu annetaan ulkoa (getText), jotta moduulin voi testata ilman verkkoa.

const LEAGUES = { EPL: 'PL', La_liga: 'PD', Serie_A: 'SA', Ligue_1: 'FL1', Bundesliga: 'BL1' };

// Understatin joukkuenimet -> sovelluksen nimet (muut kulkevat sellaisenaan)
const TEAM_NAMES = {
  'Manchester City': 'Man City', 'Manchester United': 'Man United', 'Newcastle United': 'Newcastle',
  'Wolverhampton Wanderers': 'Wolves', 'Atletico Madrid': 'Atlético Madrid', 'Real Betis': 'Betis',
  Alaves: 'Alavés', 'AC Milan': 'Milan', 'Parma Calcio 1913': 'Parma', 'Paris Saint Germain': 'PSG',
  'Bayern Munich': 'Bayern München', 'Borussia Dortmund': 'Dortmund', 'Bayer Leverkusen': 'Leverkusen',
  'RasenBallsport Leipzig': 'RB Leipzig', 'VfB Stuttgart': 'Stuttgart', 'Borussia M.Gladbach': 'Gladbach',
  'Mainz 05': 'Mainz', 'FC Heidenheim': 'Heidenheim', 'FC Cologne': 'Köln'
};

// Rangaistusalue Understatin koordinaateissa (kenttä 105 x 68 m, alue 16,5 m x 40,32 m)
const BOX_X = (105 - 16.5) / 105;
const BOX_Y_MIN = (68 - 40.32) / 2 / 68;
const BOX_Y_MAX = 1 - BOX_Y_MIN;

const BASE = 'https://understat.com';

function defaultSeasonYear(now = new Date()) {
  return now.getMonth() >= 6 ? now.getFullYear() : now.getFullYear() - 1;
}

function mapPosition(raw) {
  const tokens = String(raw || '').split(/\s+/).filter((t) => t && t.toUpperCase() !== 'S');
  const first = (tokens[0] || 'M').toUpperCase();
  if (first.startsWith('GK')) return 'Maalivahti';
  if (first.startsWith('D')) return 'Puolustaja';
  if (first.startsWith('F')) return 'Hyökkääjä';
  return 'Keskikenttä';
}

// JSON.parse('\x7B\x22a\x22...') -> JS-merkkijonon purku ja JSON-jäsennys
function unescapeJsString(s) {
  return s.replace(/\\(x[0-9a-fA-F]{2}|u[0-9a-fA-F]{4}|[\s\S])/g, (_m, g) => {
    if (g[0] === 'x' && g.length === 3) return String.fromCharCode(parseInt(g.slice(1), 16));
    if (g[0] === 'u' && g.length === 5) return String.fromCharCode(parseInt(g.slice(1), 16));
    if (g === 'n') return '\n';
    if (g === 't') return '\t';
    if (g === 'r') return '\r';
    return g; // \\ \' \" \/
  });
}

function extractVar(html, name) {
  const re = new RegExp(`var\\s+${name}\\s*=\\s*JSON\\.parse\\(\\s*'((?:[^'\\\\]|\\\\[\\s\\S])*)'\\s*\\)`);
  const m = re.exec(String(html));
  if (!m) return null;
  try { return JSON.parse(unescapeJsString(m[1])); } catch { return null; }
}

const num = (v) => { const n = parseFloat(v); return Number.isFinite(n) ? n : 0; };

// Sarjan kausitiedot: ensin AJAX-rajapinta, sitten sivun upotettu data
async function loadLeague(getText, lg, year) {
  const ajaxUrl = `${BASE}/getLeagueData/${lg}/${year}`;
  const pageUrl = `${BASE}/league/${lg}/${year}`;
  try {
    const data = JSON.parse(await getText(ajaxUrl, { ajax: true, referer: pageUrl }));
    const players = Array.isArray(data.players) ? data.players : Object.values(data.players || {});
    const dates = Array.isArray(data.dates) ? data.dates : Object.values(data.dates || {});
    if (players.length) return { players, dates };
  } catch { /* kokeillaan sivua */ }
  const html = await getText(pageUrl, {});
  const players = extractVar(html, 'playersData');
  const dates = extractVar(html, 'datesData');
  if (!Array.isArray(players) || !players.length) throw new Error('pelaajadataa ei löytynyt');
  return { players, dates: Array.isArray(dates) ? dates : [] };
}

const RESULT_CODES = { goal: 'G', savedshot: 'S', missedshots: 'M', missedshot: 'M', blockedshot: 'B', shotonpost: 'P' };
const SITUATION_CODES = { openplay: 'O', fromcorner: 'C', setpiece: 'S', directfreekick: 'F', penalty: 'P' };
const letters = (v) => String(v || '').toLowerCase().replace(/[^a-z]/g, '');

// Ottelun laukaukset: [pelaajan id, X, Y, tulos, xG, minuutti, tilanne, puoli (h/a)]
function compactShots(data) {
  const src = data && data.shots ? data.shots : data;
  if (!src || (!Array.isArray(src.h) && !Array.isArray(src.a))) return null;
  const out = [];
  for (const s of [...(src.h || []), ...(src.a || [])]) {
    if (!s || s.player_id == null) continue;
    out.push([String(s.player_id), num(s.X), num(s.Y), String(s.result || ''), num(s.xG), parseInt(s.minute, 10) || 0, String(s.situation || ''), String(s.h_a || '')]);
  }
  return out;
}

// Ottelun kokoonpanot: [pelaajan id, pelatut minuutit, puoli (h/a)]
function compactRosters(data) {
  const src = data && data.rosters ? data.rosters : data;
  if (!src || typeof src !== 'object' || (!src.h && !src.a)) return null;
  const out = [];
  for (const side of ['h', 'a']) {
    const group = src[side];
    if (!group || typeof group !== 'object') continue;
    for (const v of Array.isArray(group) ? group : Object.values(group)) {
      const pid = v && (v.player_id != null ? v.player_id : v.id);
      if (pid == null) continue;
      out.push([String(pid), parseInt(v.time, 10) || 0, side]);
    }
  }
  return out.length ? out : null;
}

// Palauttaa { s: laukaukset, r: kokoonpanot tai null }
async function loadMatch(getText, matchId) {
  try {
    const json = JSON.parse(await getText(`${BASE}/getMatchData/${matchId}`, { ajax: true, referer: `${BASE}/match/${matchId}` }));
    const s = compactShots(json);
    if (s) return { s, r: compactRosters(json) };
  } catch { /* kokeillaan sivua */ }
  const html = await getText(`${BASE}/match/${matchId}`, {});
  const s = compactShots(extractVar(html, 'shotsData'));
  if (!s) throw new Error('laukauksia ei löytynyt');
  return { s, r: compactRosters(extractVar(html, 'rostersData')) };
}

async function pool(items, size, fn) {
  let i = 0;
  const workers = Array.from({ length: Math.min(size, items.length) }, async () => {
    while (i < items.length) { const item = items[i++]; await fn(item); }
  });
  await Promise.all(workers);
}

// Palauttaa { players, failed: [{ league, error }], fetchedMatches }. Cache: { [vuosi]: { [ottelu]: laukaukset } }
async function fetchPlayers({ getText, year = defaultSeasonYear(), cache = {}, onProgress = () => {}, concurrency = 4 }) {
  const seasonCache = (cache[year] = cache[year] || {});
  const players = [];
  const matchesOut = {}; // pelaajan tunnus -> [[päivä, vastustaja, maalit, laukaukset, kohti, ulkopuolelta, ulk. kohti, minuutit], ...]
  const shotsOut = {}; // pelaajan tunnus -> [[x, y, xG, minuutti, tulos, tilanne], ...]
  const failed = [];
  let fetchedMatches = 0;

  for (const [lg, code] of Object.entries(LEAGUES)) {
    try {
      onProgress({ text: `Haetaan ${code}: kausitilastot…` });
      const { players: raw, dates } = await loadLeague(getText, lg, year);
      const played = dates.filter((d) => d && (d.isResult === true || d.isResult === 'true')).map((d) => String(d.id));
      const meta = {};
      for (const d of dates) {
        if (d && d.id != null) meta[String(d.id)] = { date: String(d.datetime || '').slice(0, 10), h: d.h && d.h.title, a: d.a && d.a.title };
      }
      const todo = played.filter((id) => !seasonCache[id] || Array.isArray(seasonCache[id]));
      let done = 0, missing = 0;
      await pool(todo, concurrency, async (id) => {
        try { seasonCache[id] = await loadMatch(getText, id); fetchedMatches++; } catch { missing++; }
        done++;
        onProgress({ text: `Haetaan ${code}: laukaukset ${done}/${todo.length}` });
      });
      if (missing) throw new Error(`${missing} ottelun laukaukset puuttuvat`);

      const agg = new Map();
      const teamsOf = new Map(raw.map((r) => [String(r.id), String(r.team_title || '').split(',').map((t) => t.trim())]));
      const rows = new Map();
      for (const id of played) {
        const entry = seasonCache[id];
        const mm = meta[id] || {};
        const per = new Map();
        for (const [pid, x, y, resultRaw, xg, minute, situation, side] of entry.s || []) {
          const result = letters(resultRaw);
          if (result === 'owngoal') continue;
          const m = per.get(pid) || { g: 0, sh: 0, on: 0, out: 0, outOn: 0, side };
          m.sh++;
          if (result === 'goal') m.g++;
          if (result === 'goal' || result === 'savedshot') m.on++;
          if (!(x >= BOX_X && y >= BOX_Y_MIN && y <= BOX_Y_MAX)) { m.out++; if (result === 'goal' || result === 'savedshot') m.outOn++; }
          per.set(pid, m);
          (shotsOut[`${code}-${pid}`] = shotsOut[`${code}-${pid}`] || []).push([
            Math.round(x * 1000) / 1000, Math.round(y * 1000) / 1000, Math.round((xg || 0) * 1000) / 1000, minute || 0,
            RESULT_CODES[result] || 'M', SITUATION_CODES[letters(situation)] || 'O'
          ]);
          const a = agg.get(pid) || { shots: 0, on: 0, out: 0, outOn: 0 };
          const onTarget = result === 'goal' || result === 'savedshot';
          const inside = x >= BOX_X && y >= BOX_Y_MIN && y <= BOX_Y_MAX;
          a.shots++;
          if (onTarget) a.on++;
          if (!inside) { a.out++; if (onTarget) a.outOn++; }
          agg.set(pid, a);
        }
        // Pelatut ottelut: kokoonpanon mukaan; jos kokoonpanoa ei saatu, joukkueen kaikki ottelut
        const appeared = new Map();
        if (entry.r) for (const [pid, time, side] of entry.r) if (time > 0) appeared.set(pid, { min: time, side });
        for (const [pid, m] of per) if (!appeared.has(pid)) appeared.set(pid, { min: -1, side: m.side });
        if (!entry.r) {
          for (const [pid, teams] of teamsOf) {
            if (appeared.has(pid)) continue;
            if (teams.includes(mm.h)) appeared.set(pid, { min: -1, side: 'h' });
            else if (teams.includes(mm.a)) appeared.set(pid, { min: -1, side: 'a' });
          }
        }
        for (const [pid, info] of appeared) {
          const m = per.get(pid) || { g: 0, sh: 0, on: 0, out: 0, outOn: 0 };
          const opp = info.side === 'a' ? mm.h : info.side === 'h' ? mm.a : '';
          if (!opp || !mm.date) continue;
          (rows.get(pid) || rows.set(pid, []).get(pid)).push([mm.date, TEAM_NAMES[opp] || opp, m.g, m.sh, m.on, m.out, m.outOn, info.min]);
        }
      }
      for (const [pid, list] of rows) {
        list.sort((x, y) => (x[0] < y[0] ? -1 : x[0] > y[0] ? 1 : 0));
        matchesOut[`${code}-${pid}`] = list;
      }

      for (const r of raw) {
        const games = parseInt(r.games, 10) || 0;
        if (games < 1) continue;
        const goals = parseInt(r.goals, 10) || 0;
        const a = agg.get(String(r.id)) || { shots: 0, on: 0, out: 0, outOn: 0 };
        const teamRaw = String(r.team_title || '').split(',').pop().trim();
        const shots = Math.max(a.shots, goals);
        players.push({
          id: `${code}-${r.id}`,
          name: String(r.player_name),
          team: TEAM_NAMES[teamRaw] || teamRaw,
          league: code,
          nationality: '',
          position: mapPosition(r.position),
          appearances: games,
          goals,
          // Maali on aina laukaus ja kohti maalia, joten luvut pidetään keskenään johdonmukaisina.
          shots,
          shotsOnTarget: Math.min(Math.max(a.on, goals), shots),
          shotsOutsideBox: a.out,
          shotsOnTargetOutsideBox: a.outOn,
          xG: Math.round(num(r.xG) * 100) / 100,
          minutes: parseInt(r.time, 10) || 0
        });
      }
    } catch (e) {
      failed.push({ league: code, error: e && e.message ? e.message : String(e) });
    }
  }
  // Laukaukset vain pelaajille, jotka ovat mukana tuloksessa
  const known = new Set(players.map((p) => p.id));
  for (const id of Object.keys(shotsOut)) if (!known.has(id)) delete shotsOut[id];
  for (const id of Object.keys(matchesOut)) if (!known.has(id)) delete matchesOut[id];
  return { players, shots: shotsOut, matches: matchesOut, failed, fetchedMatches };
}

module.exports = { fetchPlayers, extractVar, unescapeJsString, mapPosition, defaultSeasonYear, LEAGUES };
