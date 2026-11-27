'use strict';
// FotMob-pelaajahaku (sama logiikka kuin tools/fetch_players.py): ottelusivun __NEXT_DATA__ sisältää laukauskartan
// (koordinaatit, xG, isFromInsideBox), minuutit ja kokoonpanot. Ei API-avainta; sivu luetaan kuin selaimella.
// Verkko ja välimuisti annetaan ulkoa (getText, cacheGet, cacheSet), jotta moduulin voi testata ilman niitä.

const LEAGUES = [['PL', 47], ['PD', 87], ['SA', 55], ['FL1', 53], ['BL1', 54], ['MLS', 130]];

const TEAM_NAMES = {
  'Manchester City': 'Man City', 'Manchester United': 'Man United', 'Newcastle United': 'Newcastle',
  'Wolverhampton Wanderers': 'Wolves', 'Atletico Madrid': 'Atlético Madrid', 'Real Betis': 'Betis',
  Alaves: 'Alavés', 'AC Milan': 'Milan', 'Parma Calcio 1913': 'Parma', 'Paris Saint Germain': 'PSG',
  'Paris Saint-Germain': 'PSG', 'Bayern Munich': 'Bayern München', 'Borussia Dortmund': 'Dortmund',
  'Bayer Leverkusen': 'Leverkusen', 'RasenBallsport Leipzig': 'RB Leipzig', 'VfB Stuttgart': 'Stuttgart',
  'Borussia M.Gladbach': 'Gladbach', 'Borussia Mönchengladbach': 'Gladbach', 'Mainz 05': 'Mainz',
  'FC Heidenheim': 'Heidenheim', 'FC Cologne': 'Köln', '1. FC Köln': 'Köln', 'FC Köln': 'Köln'
};

const POS = { 0: 'Maalivahti', 1: 'Puolustaja', 2: 'Keskikenttä', 3: 'Hyökkääjä' };
const SITUATIONS = { RegularPlay: 'O', FastBreak: 'O', FromCorner: 'C', FreeKick: 'F', SetPiece: 'S', ThrowInSetPiece: 'S', Penalty: 'P' };
const RESULT_CODES = { goal: 'G', savedshot: 'S', missedshot: 'M', blockedshot: 'B', shotonpost: 'P' };

function nextData(html) {
  const m = /<script id="__NEXT_DATA__"[^>]*>([\s\S]*?)<\/script>/.exec(html);
  if (!m) throw new Error('sivun dataa ei löytynyt');
  return JSON.parse(m[1]);
}

function walk(obj, visit) {
  if (Array.isArray(obj)) { obj.forEach((v) => walk(v, visit)); return; }
  if (obj && typeof obj === 'object') {
    visit(obj);
    Object.values(obj).forEach((v) => walk(v, visit));
  }
}

// Kauden aikaväli: MLS kalenterivuosi, muut heinäkuusta kesäkuuhun. year = kauden aloitusvuosi (heinäkuusta alkava kausi).
function seasonWindow(code, year, now = new Date()) {
  if (code === 'MLS') {
    const y = now.getMonth() >= 2 ? now.getFullYear() : year;
    return [`${y}-01-01`, `${y}-12-31`];
  }
  return [`${year}-07-01`, `${year + 1}-06-30`];
}

async function loadFixtures(getText, leagueId, [from, to]) {
  const page = nextData(await getText(`https://www.fotmob.com/leagues/${leagueId}/overview/x`));
  const found = new Map();
  walk(page, (d) => {
    const st = d.status;
    if (d.pageUrl && st && typeof st === 'object' && st.finished && !st.cancelled) {
      const when = String(st.utcTime || '').slice(0, 10);
      if (when >= from && when <= to) {
        const id = String(d.matchId || d.id || String(d.pageUrl).split('#').pop());
        found.set(id, { id, url: d.pageUrl, date: when });
      }
    }
  });
  return [...found.values()].sort((a, b) => (a.date < b.date ? -1 : a.date > b.date ? 1 : 0));
}

// Ottelusivun pageProps -> tiivis ottelutietue
function parseMatch(props) {
  const general = props.general, content = props.content;
  const home = general.homeTeam, away = general.awayTeam;
  const names = { [home.id]: home.name, [away.id]: away.name };
  const shotsIn = ((content.shotmap && content.shotmap.shots) || []).filter((x) => x.period !== 'PenaltyShootout');
  const end = Math.max(90, ...shotsIn.map((x) => Number(x.min) || 0));
  const reds = {};
  const events = (content.matchFacts && content.matchFacts.events && content.matchFacts.events.events) || [];
  for (const e of events) {
    if (e.type === 'Card' && (e.card === 'Red' || e.card === 'YellowRed') && e.playerId) reds[e.playerId] = Number(e.time) || end;
  }
  const minutes = {};
  for (const [pid, st] of Object.entries(content.playerStats || {})) {
    for (const group of st.stats || []) {
      const mp = group.stats && group.stats['Minutes played'];
      const value = mp && mp.stat && mp.stat.value;
      if (value != null) minutes[pid] = Number(value);
    }
  }
  const players = [];
  for (const side of ['homeTeam', 'awayTeam']) {
    const team = (content.lineup && content.lineup[side]) || {};
    for (const kind of ['starters', 'subs']) {
      for (const p of team[kind] || []) {
        const ev = (p.performance && p.performance.substitutionEvents) || [];
        const subIn = (ev.find((e) => e.type === 'subIn') || {}).time;
        const subOut = (ev.find((e) => e.type === 'subOut') || {}).time;
        let start;
        if (kind === 'starters') start = 0;
        else if (subIn != null) start = Number(subIn);
        else if (minutes[p.id] > 0) start = end - minutes[p.id];
        else continue;
        const stop = Math.min(subOut != null ? Number(subOut) : end, reds[p.id] != null ? reds[p.id] : end);
        const played = minutes[p.id] ? minutes[p.id] : Math.max(0, stop - start);
        players.push({ id: p.id, name: p.name || String(p.id), team: names[team.id] || team.name || '',
          pos: POS[p.usualPlayingPositionId] ? p.usualPlayingPositionId : 2, min: played });
      }
    }
  }
  const shots = [];
  for (const x of shotsIn) {
    if (x.isOwnGoal || x.x == null || x.y == null || x.playerId == null) continue;
    let res;
    if (x.eventType === 'Goal') res = 'goal';
    else if (x.eventType === 'Post') res = 'shotonpost';
    else if (x.eventType === 'Miss') res = 'missedshot';
    else if (x.eventType === 'AttemptSaved') res = x.isBlocked ? 'blockedshot' : 'savedshot';
    else if (/block/i.test(String(x.eventType))) res = 'blockedshot';
    else res = 'missedshot';
    shots.push({ pid: x.playerId, name: x.fullName || x.playerName || String(x.playerId), team: names[x.teamId] || '', res,
      x: Number(x.x) / 105, y: Number(x.y) / 68, xg: Number(x.expectedGoals) || 0, min: Number(x.min) || 0,
      sit: SITUATIONS[x.situation] || 'O', inside: !!x.isFromInsideBox });
  }
  return { id: String(general.matchId), date: String(general.matchTimeUTCDate).slice(0, 10), home: home.name, away: away.name, shots, players };
}

async function pool(items, size, fn) {
  let i = 0;
  const workers = Array.from({ length: Math.min(size, items.length) }, async () => {
    while (i < items.length) { const item = items[i++]; await fn(item); }
  });
  await Promise.all(workers);
}

const r3 = (n) => Math.round(n * 1000) / 1000;

// Palauttaa { players, shots, matches, failed: [{ league, error }], fetchedMatches }
async function fetchPlayers({ getText, cacheGet, cacheSet, year, onProgress = () => {}, only = null, concurrency = 4, now = new Date() }) {
  const players = [], shotsOut = {}, matchesOut = {}, failed = [];
  let fetchedMatches = 0;
  const missingByLeague = {};
  const seasonYear = year != null ? year : (now.getMonth() >= 6 ? now.getFullYear() : now.getFullYear() - 1);

  for (const [code, leagueId] of LEAGUES) {
    if (only && code !== only) continue;
    try {
      onProgress({ text: `FotMob: ${code} ottelulista…` });
      const fixtures = await loadFixtures(getText, leagueId, seasonWindow(code, seasonYear, now));
      if (!fixtures.length) throw new Error('otteluita ei löytynyt');
      const records = new Map();
      const todo = [];
      for (const f of fixtures) {
        const cached = cacheGet(f.id);
        if (cached) records.set(f.id, cached); else todo.push(f);
      }
      let done = 0;
      let failedMatches = [];
      const fetchOne = async (f) => {
        const rec = parseMatch(nextData(await getText('https://www.fotmob.com' + f.url)).props.pageProps);
        cacheSet(f.id, rec);
        records.set(f.id, rec);
        fetchedMatches++;
      };
      await pool(todo, concurrency, async (f) => {
        try { await fetchOne(f); } catch { failedMatches.push(f); }
        done++;
        onProgress({ text: `FotMob: ${code} ottelut ${done}/${todo.length}` });
      });
      // Uusintakierrokset yksi kerrallaan ja viiveellä (nopeusrajoitukset)
      for (let pass = 1; pass <= 3 && failedMatches.length; pass++) {
        const again = failedMatches; failedMatches = [];
        let n = 0;
        for (const f of again) {
          await new Promise((r) => setTimeout(r, 600 * pass));
          try { await fetchOne(f); } catch { failedMatches.push(f); }
          n++;
          onProgress({ text: `FotMob: ${code} uusinta ${pass}/3 · ${n}/${again.length}` });
        }
      }
      const missing = failedMatches.length;
      missingByLeague[code] = missing;
      if (!records.size) throw new Error('yhtään ottelua ei saatu luettua');
      if (missing > todo.length / 2) throw new Error(`${missing} ottelun haku epäonnistui`);

      const acc = new Map();
      const get = (pid, name, team) => {
        let a = acc.get(pid);
        if (!a) { a = { id: `${code}-${pid}`, name, team, pos: {}, apps: 0, goals: 0, shots: 0, on: 0, out: 0, outOn: 0, xg: 0, minutes: 0, lines: [] }; acc.set(pid, a); }
        return a;
      };
      for (const rec of [...records.values()].sort((a, b) => (a.date < b.date ? -1 : a.date > b.date ? 1 : 0))) {
        const per = new Map();
        for (const s of rec.shots) {
          const a = get(s.pid, s.name, s.team);
          a.team = s.team || a.team;
          const onTarget = s.res === 'goal' || s.res === 'savedshot';
          const m = per.get(s.pid) || { g: 0, sh: 0, on: 0, out: 0, outOn: 0 };
          m.sh++; a.shots++; a.xg += s.xg;
          if (s.res === 'goal') { m.g++; a.goals++; }
          if (onTarget) { m.on++; a.on++; }
          if (!s.inside) { m.out++; a.out++; if (onTarget) { m.outOn++; a.outOn++; } }
          per.set(s.pid, m);
          (shotsOut[a.id] = shotsOut[a.id] || []).push([r3(s.x), r3(s.y), r3(s.xg), s.min, RESULT_CODES[s.res] || 'M', s.sit]);
        }
        const seen = new Set();
        for (const p of rec.players) {
          seen.add(p.id);
          const a = get(p.id, p.name, p.team);
          a.team = p.team || a.team;
          a.pos[p.pos] = (a.pos[p.pos] || 0) + 1;
          if (p.min > 0 || per.has(p.id)) a.apps++;
          a.minutes += p.min;
          const m = per.get(p.id) || { g: 0, sh: 0, on: 0, out: 0, outOn: 0 };
          const opp = p.team === rec.home ? rec.away : rec.home;
          a.lines.push([rec.date, TEAM_NAMES[opp] || opp, m.g, m.sh, m.on, m.out, m.outOn, p.min]);
        }
        // Laukaus ilman kokoonpanotietoa: pelaaja luetaan silti pelanneeksi
        for (const [pid, m] of per) {
          if (seen.has(pid)) continue;
          const a = acc.get(pid);
          const opp = a.team === rec.home ? rec.away : rec.home;
          a.apps++;
          a.lines.push([rec.date, TEAM_NAMES[opp] || opp, m.g, m.sh, m.on, m.out, m.outOn, 0]);
        }
      }
      for (const a of acc.values()) {
        if (a.apps < 1) continue;
        const top = Object.entries(a.pos).sort((x, y) => y[1] - x[1])[0];
        const shots = Math.max(a.shots, a.goals);
        players.push({
          id: a.id, name: a.name, team: TEAM_NAMES[a.team] || a.team, league: code, nationality: '',
          position: POS[top ? Number(top[0]) : 2] || 'Keskikenttä', appearances: a.apps, goals: a.goals,
          // Maali on aina laukaus ja kohti maalia, joten luvut pidetään keskenään johdonmukaisina.
          shots, shotsOnTarget: Math.min(Math.max(a.on, a.goals), shots),
          shotsOutsideBox: a.out, shotsOnTargetOutsideBox: a.outOn,
          xG: Math.round(a.xg * 100) / 100, minutes: a.minutes
        });
        a.lines.sort((x, y) => (x[0] < y[0] ? -1 : x[0] > y[0] ? 1 : 0));
        matchesOut[a.id] = a.lines;
      }
    } catch (e) {
      failed.push({ league: code, error: e && e.message ? e.message : String(e) });
    }
  }
  const known = new Set(players.map((p) => p.id));
  for (const id of Object.keys(shotsOut)) if (!known.has(id)) delete shotsOut[id];
  return { players, shots: shotsOut, matches: matchesOut, failed, fetchedMatches, missing: missingByLeague };
}

module.exports = { fetchPlayers, parseMatch, nextData, loadFixtures, seasonWindow, LEAGUES };
