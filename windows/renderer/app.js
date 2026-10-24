'use strict';

const LEAGUES = [
  { code: 'CL', name: 'Mestarien liiga', flag: 'EU', accent: '#5AA9FF', src: 'fd', slug: 'uefa.champions', odds: 'soccer_uefa_champs_league', zones: 'cup' },
  { code: 'EL', name: 'Eurooppa-liiga', flag: 'EU', accent: '#FF9F43', src: 'espn', slug: 'uefa.europa', odds: 'soccer_uefa_europa_league', zones: 'cup' },
  { code: 'UECL', name: 'Konferenssiliiga', flag: 'EU', accent: '#37C98B', src: 'espn', slug: 'uefa.europa.conf', odds: 'soccer_uefa_europa_conference_league', zones: 'cup' },
  { code: 'PL', name: 'Valioliiga', flag: 'GB', accent: '#9B7BFF', src: 'fd', slug: 'eng.1', odds: 'soccer_epl', stats: true },
  { code: 'PD', name: 'La Liga', flag: 'ES', accent: '#FF7A59', src: 'fd', slug: 'esp.1', odds: 'soccer_spain_la_liga', stats: true },
  { code: 'SA', name: 'Serie A', flag: 'IT', accent: '#3FD0C9', src: 'fd', slug: 'ita.1', odds: 'soccer_italy_serie_a', stats: true },
  { code: 'FL1', name: 'Ligue 1', flag: 'FR', accent: '#D6E85A', src: 'fd', slug: 'fra.1', odds: 'soccer_france_ligue_one', stats: true },
  { code: 'BL1', name: 'Bundesliiga', flag: 'DE', accent: '#FF5C7A', src: 'fd', slug: 'ger.1', odds: 'soccer_germany_bundesliga', stats: true },
  { code: 'SPL', name: 'Saudi Pro League', flag: 'SA', accent: '#E8D08A', src: 'espn', slug: 'ksa.1', odds: 'soccer_saudi_arabia_pro_league', zones: 'none' },
  { code: 'MLS', name: 'MLS', flag: 'US', accent: '#8DA2FB', src: 'espn', slug: 'usa.1', odds: 'soccer_usa_mls', zones: 'none', calendarSeason: true },
  { code: 'TUR', name: 'Süper Lig', flag: 'TR', accent: '#E5484D', src: 'espn', slug: 'tur.1', odds: 'soccer_turkey_super_league' }
];
const POSITIONS = ['Maalivahti', 'Puolustaja', 'Keskikenttä', 'Hyökkääjä'];
const ICONS = [
  { id: 'night', title: 'Yökenttä', file: 'IconA.png' },
  { id: 'floodlight', title: 'Valonheitin', file: 'IconB.png' },
  { id: 'pitchLine', title: 'Kenttäviiva', file: 'IconC.png' }
];
const LINES = [0.5, 1.5, 2.5, 3.5, 4.5, 5.5, 6.5];
const HTFT = [['V/V', 'WW'], ['V/T', 'WD'], ['V/H', 'WL'], ['T/V', 'DW'], ['T/T', 'DD'], ['T/H', 'DL'], ['H/V', 'LW'], ['H/T', 'LD'], ['H/H', 'LL']];
const SORTS = {
  name: (p) => p.name, team: (p) => p.team,
  appearances: (p) => p.appearances, goals: (p) => p.goals, shots: (p) => p.shots,
  shotsOnTarget: (p) => p.shotsOnTarget, shotsOnTargetOutsideBox: (p) => p.shotsOnTargetOutsideBox,
  shotsOutsideBox: (p) => p.shotsOutsideBox, onTargetPercent: (p) => onTargetPct(p), perGame: (p) => perGame(p)
};
const leagueOf = (code) => LEAGUES.find((l) => l.code === code);

const S = {
  league: null, section: 'players',
  players: [], playersSource: 'none', playersUpdated: null, playersPartial: false, updatingPlayers: false, playersStatus: '', playersNote: '', nationalities: {}, enriching: false,
  matches: {}, standings: {}, crests: {}, crestsBy: {}, playerModal: null, live: {}, updatedAt: {},
  today: [], todayLive: {}, todayUpdated: null, loadingToday: false,
  loading: false, error: null,
  ratings: {}, apiKey: '', oddsKey: '', oddsRemaining: null, oddsError: '', odds: {}, icon: 'night',
  search: '', team: '', position: '', favOnly: false, sort: 'goals', asc: false,
  matchday: 1, hidePast: true, liveOnly: false,
  stMode: 'table', venue: 'all', line: 2.5, st: { key: 'position', asc: true },
  teamModal: null, matchModal: null, mstats: {}, settingsOpen: false, message: ''
};
const focus = () => S.league || 'PL';
// football-data.org vain, jos avain on annettu; muuten kaikki sarjat haetaan ESPN:ltä (ei avainta).
const srcOf = (lg) => (lg.src === 'fd' && S.apiKey.trim() ? 'fd' : 'espn');

// ---------- apurit ----------

const esc = (v) => String(v ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const num = (x) => (Number.isFinite(+x) ? +x : 0);
const onTargetPct = (p) => (p.shots > 0 ? (p.shotsOnTarget / p.shots) * 100 : 0);
const perGame = (p) => (p.appearances > 0 ? p.shots / p.appearances : 0);
const fmt1 = (v) => v.toLocaleString('fi-FI', { minimumFractionDigits: 1, maximumFractionDigits: 1 });
const fmt2 = (v) => (v == null ? '–' : v.toFixed(2));
const pad2 = (n) => String(n).padStart(2, '0');
const clock = (iso) => { const d = new Date(iso); return `${pad2(d.getHours())}:${pad2(d.getMinutes())}`; };
const shortDate = (iso) => { const d = new Date(iso); return `${d.getDate()}.${d.getMonth() + 1}.`; };
const longDate = (iso) => {
  const s = new Intl.DateTimeFormat('fi-FI', { weekday: 'long', day: 'numeric', month: 'numeric' }).format(new Date(iso));
  return `${s} klo ${clock(iso)}`;
};
const dayHeading = (d) => {
  const s = new Intl.DateTimeFormat('fi-FI', { weekday: 'long', day: 'numeric', month: 'long' }).format(d);
  return s.charAt(0).toUpperCase() + s.slice(1);
};
const dayStart = (d) => new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime();
const initials = (name) => {
  const w = name.split(' ').filter(Boolean);
  return w.length >= 2 ? (w[0][0] + w[1][0]).toUpperCase() : name.slice(0, 3).toUpperCase();
};
const hue = (name) => { let h = 5381; for (const ch of name) h = (h * 33 + ch.codePointAt(0)) % 360; return h; };

function flagCode(n) {
  if (!n) return '';
  const cps = [...n].map((c) => c.codePointAt(0));
  if (cps.length === 2 && cps.every((c) => c >= 0x1F1E6 && c <= 0x1F1FF)) {
    return String.fromCharCode(...cps.map((c) => c - 0x1F1E6 + 65));
  }
  return /^[A-Za-z]{2}(-[A-Za-z]{3})?$/.test(n) ? n.toUpperCase() : '';
}
// Windows ei piirrä lippuemojeja, joten näytetään lippukuva ja varana maakoodi.
function flagHtml(n) {
  const code = flagCode(n);
  if (!code) return esc(n);
  return `<span class="flag"><img src="https://flagcdn.com/24x18/${code.toLowerCase()}.png" alt=""><span class="code">${code}</span></span>`;
}

// Joukkuenimien yhdistäminen: eri rajapinnat nimeävät samat joukkueet eri tavoin.
const NAME_SKIP = new Set(['fc', 'cf', 'afc', 'sc', 'ac', 'as', 'ssc', 'us', 'rc', 'ud', 'cd', 'sv', 'fsv', 'vfb', 'vfl', 'tsg', 'bsc', 'fk', 'ca', 'club', 'de', 'the', 'calcio']);
const NAME_ALIASES = {
  'manchester city': 'man city', 'manchester united': 'man united', 'newcastle united': 'newcastle',
  'wolverhampton wanderers': 'wolves', 'wolverhampton': 'wolves', 'spurs': 'tottenham', 'tottenham hotspur': 'tottenham',
  'brighton hove albion': 'brighton', 'brighton hove': 'brighton', 'nottingham': 'nottingham forest',
  'leeds united': 'leeds', 'west ham united': 'west ham', 'athletic': 'athletic club', 'real betis balompie': 'betis',
  'real betis': 'betis', 'deportivo alaves': 'alaves', 'real sociedad futbol': 'real sociedad',
  'rayo vallecano de madrid': 'rayo vallecano', 'internazionale milano': 'inter', 'internazionale': 'inter',
  'paris saint germain': 'psg', 'olympique marseille': 'marseille', 'olympique lyonnais': 'lyon',
  'bayern munich': 'bayern munchen', 'borussia dortmund': 'dortmund', 'bayer leverkusen': 'leverkusen',
  'rasenballsport leipzig': 'rb leipzig', 'borussia monchengladbach': 'gladbach', 'borussia m gladbach': 'gladbach',
  'fc cologne': 'koln', 'cologne': 'koln', 'sporting lisbon': 'sporting cp', 'sporting clube portugal': 'sporting cp',
  'sl benfica': 'benfica', 'barca': 'barcelona', 'atleti': 'atletico madrid', 'nott m forest': 'nottingham forest',
  'man utd': 'man united', 'mgladbach': 'gladbach', 'm gladbach': 'gladbach', 'inter milan': 'inter',
  'ath bilbao': 'athletic club', 'athletic bilbao': 'athletic club'
};
function tkey(name) {
  const folded = String(name).normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase();
  const tokens = folded.split(/[^a-z0-9]+/).filter((t) => t && !/^\d+$/.test(t) && !NAME_SKIP.has(t));
  const joined = tokens.join(' ');
  return NAME_ALIASES[joined] || joined;
}
function related(a, b) {
  const x = new Set(a.split(' ').filter(Boolean)), y = new Set(b.split(' ').filter(Boolean));
  if (!x.size || !y.size) return false;
  const sub = (p, q) => [...p].every((t) => q.has(t));
  return sub(x, y) || sub(y, x);
}

// Logot tallennetaan nimellä, normalisoidulla nimellä ja sarjakohtaisesti: Understatin "Brighton" löytää ESPN:n "Brighton & Hove Albion" -logon.
const crestCache = new Map();
function setCrest(name, url, code) {
  if (!url || !name) return;
  S.crests[name] = url; S.crests[tkey(name)] = url;
  if (code) (S.crestsBy[code] = S.crestsBy[code] || {})[tkey(name)] = url;
  crestCache.clear();
}
function crestFor(name, code) {
  const direct = S.crests[name] || S.crests[tkey(name)];
  if (direct || !code || !S.crestsBy[code]) return direct;
  const ck = code + '|' + name;
  if (crestCache.has(ck)) return crestCache.get(ck);
  const tk = tkey(name);
  const hit = Object.entries(S.crestsBy[code]).find(([k]) => related(k, tk));
  crestCache.set(ck, hit ? hit[1] : undefined);
  return hit ? hit[1] : undefined;
}

function badge(name, size = 28, code) {
  const url = crestFor(name, code);
  return `<span class="badge" style="--s:${size}px;--h:${hue(name)}"><span class="mono">${esc(initials(name))}</span>${url ? `<img src="${esc(url)}" alt="">` : ''}</span>`;
}

// Kuvien lataus ilman inline-käsittelijöitä (CSP)
document.addEventListener('load', (e) => {
  const t = e.target;
  if (t.tagName === 'IMG' && t.parentNode.classList.contains('badge')) t.parentNode.classList.add('logo');
}, true);
document.addEventListener('error', (e) => {
  const t = e.target;
  if (t.tagName !== 'IMG') return;
  if (t.parentNode.classList.contains('flag')) t.parentNode.classList.add('fallback');
  else if (t.parentNode.classList.contains('badge')) t.remove();
}, true);

// ---------- data ----------

function normalizePlayers(arr) {
  if (!Array.isArray(arr) || !arr.length) throw new Error('empty');
  return arr.map((p, i) => ({
    id: String(p.id ?? `imp-${i}`), name: String(p.name ?? ''), team: String(p.team ?? ''),
    league: String(p.league ?? ''), nationality: String(p.nationality ?? ''),
    position: POSITIONS.includes(p.position) ? p.position : 'Keskikenttä',
    appearances: num(p.appearances), goals: num(p.goals), shots: num(p.shots),
    shotsOnTarget: num(p.shotsOnTarget), shotsOutsideBox: num(p.shotsOutsideBox),
    shotsOnTargetOutsideBox: num(p.shotsOnTargetOutsideBox)
  }));
}

// -- football-data.org --

async function fdGet(path) {
  const res = await window.api.footballData(path, S.apiKey.trim());
  if (res.status === 429) throw new Error('Kyselyraja täynnä, yritä minuutin kuluttua uudelleen');
  if (res.status === 401 || res.status === 403) throw new Error('API-avain ei kelpaa tähän sarjaan');
  if (res.status <= 0) throw new Error('Yhteys football-data.org:iin epäonnistui');
  if (res.status < 200 || res.status >= 300) throw new Error(`Palvelin vastasi virheellä ${res.status}`);
  return res.body;
}

const tname = (t) => t.shortName || t.name;

function fdMatch(m, code) {
  setCrest(tname(m.homeTeam), m.homeTeam.crest, code);
  setCrest(tname(m.awayTeam), m.awayTeam.crest, code);
  const status = ['FINISHED', 'AWARDED'].includes(m.status) ? 'finished'
    : ['IN_PLAY', 'PAUSED'].includes(m.status) ? 'live' : 'scheduled';
  const ht = (m.score && m.score.halfTime) || {};
  return {
    id: `${code}-${m.id}`, src: 'fd', league: code, matchday: m.matchday || 0, date: m.utcDate,
    home: tname(m.homeTeam), away: tname(m.awayTeam),
    homeGoals: m.score.fullTime.home, awayGoals: m.score.fullTime.away, status,
    homeHalf: status === 'scheduled' ? null : (ht.home ?? null), awayHalf: status === 'scheduled' ? null : (ht.away ?? null)
  };
}

async function fdLeague(code) {
  const [st, ma] = await Promise.all([
    fdGet(`/competitions/${code}/standings`),
    fdGet(`/competitions/${code}/matches`)
  ]);
  const groups = st.standings || [];
  const group = groups.find((g) => g.type === 'TOTAL') || groups[0];
  const rows = (group ? group.table : []).map((r) => {
    setCrest(tname(r.team), r.team.crest, code);
    return {
      position: r.position, team: tname(r.team), played: r.playedGames, won: r.won, drawn: r.draw, lost: r.lost,
      goalsFor: r.goalsFor, goalsAgainst: r.goalsAgainst, points: r.points, form: []
    };
  });
  return { rows, games: (ma.matches || []).map((m) => fdMatch(m, code)) };
}

// -- ESPN (ei avainta, epävirallinen) --

async function espnGet(lg, kind, query = {}) {
  const res = await window.api.espn({ slug: lg.slug, kind, query });
  const qs = Object.entries(query).map(([k, v]) => `${k}=${v}`).join('&');
  if (res.status <= 0) throw new Error('Yhteys ESPN:ään epäonnistui');
  if (res.status < 200 || res.status >= 300) throw new Error(`ESPN vastasi virheellä ${res.status}: /${lg.slug}/${kind}${qs ? '?' + qs : ''}`);
  return res.body || {};
}

const flex = (v) => {
  if (typeof v === 'number') return v;
  if (typeof v === 'string') { const n = parseFloat(v.replace('%', '').replace(',', '.').trim()); return Number.isFinite(n) ? n : null; }
  return null;
};

async function espnStandings(lg) {
  const dto = await espnGet(lg, 'standings');
  const children = dto.children || [];
  let entries = children.flatMap((c) => (c.standings && c.standings.entries) || []);
  const groupCount = children.filter((c) => c.standings && (c.standings.entries || []).length).length;
  if (!entries.length) entries = (dto.standings && dto.standings.entries) || [];
  if (!entries.length) throw new Error('ESPN ei palauttanut tietoja: sarjataulukko');
  const parsed = entries.map((e) => {
    const values = {};
    (e.stats || []).forEach((s) => { const v = flex(s.value); if (s.name && v !== null) values[s.name] = v; });
    const team = e.team || {};
    return { team: team.displayName || team.name || '?', logo: team.logos && team.logos[0] && team.logos[0].href, values };
  });
  const n = (p, k) => Math.trunc(p.values[k] || 0);
  const diff = (p) => n(p, 'pointsFor') - n(p, 'pointsAgainst');
  if (groupCount > 1 || parsed.some((p) => p.values.rank === undefined)) {
    parsed.sort((a, b) => n(b, 'points') - n(a, 'points') || diff(b) - diff(a));
  } else {
    parsed.sort((a, b) => (a.values.rank || 0) - (b.values.rank || 0));
  }
  return parsed.map((p, i) => {
    setCrest(p.team, p.logo, lg.code);
    return {
      position: i + 1, team: p.team, played: n(p, 'gamesPlayed'), won: n(p, 'wins'), drawn: n(p, 'ties'), lost: n(p, 'losses'),
      goalsFor: n(p, 'pointsFor'), goalsAgainst: n(p, 'pointsAgainst'), points: n(p, 'points'), form: []
    };
  });
}

function espnEvent(ev, lg) {
  const comp = ev.competitions && ev.competitions[0];
  if (!comp) return null;
  const home = comp.competitors.find((c) => c.homeAway === 'home');
  const away = comp.competitors.find((c) => c.homeAway === 'away');
  if (!home || !away || !home.team.displayName || !away.team.displayName) return null;
  const date = new Date(ev.date);
  if (Number.isNaN(date.getTime())) return null;
  setCrest(home.team.displayName, home.team.logo, lg.code);
  setCrest(away.team.displayName, away.team.logo, lg.code);
  const state = (ev.status && ev.status.type && ev.status.type.state) || 'pre';
  const status = state === 'post' ? 'finished' : state === 'in' ? 'live' : 'scheduled';
  const played = status !== 'scheduled';
  const goals = (c) => (played ? flex(c.score) : null);
  const half = (c) => {
    const lines = c.linescores || [];
    return played && lines.length >= 2 ? flex(lines[0].value) : null;
  };
  return {
    id: `${lg.code}-${ev.id}`, src: 'espn', league: lg.code, matchday: 0, date: date.toISOString(),
    home: home.team.displayName, away: away.team.displayName,
    homeGoals: goals(home), awayGoals: goals(away), status, homeHalf: half(home), awayHalf: half(away)
  };
}

// Kausi: MLS kalenterivuosi, muut heinäkuusta alkaen
function seasonYear(lg) {
  const now = new Date();
  const y = now.getUTCFullYear();
  if (lg.calendarSeason) return y;
  return now.getUTCMonth() + 1 >= 7 ? y : y - 1;
}
function monthRanges(lg) {
  const year = seasonYear(lg);
  const startMonth = lg.calendarSeason ? 1 : 7;
  const out = [];
  for (let off = 0; off < 12; off++) {
    const idx = startMonth - 1 + off;
    const y = year + Math.floor(idx / 12), m = (idx % 12) + 1;
    const last = new Date(Date.UTC(y, m, 0)).getUTCDate();
    out.push(`${y}${pad2(m)}01-${y}${pad2(m)}${pad2(last)}`);
  }
  return out;
}
const ymd = (d) => `${d.getFullYear()}${pad2(d.getMonth() + 1)}${pad2(d.getDate())}`;

async function pool(items, size, fn) {
  const out = [];
  for (let i = 0; i < items.length; i += size) {
    out.push(...await Promise.all(items.slice(i, i + size).map(fn)));
  }
  return out;
}

async function espnEvents(lg, queries) {
  let failure = null, ok = false;
  const lists = await pool(queries, 15, async (dates) => {
    try { const dto = await espnGet(lg, 'scoreboard', { dates }); ok = true; return dto.events || []; }
    catch (e) { if (!failure) failure = e; return []; }
  });
  return { events: lists.flat(), failure, ok };
}

const isoWeekKey = (iso) => {
  const d = new Date(iso);
  const t = new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()));
  const dayNum = t.getUTCDay() || 7;
  t.setUTCDate(t.getUTCDate() + 4 - dayNum);
  const yearStart = Date.UTC(t.getUTCFullYear(), 0, 1);
  return t.getUTCFullYear() * 100 + Math.ceil(((t - yearStart) / 86400000 + 1) / 7);
};

async function espnMatches(lg) {
  let { events, failure } = await espnEvents(lg, monthRanges(lg));
  // Varavaihtoehto: jos aikavälihaku ei toimi, haetaan yksittäiset päivät (±45 vrk)
  if (!events.length) {
    const days = [];
    for (let o = -45; o <= 45; o++) { const d = new Date(); d.setDate(d.getDate() + o); days.push(ymd(d)); }
    events = (await espnEvents(lg, days)).events;
  }
  if (!events.length && failure) throw failure;
  const seen = new Set();
  const games = events.filter((e) => !seen.has(e.id) && seen.add(e.id)).map((e) => espnEvent(e, lg)).filter(Boolean);
  if (!games.length) throw new Error('ESPN ei palauttanut tietoja: otteluohjelma');
  // ESPN ei kerro kierrosta, joten ottelut ryhmitellään viikoittain: viikko = "kierros"
  const weeks = [...new Set(games.map((g) => isoWeekKey(g.date)))].sort((a, b) => a - b);
  games.forEach((g) => { g.matchday = weeks.indexOf(isoWeekKey(g.date)) + 1; });
  return games;
}

async function refresh(force = false) {
  const code = focus();
  const lg = leagueOf(code);
  if (!force && S.live[code]) return;
  S.loading = true; S.error = null; render();
  try {
    if (srcOf(lg) === 'fd') {
      const { rows, games } = await fdLeague(code);
      S.standings[code] = rows; S.matches[code] = games;
    } else {
      const [rows, games] = await Promise.all([espnStandings(lg), espnMatches(lg)]);
      S.standings[code] = rows; S.matches[code] = games;
    }
    S.live[code] = true; S.updatedAt[code] = new Date();
    pickMatchday();
  } catch (e) {
    S.error = e.message;
  }
  S.loading = false; render();
  ensureOdds();
}

// Kaikki sarjat: tämän päivän ottelut
async function refreshToday() {
  if (S.loadingToday) return;
  S.loadingToday = true; S.error = null; render();
  const now = new Date();
  const todayKey = dayStart(now);
  const collected = [];
  const live = {};
  let firstError = null;
  const around = [-1, 0, 1].map((o) => { const d = new Date(now); d.setDate(d.getDate() + o); return d; });
  if (S.apiKey.trim()) {
    const iso = (d) => `${d.getUTCFullYear()}-${pad2(d.getUTCMonth() + 1)}-${pad2(d.getUTCDate())}`;
    try {
      const body = await fdGet(`/matches?dateFrom=${iso(new Date(now.getTime() - 86400000))}&dateTo=${iso(new Date(now.getTime() + 86400000))}`);
      (body.matches || []).forEach((m) => {
        const code = m.competition && m.competition.code;
        if (code && leagueOf(code) && leagueOf(code).src === 'fd') { collected.push(fdMatch(m, code)); live[code] = true; }
      });
      LEAGUES.filter((l) => l.src === 'fd').forEach((l) => { live[l.code] = true; });
    } catch (e) { firstError = e; }
  }
  const espnLeagues = LEAGUES.filter((l) => !live[l.code]);
  await Promise.all(espnLeagues.map(async (lg) => {
    try {
      const { events, failure, ok } = await espnEvents(lg, around.map(ymd));
      if (!ok && failure) throw failure;
      const seen = new Set();
      events.filter((e) => !seen.has(e.id) && seen.add(e.id)).forEach((e) => { const m = espnEvent(e, lg); if (m) collected.push(m); });
      live[lg.code] = true;
    } catch (e) { if (!firstError) firstError = e; }
  }));
  S.today = collected.filter((m) => dayStart(new Date(m.date)) === todayKey);
  S.todayLive = live; S.todayUpdated = new Date();
  if (firstError) S.error = firstError.message;
  S.loadingToday = false; render();
  ensureOdds();
}

function pickMatchday() {
  const games = S.matches[focus()] || [];
  const open = games.filter((m) => m.status !== 'finished' && m.matchday > 0).map((m) => m.matchday);
  const all = games.map((m) => m.matchday);
  S.matchday = open.length ? Math.min(...open) : (all.length ? Math.max(...all) : 1);
}

// -- Kertoimet (The Odds API, välimuisti pääprosessissa) --

const oddsBusy = new Set();
function oddsLeagues() {
  if (S.section !== 'fixtures') return [];
  if (S.league) return [leagueOf(S.league)];
  const ids = new Set(S.today.filter((m) => m.status === 'scheduled').map((m) => m.league));
  return LEAGUES.filter((l) => ids.has(l.code));
}
async function ensureOdds(force = false) {
  if (!S.oddsKey.trim()) return;
  let changed = false;
  for (const lg of oddsLeagues()) {
    if (oddsBusy.has(lg.code)) continue;
    oddsBusy.add(lg.code);
    try {
      const res = await window.api.odds(lg.odds, S.oddsKey.trim(), force);
      if (res.remaining !== undefined && res.remaining !== null) S.oddsRemaining = res.remaining;
      if (res.status === 200) { S.odds[lg.code] = res.entries || []; S.oddsError = ''; changed = true; }
      else {
        if (res.entries && res.entries.length) { S.odds[lg.code] = res.entries; changed = true; }
        S.oddsError = res.status === 401 || res.status === 429
          ? 'The Odds API: avain ei kelpaa tai kuukauden krediitit on käytetty'
          : `The Odds API vastasi virheellä ${res.status}`;
        if (res.status === 401 || res.status === 429) { oddsBusy.delete(lg.code); break; }
      }
    } catch { S.oddsError = 'The Odds API: yhteys epäonnistui'; }
    oddsBusy.delete(lg.code);
  }
  if (changed || S.settingsOpen) render();
}
function oddsFor(m) {
  const list = S.odds[m.league];
  if (!list) return null;
  const h = tkey(m.home), a = tkey(m.away);
  const hit = list.find((o) => {
    const oh = tkey(o.homeName), oa = tkey(o.awayName);
    return (oh === h || related(oh, h)) && (oa === a || related(oa, a))
      && Math.abs(new Date(o.commence) - new Date(m.date)) < 36 * 3600 * 1000;
  });
  return hit && hit.home != null && hit.draw != null && hit.away != null ? hit : null;
}

const COUNTRY_CODES = {"Albania": "AL", "Algeria": "DZ", "Angola": "AO", "Argentina": "AR", "Armenia": "AM", "Australia": "AU", "Austria": "AT", "Azerbaijan": "AZ", "Belarus": "BY", "Belgium": "BE", "Benin": "BJ", "Bolivia": "BO", "Bosnia-Herzegovina": "BA", "Bosnia and Herzegovina": "BA", "Brazil": "BR", "Bulgaria": "BG", "Burkina Faso": "BF", "Burundi": "BI", "Cameroon": "CM", "Canada": "CA", "Cape Verde": "CV", "Cape Verde Islands": "CV", "Central African Republic": "CF", "Chile": "CL", "China": "CN", "China PR": "CN", "Colombia": "CO", "Comoros": "KM", "Congo": "CG", "Congo DR": "CD", "DR Congo": "CD", "Costa Rica": "CR", "Croatia": "HR", "Cuba": "CU", "Curacao": "CW", "Curaçao": "CW", "Cyprus": "CY", "Czech Republic": "CZ", "Czechia": "CZ", "Denmark": "DK", "Dominican Republic": "DO", "Ecuador": "EC", "Egypt": "EG", "Equatorial Guinea": "GQ", "Eritrea": "ER", "Estonia": "EE", "Ethiopia": "ET", "Faroe Islands": "FO", "Finland": "FI", "France": "FR", "Gabon": "GA", "Gambia": "GM", "Georgia": "GE", "Germany": "DE", "Ghana": "GH", "Greece": "GR", "Guinea": "GN", "Guinea-Bissau": "GW", "Haiti": "HT", "Honduras": "HN", "Hungary": "HU", "Iceland": "IS", "India": "IN", "Indonesia": "ID", "Iran": "IR", "Iraq": "IQ", "Ireland": "IE", "Republic of Ireland": "IE", "Israel": "IL", "Italy": "IT", "Ivory Coast": "CI", "Côte d'Ivoire": "CI", "Cote d'Ivoire": "CI", "Jamaica": "JM", "Japan": "JP", "Jordan": "JO", "Kazakhstan": "KZ", "Kenya": "KE", "Kosovo": "XK", "Latvia": "LV", "Lebanon": "LB", "Liberia": "LR", "Libya": "LY", "Lithuania": "LT", "Luxembourg": "LU", "Madagascar": "MG", "Mali": "ML", "Malta": "MT", "Mauritania": "MR", "Mexico": "MX", "Moldova": "MD", "Montenegro": "ME", "Morocco": "MA", "Mozambique": "MZ", "Namibia": "NA", "Netherlands": "NL", "New Zealand": "NZ", "Niger": "NE", "Nigeria": "NG", "North Macedonia": "MK", "Norway": "NO", "Panama": "PA", "Paraguay": "PY", "Peru": "PE", "Philippines": "PH", "Poland": "PL", "Portugal": "PT", "Romania": "RO", "Russia": "RU", "Rwanda": "RW", "Saudi Arabia": "SA", "Senegal": "SN", "Serbia": "RS", "Sierra Leone": "SL", "Slovakia": "SK", "Slovenia": "SI", "South Africa": "ZA", "South Korea": "KR", "Korea Republic": "KR", "Spain": "ES", "Suriname": "SR", "Sweden": "SE", "Switzerland": "CH", "Syria": "SY", "Tanzania": "TZ", "Togo": "TG", "Trinidad and Tobago": "TT", "Tunisia": "TN", "Turkey": "TR", "Türkiye": "TR", "Uganda": "UG", "Ukraine": "UA", "United States": "US", "USA": "US", "Uruguay": "UY", "Uzbekistan": "UZ", "Venezuela": "VE", "Zambia": "ZM", "Zimbabwe": "ZW", "England": "gb-eng", "Scotland": "gb-sct", "Wales": "gb-wls", "Northern Ireland": "gb"};

// ---------- pelaajien kansallisuudet (liput) ----------

const nameTokens = (n) => new Set(String(n).normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().split(/[^a-z0-9]+/).filter((t) => t.length > 1));
const sameName = (a, b) => {
  if (!a.size || !b.size) return false;
  const sub = (p, q) => [...p].every((t) => q.has(t));
  return sub(a, b) || sub(b, a);
};
function applyNationalities() {
  S.players.forEach((p) => { if (!p.nationality && S.nationalities[p.id]) p.nationality = S.nationalities[p.id]; });
}

// Täydentää tyhjät kansallisuudet football-data.orgin joukkuekokoonpanoista (5 kyselyä, tulokset tallennetaan).
async function enrichNationalities() {
  if (!S.apiKey.trim() || S.enriching) return;
  if (!S.players.some((p) => !p.nationality)) return;
  S.enriching = true; if (S.settingsOpen) render();
  const index = {};
  for (const lg of LEAGUES.filter((l) => l.stats)) {
    try {
      const body = await fdGet(`/competitions/${lg.code}/teams`);
      index[lg.code] = (body.teams || []).flatMap((t) => (t.squad || []).filter((m) => m.nationality).map((m) => ({
        tokens: nameTokens(m.name), nat: COUNTRY_CODES[m.nationality] || '', team: tkey(t.shortName || t.name)
      }))).filter((e) => e.nat);
    } catch { /* sarja ohitetaan, yritetään seuraavalla kerralla */ }
  }
  let found = 0;
  S.players.forEach((p) => {
    if (p.nationality || !index[p.league]) return;
    const tokens = nameTokens(p.name);
    const hits = index[p.league].filter((e) => sameName(tokens, e.tokens));
    const tk = tkey(p.team);
    const pick = hits.find((e) => e.team === tk || related(e.team, tk)) || (hits.length === 1 ? hits[0] : null);
    if (pick) { p.nationality = pick.nat; S.nationalities[p.id] = pick.nat; found++; }
  });
  if (found) window.api.saveStore({ nationalities: S.nationalities });
  S.enriching = false; render();
}

// Pelaajadata Understatista (main-prosessi hakee kausitilastot ja ottelukohtaiset laukaukset, tulokset välimuistissa)
const PLAYERS_MAX_AGE = 6 * 3600 * 1000;

function playersStale() {
  if (S.playersSource === 'imported') return false; // oma tuonti päivitetään vain käsin
  if (S.playersSource !== 'understat' || S.playersPartial || !S.playersUpdated) return true;
  return Date.now() - new Date(S.playersUpdated).getTime() > PLAYERS_MAX_AGE;
}

async function updatePlayers() {
  if (S.updatingPlayers) return;
  S.updatingPlayers = true; S.playersStatus = 'Haetaan pelaajadataa…'; S.playersNote = '';
  render();
  let res;
  try { res = await window.api.fetchPlayers(); } catch { res = { ok: false, error: 'yhteys epäonnistui' }; }
  S.updatingPlayers = false; S.playersStatus = '';
  const failed = (res && res.failed) || [];
  if (!res || !res.ok || !res.players.length) {
    const why = (res && res.error) || failed.map((f) => `${f.league}: ${f.error}`).join(', ') || 'ei tuloksia';
    S.playersNote = `Pelaajadataa ei saatu päivitettyä (${why}). Vanha data säilyy.`;
    render(); return;
  }
  const lost = new Set(failed.map((f) => f.league));
  const kept = S.players.filter((p) => lost.has(p.league)); // epäonnistuneiden sarjojen vanha data säilyy
  S.players = normalizePlayers([...res.players, ...kept]);
  S.playersSource = 'understat'; S.playersPartial = lost.size > 0; S.playersUpdated = new Date().toISOString();
  applyNationalities();
  await window.api.savePlayers(S.players, lost.size ? 'understat-partial' : 'understat');
  if (lost.size) S.playersNote = `Osa sarjoista jäi päivittämättä: ${failed.map((f) => `${f.league} (${f.error})`).join(', ')}. Yritetään uudelleen seuraavalla päivityksellä.`;
  render();
  enrichNationalities();
  if (S.playerModal) openPlayer(S.playerModal.id);
}

// Pelaajalistan joukkueiden logot: haetaan sarjataulukot (ESPN, ei avainta) taustalla, jotta logot löytyvät myös ennen sarjan avaamista
const crestTried = new Set();
async function ensureCrests() {
  let changed = false;
  for (const lg of LEAGUES.filter((l) => l.stats)) {
    if (crestTried.has(lg.code) || S.crestsBy[lg.code]) continue;
    crestTried.add(lg.code);
    try { await espnStandings(lg); changed = true; } catch { /* logot jäävät nimikirjaimiksi */ }
  }
  if (changed) render();
}

// ---------- pelaajan laukauskartta ----------

const SHOT_RES = { G: ['Maali', '#FFB547'], S: ['Torjuttu', '#4ADE9A'], P: ['Tolppa', '#B48CFF'], M: ['Ohi', '#879A96'], B: ['Blokattu', '#FF6B6B'] };
const SHOT_SIT = { O: 'Avopeli', C: 'Kulma', S: 'Vakiotilanne', F: 'Vapaapotku', P: 'Rangaistus' };
const BOX_X = (105 - 16.5) / 105, BOX_Y_MIN = (68 - 40.32) / 2 / 68, BOX_Y_MAX = 1 - BOX_Y_MIN;
const outsideBox = (sh) => !(sh[0] >= BOX_X && sh[1] >= BOX_Y_MIN && sh[1] <= BOX_Y_MAX);

async function openPlayer(id) {
  if (!S.players.some((p) => p.id === id)) return;
  S.playerModal = { id, state: 'loading', shots: [], available: false, result: 'all', sit: 'all' };
  render();
  let r;
  try { r = await window.api.playerShots(id); } catch { r = { available: false, shots: [] }; }
  if (!S.playerModal || S.playerModal.id !== id) return;
  S.playerModal.state = 'ok'; S.playerModal.shots = r.shots || []; S.playerModal.available = !!r.available;
  render();
}

function shotMapSvg(shots) {
  const K = 8, W = 68 * K, H = 52.5 * K;
  const boxW = 40.32 * K, six = 18.32 * K, goal = 7.32 * K, r = 9.15 * K, spotY = 11 * K, boxH = 16.5 * K;
  const dx = Math.sqrt(r * r - (boxH - spotY) ** 2);
  const lines = `<rect x="0" y="0" width="${W}" height="${H}"/>
    <rect x="${(W - boxW) / 2}" y="0" width="${boxW}" height="${boxH}"/>
    <rect x="${(W - six) / 2}" y="0" width="${six}" height="${5.5 * K}"/>
    <rect x="${(W - goal) / 2}" y="-8" width="${goal}" height="8" class="goalpost"/>
    <path d="M ${W / 2 - dx} ${boxH} A ${r} ${r} 0 0 0 ${W / 2 + dx} ${boxH}"/>
    <path d="M ${W / 2 - r} ${H} A ${r} ${r} 0 0 1 ${W / 2 + r} ${H}"/>
    <circle cx="${W / 2}" cy="${spotY}" r="2.5" class="spot"/>`;
  const dots = [...shots].sort((a, b) => b[2] - a[2]).map((sh) => {
    const cx = Math.max(0, Math.min(W, sh[1] * W)), cy = Math.max(0, Math.min(H - 4, (1 - sh[0]) * 105 * K));
    const rad = 4.5 + Math.sqrt(Math.max(0, sh[2])) * 16;
    const info = SHOT_RES[sh[4]] || SHOT_RES.M;
    return `<circle cx="${cx.toFixed(1)}" cy="${cy.toFixed(1)}" r="${rad.toFixed(1)}" class="sd ${sh[4] === 'G' ? 'goal' : ''}" style="--c:${info[1]}"><title>${sh[3]}' · ${info[0]} · xG ${sh[2].toFixed(2)} · ${SHOT_SIT[sh[5]] || 'Avopeli'}</title></circle>`;
  }).join('');
  return `<svg class="pitch" viewBox="-14 -22 ${W + 28} ${H + 36}" role="img" aria-label="Laukauskartta"><g class="plines">${lines}</g>${dots}</svg>`;
}

function playerModalView() {
  const pm = S.playerModal;
  const p = S.players.find((x) => x.id === pm.id);
  if (!p) return '';
  const lg = leagueOf(p.league);
  const all = pm.shots;
  const vis = all.filter((sh) => (pm.result === 'all' || sh[4] === pm.result) && (pm.sit === 'all' || sh[5] === pm.sit));
  let body;
  if (pm.state === 'loading') body = '<div class="empty"><b>Haetaan laukauksia…</b></div>';
  else if (!pm.available) body = `<div class="empty"><b>Laukauskartan tiedot puuttuvat</b>
    <span>Laukaukset haetaan Understatista pelaajadatan päivityksen yhteydessä (ensimmäinen haku kestää hetken).</span>
    <button class="ghost" data-act="updplayers" ${S.updatingPlayers ? 'disabled' : ''}>${S.updatingPlayers ? 'Haetaan…' : '⟳ Päivitä pelaajadata'}</button>
    ${S.updatingPlayers ? `<span data-pstatus>${esc(S.playersStatus)}</span>` : ''}</div>`;
  else if (!all.length) body = '<div class="empty"><b>Ei laukauksia tällä kaudella</b></div>';
  else {
    const goals = all.filter((sh) => sh[4] === 'G').length, on = all.filter((sh) => sh[4] === 'G' || sh[4] === 'S').length;
    const xg = all.reduce((a, sh) => a + sh[2], 0), out = all.filter(outsideBox).length;
    const stat = (v, l) => `<div class="pm-stat"><b>${v}</b><small>${l}</small></div>`;
    const resChip = (k, label, color, n) => `<button class="chip ${pm.result === k ? 'sel' : ''}" data-act="pmres" data-v="${k}" style="--c:${color}">${k !== 'all' ? '<i></i>' : ''}${label}${n != null ? ` ${n}` : ''}</button>`;
    const sits = [...new Set(all.map((sh) => sh[5]))].filter((k) => SHOT_SIT[k]);
    body = `<div class="pm-stats">${stat(all.length, 'Laukaukset')}${stat(goals, 'Maalit')}${stat(on, 'Kohti maalia')}${stat(xg.toFixed(2), 'xG')}${stat((xg / all.length).toFixed(2), 'xG / laukaus')}${stat(out, 'Alueen ulkopuolelta')}</div>
      <div class="pm-filters">${resChip('all', 'Kaikki', 'var(--amber)', all.length)}${Object.entries(SHOT_RES).map(([k, [label, color]]) => { const n = all.filter((sh) => sh[4] === k).length; return n ? resChip(k, label, color, n) : ''; }).join('')}</div>
      ${sits.length > 1 ? `<div class="pm-filters">${['all', ...sits].map((k) => `<button class="chip ${pm.sit === k ? 'sel' : ''}" data-act="pmsit" data-v="${k}" style="--c:var(--eu)">${k === 'all' ? 'Kaikki tilanteet' : SHOT_SIT[k]}</button>`).join('')}</div>` : ''}
      <div class="pm-map">${shotMapSvg(vis)}</div>
      <div class="hint" style="text-align:center">Ympyrän koko = laukauksen xG. Näytetään ${vis.length} / ${all.length} laukausta. Kenttä: hyökkäyspuolisko, maali ylhäällä. Tiedot: Understat.</div>`;
  }
  return `<div class="modal-bg top" data-act="close-bg"><div class="modal player" role="dialog" aria-label="${esc(p.name)}">
    <div class="pm-head">${badge(p.team, 48, p.league)}<div style="min-width:0;flex:1"><h2>${esc(p.name)}</h2>
      <div class="sub">${p.nationality ? flagHtml(p.nationality) + ' ' : ''}${esc(p.team)}${lg ? ' · ' + esc(lg.name) : ''} · ${esc(p.position)} · ${p.appearances} ottelua · ${p.goals} maalia</div></div>
      <button class="ghost" data-act="close" title="Sulje (Esc)">✕</button></div>
    ${body}</div></div>`;
}

// ---------- ottelun tilastot ----------

const STAT_DEFS = {
  possession: { label: 'Pallonhallinta', kind: 'percent' },
  shots: { label: 'Laukaukset yhteensä', kind: 'count' },
  shotsOnTarget: { label: 'Laukaukset kohti maalia', kind: 'count' },
  shotsOffTarget: { label: 'Laukaukset ohi maalin', kind: 'count' },
  blockedShots: { label: 'Blokatut laukaukset', kind: 'count' },
  corners: { label: 'Kulmapotkut', kind: 'count' },
  offsides: { label: 'Paitsiot', kind: 'count' },
  passes: { label: 'Syötöt', kind: 'ratio' },
  longBalls: { label: 'Pitkät syötöt', kind: 'ratio' },
  crosses: { label: 'Keskitykset', kind: 'ratio' },
  fouls: { label: 'Rikkeet', kind: 'count' },
  tackles: { label: 'Taklaukset', kind: 'ratio' },
  interceptions: { label: 'Katkaisut', kind: 'count' },
  saves: { label: 'Torjunnat', kind: 'count' },
  yellowCards: { label: 'Keltaiset kortit', kind: 'count' },
  redCards: { label: 'Punaiset kortit', kind: 'count' }
};
const STAT_GROUPS = [
  ['Tärkeimmät tilastot', ['possession', 'shots', 'shotsOnTarget', 'corners', 'passes', 'yellowCards', 'redCards']],
  ['Laukaukset', ['shots', 'shotsOnTarget', 'shotsOffTarget', 'blockedShots']],
  ['Hyökkäys', ['corners', 'offsides']],
  ['Syötöt', ['passes', 'longBalls', 'crosses']],
  ['Puolustus', ['fouls', 'tackles', 'interceptions', 'saves']]
];

const findMatch = (id) => {
  for (const code of Object.keys(S.matches)) { const m = S.matches[code].find((x) => x.id === id); if (m) return m; }
  return S.today.find((x) => x.id === id) || null;
};

function loadCachedStats() {
  try { return JSON.parse(localStorage.getItem('matchStats') || '{}'); } catch { return {}; }
}
function saveCachedStats(id, data) {
  try {
    const all = loadCachedStats();
    all[id] = data;
    const ids = Object.keys(all);
    if (ids.length > 300) ids.slice(0, ids.length - 300).forEach((k) => delete all[k]);
    localStorage.setItem('matchStats', JSON.stringify(all));
  } catch { /* välimuisti ei ole pakollinen */ }
}

// ESPN:n ottelutunniste: ESPN-sarjoilla se on ottelun tunnisteessa, muilla etsitään päivän ottelulistasta.
async function espnEventId(lg, m) {
  if (m.src === 'espn') return m.id.slice(m.id.indexOf('-') + 1);
  const d = new Date(m.date);
  const days = new Set([`${d.getUTCFullYear()}${pad2(d.getUTCMonth() + 1)}${pad2(d.getUTCDate())}`, ymd(d)]);
  const h = tkey(m.home), a = tkey(m.away);
  for (const day of days) {
    const dto = await espnGet(lg, 'scoreboard', { dates: day });
    for (const ev of dto.events || []) {
      const comp = ev.competitions && ev.competitions[0];
      if (!comp) continue;
      const home = comp.competitors.find((c) => c.homeAway === 'home'), away = comp.competitors.find((c) => c.homeAway === 'away');
      if (!home || !away) continue;
      const eh = tkey(home.team.displayName || ''), ea = tkey(away.team.displayName || '');
      if ((eh === h || related(eh, h)) && (ea === a || related(ea, a))) return ev.id;
    }
  }
  throw new Error('ESPN:stä ei löytynyt tämän ottelun tilastoja.');
}

function espnGoals(dto) {
  const comp = dto.header && dto.header.competitions && dto.header.competitions[0];
  const homeId = comp && (comp.competitors || []).find((c) => c.homeAway === 'home');
  const homeTeamId = homeId && homeId.team ? String(homeId.team.id) : null;
  const events = dto.keyEvents || (comp && comp.details) || [];
  return events.filter((e) => e.scoringPlay || /goal/i.test((e.type && (e.type.text || e.type.type)) || ''))
    .filter((e) => !/disallow|cancel/i.test((e.type && e.type.text) || ''))
    .map((e) => {
      const clock = String((e.clock && e.clock.displayValue) || '');
      const mm = clock.match(/(\d+)(?:'|’)?(?:\s*\+\s*(\d+))?/);
      const text = ((e.type && e.type.text) || '') + ' ' + (e.text || '');
      const who = (e.participants && e.participants[0] && e.participants[0].athlete && e.participants[0].athlete.displayName)
        || (e.athletesInvolved && e.athletesInvolved[0] && e.athletesInvolved[0].displayName) || (e.shortText || '').replace(/ Goal.*$/i, '') || '?';
      const teamId = e.team && e.team.id !== undefined ? String(e.team.id) : null;
      return {
        minute: mm ? +mm[1] : 0, extra: mm && mm[2] ? +mm[2] : 0,
        isHome: teamId && homeTeamId ? teamId === homeTeamId : true, scorer: who,
        kind: /own/i.test(text) ? 'OWN' : /penalty/i.test(text) ? 'PENALTY' : null
      };
    }).sort((x, y) => x.minute + x.extra / 100 - y.minute - y.extra / 100);
}

async function fdGoals(m) {
  const body = await fdGet(`/matches/${m.id.slice(m.id.indexOf('-') + 1)}`);
  const homeId = body.homeTeam && body.homeTeam.id;
  return (body.goals || []).map((g) => ({
    minute: g.minute || 0, extra: g.injuryTime || 0, isHome: g.team && g.team.id === homeId,
    scorer: (g.scorer && g.scorer.name) || '?', assist: g.assist && g.assist.name,
    kind: g.type === 'OWN' ? 'OWN' : g.type === 'PENALTY' ? 'PENALTY' : null
  }));
}

async function fetchMatchDetail(m) {
  const lg = leagueOf(m.league);
  const id = await espnEventId(lg, m);
  const dto = await espnGet(lg, 'summary', { event: id });
  const teams = (dto.boxscore && dto.boxscore.teams) || [];
  const home = teams.find((t) => t.homeAway === 'home') || teams[0];
  const away = teams.find((t) => t.homeAway === 'away') || teams[1];
  if (!home || !away) throw new Error('ESPN ei palauttanut tietoja: ottelutilastot');
  const collect = (t) => { const out = {}; (t.statistics || []).forEach((s) => { const v = parseFloat(String(s.displayValue).replace('%', '')); if (s.name && Number.isFinite(v)) out[s.name] = v; }); return out; };
  const h = collect(home), a = collect(away);
  const stats = {};
  const add = (key, name) => { if (h[name] !== undefined && a[name] !== undefined) stats[key] = { home: { value: h[name] }, away: { value: a[name] } }; };
  add('possession', 'possessionPct'); add('shots', 'totalShots'); add('shotsOnTarget', 'shotsOnTarget'); add('blockedShots', 'blockedShots');
  add('corners', 'wonCorners'); add('offsides', 'offsides'); add('fouls', 'foulsCommitted'); add('saves', 'saves');
  add('yellowCards', 'yellowCards'); add('redCards', 'redCards'); add('interceptions', 'interceptions');
  if (h.totalShots !== undefined && a.totalShots !== undefined) {
    const ho = h.totalShots - (h.shotsOnTarget || 0) - (h.blockedShots || 0), ao = a.totalShots - (a.shotsOnTarget || 0) - (a.blockedShots || 0);
    if (ho >= 0 && ao >= 0) stats.shotsOffTarget = { home: { value: ho }, away: { value: ao } };
  }
  const ratio = (key, made, total) => { if (h[made] !== undefined && h[total] !== undefined && a[made] !== undefined && a[total] !== undefined) stats[key] = { home: { value: h[made], attempts: h[total] }, away: { value: a[made], attempts: a[total] } }; };
  ratio('passes', 'accuratePasses', 'totalPasses'); ratio('crosses', 'accurateCrosses', 'totalCrosses');
  ratio('tackles', 'effectiveTackles', 'totalTackles'); ratio('longBalls', 'accurateLongBalls', 'totalLongBalls');
  let goals = [];
  try { goals = espnGoals(dto); } catch { goals = []; }
  if (!goals.length && m.src === 'fd' && S.apiKey.trim() && (m.homeGoals || 0) + (m.awayGoals || 0) > 0) {
    try { goals = await fdGoals(m); } catch { goals = []; }
  }
  if (!Object.keys(stats).length) throw new Error('ESPN ei palauttanut tietoja: ottelutilastot');
  return { stats, goals };
}

async function openMatch(m) {
  if (!m || m.status === 'scheduled') return;
  const cached = S.mstats[m.id] || loadCachedStats()[m.id];
  if (cached && m.status === 'finished') { S.mstats[m.id] = cached; S.matchModal = { id: m.id, state: 'ok', data: cached }; render(); return; }
  S.matchModal = { id: m.id, state: 'loading' }; render();
  try {
    const data = await fetchMatchDetail(m);
    if (m.status === 'finished') { S.mstats[m.id] = data; saveCachedStats(m.id, data); }
    if (S.matchModal && S.matchModal.id === m.id) { S.matchModal = { id: m.id, state: 'ok', data }; render(); }
  } catch (e) {
    if (S.matchModal && S.matchModal.id === m.id) { S.matchModal = { id: m.id, state: 'err', error: e.message }; render(); }
  }
}

function recentForm(team, m) {
  const k = tkey(team);
  const list = (S.matches[m.league] || []).filter((x) => x.status === 'finished' && x.homeGoals != null && x.awayGoals != null && new Date(x.date) < new Date(m.date)
    && (tkey(x.home) === k || tkey(x.away) === k)).sort((a, b) => new Date(a.date) - new Date(b.date)).slice(-5);
  return list.map((x) => { const home = tkey(x.home) === k; return mkGame(x, home, home ? x.homeGoals : x.awayGoals, home ? x.awayGoals : x.homeGoals); });
}

function statValueHtml(key, v) {
  const kind = STAT_DEFS[key].kind;
  if (kind === 'percent') return `<b>${Math.round(v.value)}%</b>`;
  if (kind === 'ratio') return v.attempts > 0 ? `<b>${Math.round((v.value / v.attempts) * 100)}%</b><small>(${Math.round(v.value)}/${Math.round(v.attempts)})</small>` : '<b>–</b>';
  return `<b>${Math.round(v.value)}</b>`;
}
function statRowHtml(key, pair) {
  const kind = STAT_DEFS[key].kind;
  const share = (v) => (kind === 'ratio' ? (v.attempts > 0 ? v.value / v.attempts : 0) : v.value);
  const h = share(pair.home), a = share(pair.away), total = h + a;
  const w = (x) => (total > 0 ? (x / total) * 100 : 0);
  return `<div class="stat"><div class="stat-top"><span class="sv l">${statValueHtml(key, pair.home)}</span><span class="sl">${STAT_DEFS[key].label}</span><span class="sv r">${statValueHtml(key, pair.away)}</span></div>
    <div class="stat-bars"><div class="half l"><i class="${h > a ? 'lead' : ''}" style="width:${w(h)}%"></i></div><div class="half r"><i class="${a > h ? 'lead' : ''}" style="width:${w(a)}%"></i></div></div></div>`;
}

function matchModalView() {
  const mm = S.matchModal;
  const m = findMatch(mm.id);
  if (!m) return '';
  const lg = leagueOf(m.league);
  const d = new Date(m.date);
  const chips = (team) => {
    const games = recentForm(team, m);
    return games.length ? `<div class="mm-form"><small>Viimeisimmät</small><div class="strip" style="justify-content:center">${games.map((g) => rb(resultKind(g.code), resultLetter(g.code), resultHelp(g))).join('')}</div></div>` : '<div class="mm-form"></div>';
  };
  let body;
  if (mm.state === 'loading') body = '<div class="empty"><b>Haetaan tilastoja…</b></div>';
  else if (mm.state === 'err') body = `<div class="empty"><b>${esc(mm.error)}</b></div>`;
  else {
    const { stats, goals } = mm.data;
    const label = (g) => `${g.minute}${g.extra ? '+' + g.extra : ''}' ${esc(g.scorer)}${g.kind === 'OWN' ? ' (oma maali)' : g.kind === 'PENALTY' ? ' (rp)' : ''}`;
    const goalsHtml = goals && goals.length ? `<div class="mpanel"><div class="mp-title">MAALIT</div><div class="mp-body">${goals.map((g) => `
      <div class="goal" ${g.assist ? `title="Syöttö: ${esc(g.assist)}"` : ''}><span class="l">${g.isHome ? label(g) : ''}</span><i>⚽</i><span class="r">${g.isHome ? '' : label(g)}</span></div>`).join('')}</div></div>` : '';
    const groups = STAT_GROUPS.map(([title, keys]) => {
      const present = keys.filter((k) => stats[k]);
      return present.length ? `<div class="mpanel"><div class="mp-title">${title.toUpperCase()}</div><div class="mp-body stats">${present.map((k) => statRowHtml(k, stats[k])).join('')}</div></div>` : '';
    }).join('');
    body = `${goalsHtml}${groups}<div class="hint" style="text-align:center">Tilastot: ESPN</div>`;
  }
  const team = (n) => `<div class="mm-team">${badge(n, 48)}<span>${esc(n)}</span></div>`;
  return `<div class="modal-bg top" data-act="close-bg"><div class="modal match" role="dialog" aria-label="${esc(m.home)} – ${esc(m.away)}">
    <div class="mm-head">
      <div class="mm-top"><div><b>${esc(lg.name)}</b><div class="sub">Kierros ${m.matchday} · ${dayHeading(d)} ${clock(m.date)}</div></div>
        <button class="ghost" data-act="close" title="Sulje (Esc)">✕</button></div>
      <div class="mm-score">${team(m.home)}<div class="mm-mid"><b class="${m.status === 'live' ? 'live' : ''}">${m.homeGoals ?? 0} – ${m.awayGoals ?? 0}</b><small class="${m.status === 'live' ? 'live' : ''}">${m.status === 'live' ? 'Käynnissä' : 'Päättynyt'}</small></div>${team(m.away)}</div>
      <div class="mm-forms">${chips(m.home)}<div style="width:130px"></div>${chips(m.away)}</div>
    </div>
    <div class="mm-body">${body}</div>
  </div></div>`;
}

// ---------- joukkuekohtaiset laskelmat ----------

function mkGame(m, isHome, gf, ga) {
  const code = (f, a) => (f > a ? 'W' : f === a ? 'D' : 'L');
  const hf = isHome ? m.homeHalf : m.awayHalf, ha = isHome ? m.awayHalf : m.homeHalf;
  return {
    m, isHome, gf, ga, code: code(gf, ga), total: gf + ga, opp: isHome ? m.away : m.home,
    hf: hf ?? null, ha: ha ?? null, hcode: hf != null && ha != null ? code(hf, ha) : null
  };
}

function buildGames(matches, venue) {
  const byTeam = new Map(), nextBy = new Map(), names = new Map();
  const push = (k, g) => { if (!byTeam.has(k)) byTeam.set(k, []); byTeam.get(k).push(g); };
  [...matches].sort((a, b) => new Date(a.date) - new Date(b.date)).forEach((m) => {
    const hk = tkey(m.home), ak = tkey(m.away);
    if (!names.has(hk)) names.set(hk, m.home);
    if (!names.has(ak)) names.set(ak, m.away);
    if (m.status === 'finished' && m.homeGoals != null && m.awayGoals != null) {
      if (venue !== 'away') push(hk, mkGame(m, true, m.homeGoals, m.awayGoals));
      if (venue !== 'home') push(ak, mkGame(m, false, m.awayGoals, m.homeGoals));
    } else {
      if (!nextBy.has(hk)) nextBy.set(hk, m);
      if (!nextBy.has(ak)) nextBy.set(ak, m);
    }
  });
  const hasHalf = [...byTeam.values()].some((l) => l.some((g) => g.hf != null));
  return {
    names: [...names.values()].sort(), hasHalf,
    games: (t) => byTeam.get(tkey(t)) || [],
    next: (t) => nextBy.get(tkey(t)) || null
  };
}

function recordOf(games) {
  const r = { played: 0, won: 0, drawn: 0, lost: 0, goalsFor: 0, goalsAgainst: 0 };
  games.forEach((g) => {
    r.played++; r.goalsFor += g.gf; r.goalsAgainst += g.ga;
    if (g.code === 'W') r.won++; else if (g.code === 'D') r.drawn++; else r.lost++;
  });
  r.points = r.won * 3 + r.drawn; r.gd = r.goalsFor - r.goalsAgainst;
  return r;
}
const formPoints = (games) => games.slice(-5).reduce((s, g) => s + (g.code === 'W' ? 3 : g.code === 'D' ? 1 : 0), 0);

// ---------- näkymät ----------

function anyLive() {
  return (S.league ? (S.matches[S.league] || []) : S.today).some((m) => m.status === 'live');
}

function view() {
  const rated = Object.values(S.ratings).filter((v) => v > 0).length;
  const code = focus();
  const lg = leagueOf(code);
  const showsToday = S.section === 'fixtures' && S.league === null;
  let live, stamp;
  if (showsToday) { live = Object.values(S.todayLive).some(Boolean); stamp = S.todayUpdated; }
  else { live = S.live[code]; stamp = S.updatedAt[code]; }
  const title = showsToday ? 'Tänään' : lg.name;
  const status = live && stamp
    ? `${title}: live-data, päivitetty ${pad2(stamp.getHours())}:${pad2(stamp.getMinutes())}`
    : (S.loading || S.loadingToday ? `${title}: haetaan…` : `${title}: ei dataa`);
  const busy = S.loading || S.loadingToday;
  return `<div class="app">
    <div class="header">
      <div class="titles"><h1>Jalkapallotilastot</h1>
        <div class="sub">Kausi 2026/2027 · ${S.players.length} pelaajaa · ${rated} arvosteltu${S.updatingPlayers ? ` · <span data-pstatus>${esc(S.playersStatus)}</span>` : ''}${S.playersNote ? ` · <span class="warn" title="${esc(S.playersNote)}">${esc(S.playersNote.length > 90 ? S.playersNote.slice(0, 87) + '…' : S.playersNote)}</span>` : ''}</div></div>
      <div class="status ${live ? 'live' : ''}">${esc(status)}</div>
      <button class="ghost" data-act="refresh" ${busy ? 'disabled' : ''}>⟳ ${busy ? 'Haetaan…' : 'Päivitä'}</button>
      <button class="ghost" data-act="settings" title="Asetukset">⚙</button>
    </div>
    <div class="chips">
      <button class="chip ${S.league === null ? 'sel' : ''}" data-act="league" data-v="" style="--c:var(--amber)">Kaikki</button>
      ${LEAGUES.map((l) => `<button class="chip ${S.league === l.code ? 'sel' : ''}" data-act="league" data-v="${l.code}" style="--c:${l.accent}">${flagHtml(l.flag)}${esc(l.name)}</button>`).join('')}
    </div>
    <div class="toolbar">
      <div class="seg">${[['players', 'Pelaajat'], ['standings', 'Sarjataulukko'], ['fixtures', 'Otteluohjelma']]
        .map(([id, label]) => `<button class="${S.section === id ? 'sel' : ''}" data-act="section" data-v="${id}">${label}</button>`).join('')}</div>
      ${S.error ? `<span class="err">⚠ ${esc(S.error)}</span>` : ''}
    </div>
    ${S.section === 'players' ? playersView() : S.section === 'standings' ? standingsView() : fixturesView()}
  </div>${S.settingsOpen ? settingsView() : ''}${S.teamModal ? teamModalView() : ''}${S.matchModal ? matchModalView() : ''}${S.playerModal ? playerModalView() : ''}`;
}

function filteredPlayers() {
  let list = S.league ? S.players.filter((p) => p.league === S.league) : S.players.slice();
  if (S.team) list = list.filter((p) => p.team === S.team);
  if (S.position) list = list.filter((p) => p.position === S.position);
  if (S.favOnly) list = list.filter((p) => (S.ratings[p.id] || 0) > 0);
  const q = S.search.trim().toLowerCase();
  if (q) list = list.filter((p) => p.name.toLowerCase().includes(q) || p.team.toLowerCase().includes(q));
  const key = SORTS[S.sort] || SORTS.goals;
  const dir = S.asc ? 1 : -1;
  return list.sort((a, b) => {
    const x = key(a), y = key(b);
    if (x !== y) return (typeof x === 'string' ? x.localeCompare(y, 'fi') : x - y) * dir;
    return b.goals - a.goals || a.name.localeCompare(b.name, 'fi');
  });
}

function playersView() {
  const lg = S.league ? leagueOf(S.league) : null;
  if (lg && !S.players.some((p) => p.league === lg.code)) {
    return `<div class="panel"><div class="empty"><b>Pelaajatilastoja ei ole saatavilla tälle sarjalle</b>
      <span>Pelaajakohtaiset laukaustilastot haetaan vain viidestä suurimmasta liigasta.<br>Sarjataulukko ja otteluohjelma toimivat normaalisti.</span></div></div>`;
  }
  const rows = filteredPlayers();
  const scope = S.league ? S.players.filter((p) => p.league === S.league) : S.players;
  const teams = [...new Set(scope.map((p) => p.team))].sort((a, b) => a.localeCompare(b, 'fi'));
  const H = (label, key, help, left) => `<button class="hcell ${left ? 'left' : ''} ${S.sort === key ? 'hot' : ''}" data-act="sort" data-key="${key}" title="${esc(help || label.replace('\n', ' '))}">${label}${S.sort === key ? (S.asc ? ' ▴' : ' ▾') : ''}</button>`;
  const plain = (label) => `<button class="hcell" disabled>${label}</button>`;
  return `
    ${S.players.length ? '' : `<div class="banner"><b>ⓘ</b> Pelaajadataa ei löytynyt. Tuo pelaajat asetuksista (JSON).</div>`}
    <div class="filters">
      <input id="search" class="field" data-bind="search" placeholder="Hae pelaajaa tai joukkuetta" value="${esc(S.search)}">
      <select class="field" data-bind="team"><option value="">Kaikki joukkueet</option>${teams.map((t) => `<option ${S.team === t ? 'selected' : ''}>${esc(t)}</option>`).join('')}</select>
      <select class="field" data-bind="position"><option value="">Kaikki asemat</option>${POSITIONS.map((t) => `<option ${S.position === t ? 'selected' : ''}>${t}</option>`).join('')}</select>
      <button class="ghost ${S.favOnly ? 'on' : ''}" data-act="fav">${S.favOnly ? '★' : '☆'} Suosikit</button>
      <span class="count">${rows.length} pelaajaa</span>
    </div>
    <div class="panel">
      <div class="head">
        ${H('Pelaaja', 'name', '', true)}${plain('Maa')}${plain('Asema')}
        ${H('Ottelut', 'appearances')}${H('Maalit', 'goals')}${H('Laukaukset', 'shots')}${H('Maalia kohti', 'shotsOnTarget')}
        ${H('Maalia kohti\nulkopuolelta', 'shotsOnTargetOutsideBox', 'Maalia kohti -laukaukset rangaistusalueen ulkopuolelta')}
        ${H('Laukaukset\nulkopuolelta', 'shotsOutsideBox', 'Kaikki laukaukset rangaistusalueen ulkopuolelta')}
        ${H('Maalia\nkohti %', 'onTargetPercent')}${H('Lauk.\n/ ott.', 'perGame')}${plain('Jakauma')}${plain('Tähdet')}
      </div>
      ${rows.length ? `<div class="scroll">${rows.map(playerRow).join('')}</div>`
        : `<div class="empty"><b>Ei pelaajia valituilla rajauksilla</b><button class="ghost" data-act="clear">Tyhjennä rajaukset</button></div>`}
    </div>`;
}

function playerRow(p) {
  const r = S.ratings[p.id] || 0;
  const hot = (k) => (S.sort === k ? ' hot' : '');
  const total = Math.max(p.shots, 1);
  const a = (p.shotsOnTargetOutsideBox / total) * 100;
  const b = (Math.max(0, p.shotsOutsideBox - p.shotsOnTargetOutsideBox) / total) * 100;
  const c = Math.max(0, 100 - a - b);
  const lg = leagueOf(p.league);
  return `<div class="row">
    <div class="cell player open" data-act="player" data-id="${esc(p.id)}" title="Näytä laukauskartta">${badge(p.team, 36, p.league)}<div style="min-width:0"><div class="pname">${esc(p.name)}</div>
      <div class="psub">${p.nationality ? flagHtml(p.nationality) : ''}${lg ? `<i style="--c:${lg.accent}"></i>` : ''}${esc(p.team)}</div></div></div>
    <div class="cell">${flagHtml(p.nationality)}</div>
    <div class="cell muted sm">${esc(p.position)}</div>
    <div class="cell num${hot('appearances')}">${p.appearances}</div>
    <div class="cell num${hot('goals')}">${p.goals}</div>
    <div class="cell num${hot('shots')}">${p.shots}</div>
    <div class="cell num${hot('shotsOnTarget')}">${p.shotsOnTarget}</div>
    <div class="cell num${hot('shotsOnTargetOutsideBox')}">${p.shotsOnTargetOutsideBox}</div>
    <div class="cell num${hot('shotsOutsideBox')}">${p.shotsOutsideBox}</div>
    <div class="cell num${hot('onTargetPercent')}">${fmt1(onTargetPct(p))}</div>
    <div class="cell num${hot('perGame')}">${fmt1(perGame(p))}</div>
    <div class="cell"><span class="mix" title="Kirkas: maalia kohti ulkopuolelta · himmeä: muut ulkopuolelta · harmaa: rangaistusalueen sisältä"><span style="width:${a}%"></span><span style="width:${b}%"></span><span style="width:${c}%"></span></span></div>
    <div class="cell"><span class="stars">${[1, 2, 3].map((n) => `<button class="${n <= r ? 'on' : ''}" data-act="star" data-id="${esc(p.id)}" data-n="${n}">${n <= r ? '★' : '☆'}</button>`).join('')}</span></div>
  </div>`;
}

// ---- Sarjataulukko ----

function zoneOf(pos, count, lg) {
  if (lg.zones === 'cup') return pos <= 8 ? 'var(--pos)' : pos <= 24 ? 'var(--eu)' : 'transparent';
  if (lg.zones === 'none') return 'transparent';
  if (pos <= 4) return 'var(--pos)';
  if (pos <= 6) return 'var(--eu)';
  if (count > 0 && pos > count - 3) return 'var(--neg)';
  return 'transparent';
}

function rb(kind, text, help) {
  return `<span class="rb ${kind}" title="${esc(help)}">${text}</span>`;
}
const resultKind = (c) => (c === 'W' ? 'win' : c === 'D' ? 'draw' : 'loss');
const resultLetter = (c) => (c === 'W' ? 'V' : c === 'D' ? 'T' : 'H');
const resultHelp = (g) => `${g.m.home} ${g.m.homeGoals ?? 0}–${g.m.awayGoals ?? 0} ${g.m.away} · ${shortDate(g.m.date)}`;
const nextHelp = (m) => (m ? `Seuraava ottelu: ${m.home} – ${m.away}, ${longDate(m.date)}` : 'Ei tulevia otteluita');

function comboHelp(code) {
  const half = { W: 'Johti puoliajalla', D: 'Tasan puoliajalla', L: 'Oli tappiolla puoliajalla' }[code[0]];
  const full = { W: 'voitti ottelun', D: 'ottelu päättyi tasan', L: 'hävisi ottelun' }[code[1]];
  return `${half}, ${full}`;
}

function setSort(key) {
  if (S.st.key === key) S.st.asc = !S.st.asc;
  else S.st = { key, asc: key === 'team' || key === 'position' };
}

function sortHead(label, key, help, left) {
  const on = S.st.key === key;
  return `<button class="hcell ${left ? 'left' : ''} ${on ? 'hot' : ''}" style="height:36px" data-act="stsort" data-key="${esc(key)}" title="${esc(help)}">${label}${on ? (S.st.asc ? ' ▴' : ' ▾') : ''}</button>`;
}
const plainHead = (label, help, left) => `<button class="hcell ${left ? 'left' : ''}" style="height:36px" disabled title="${esc(help)}">${label}</button>`;

// Joukkueen yksittäinen rivi sarjataulukossa (rajapinnan taulukko tai otteluista laskettu)
function tableRows(code, games) {
  const base = S.standings[code] || [];
  if (S.venue === 'all' && base.length) return base;
  const names = base.length ? base.map((r) => r.team) : games.names;
  const computed = names.map((n) => ({ team: n, rec: recordOf(games.games(n)) }));
  computed.sort((a, b) => b.rec.points - a.rec.points || b.rec.gd - a.rec.gd || b.rec.goalsFor - a.rec.goalsFor || a.team.localeCompare(b.team));
  return computed.map((c, i) => ({
    position: i + 1, team: c.team, played: c.rec.played, won: c.rec.won, drawn: c.rec.drawn, lost: c.rec.lost,
    goalsFor: c.rec.goalsFor, goalsAgainst: c.rec.goalsAgainst, points: c.rec.points, form: []
  }));
}

function cmp(list, valueOf, tie) {
  const dir = S.st.asc ? 1 : -1;
  return list.sort((a, b) => {
    if (S.st.key === 'team') return a.team.localeCompare(b.team, 'fi') * dir;
    const x = valueOf(a), y = valueOf(b);
    if (x !== y) return (x - y) * dir;
    return tie(a, b);
  });
}

function standingsView() {
  const code = focus(); const lg = leagueOf(code);
  const note = S.league === null ? '<small>· valitse sarja yläpalkista</small>' : '';
  const games = buildGames(S.matches[code] || [], S.venue);
  const modes = [['table', 'Taulukko'], ['ou', 'Yli/Alle'], ['htft', 'HT/FT']];
  const controls = `<div class="ctl">
    <div class="seg">${modes.map(([id, l]) => `<button class="${S.stMode === id ? 'sel' : ''}" data-act="stmode" data-v="${id}">${l}</button>`).join('')}</div>
    <div class="seg">${[['all', 'Yhteensä'], ['home', 'Kotona'], ['away', 'Vieraissa']].map(([id, l]) => `<button class="${S.venue === id ? 'sel' : ''}" data-act="venue" data-v="${id}">${l}</button>`).join('')}</div>
    ${S.stMode === 'ou' ? `<div class="seg">${LINES.map((l) => `<button class="${S.line === l ? 'sel' : ''}" data-act="line" data-v="${l}">${l.toFixed(1)}</button>`).join('')}</div>` : ''}
  </div>`;
  const body = S.stMode === 'table' ? tableMode(code, lg, games) : S.stMode === 'ou' ? overUnderMode(code, games) : htftMode(code, games);
  return `<div class="st-title">${lg.flag ? flagHtml(lg.flag) : ''}${esc(lg.name)} ${note}</div>${controls}${body}`;
}

function legendFor(lg) {
  if (lg.zones === 'cup') return '<span><i style="background:var(--pos)"></i>Suoraan jatkoon</span><span><i style="background:var(--eu)"></i>Jatkopelit</span>';
  if (lg.zones === 'none') return '';
  return '<span><i style="background:var(--pos)"></i>Mestarien liiga</span><span><i style="background:var(--eu)"></i>Eurooppa-sarjat</span><span><i style="background:var(--neg)"></i>Putoamisalue</span>';
}

function emptyBox(text) { return `<div class="panel"><div class="empty"><b>${text}</b></div></div>`; }

function tableMode(code, lg, games) {
  const rows = cmp(tableRows(code, games), (r) => ({
    position: r.position, played: r.played, won: r.won, drawn: r.drawn, lost: r.lost, goalsFor: r.goalsFor,
    goalDifference: r.goalsFor - r.goalsAgainst, points: r.points, form: formPoints(games.games(r.team))
  }[S.st.key] ?? r.position), (a, b) => a.position - b.position);
  const cols = '40px minmax(180px,1fr) 44px 44px 44px 44px 80px 54px 58px 190px';
  const head = `<div class="head st-cols" style="grid-template-columns:${cols}">
    ${sortHead('#', 'position', 'Sija sarjataulukossa')}${sortHead('Joukkue', 'team', 'Joukkueen nimi', true)}
    ${sortHead('O', 'played', 'Pelatut ottelut')}${sortHead('V', 'won', 'Voitot')}${sortHead('T', 'drawn', 'Tasapelit')}${sortHead('H', 'lost', 'Tappiot')}
    ${sortHead('Maalit', 'goalsFor', 'Tehdyt ja päästetyt maalit (lajittelu tehtyjen mukaan)')}
    ${sortHead('ME', 'goalDifference', 'Maaliero: tehdyt maalit miinus päästetyt')}${sortHead('P', 'points', 'Pisteet (voitto 3, tasapeli 1)')}
    ${sortHead('Kunto', 'form', 'Viiden viimeisimmän ottelun tulokset vanhimmasta uusimpaan. ? = seuraava ottelu (vie hiiri päälle)', true)}</div>`;
  const total = rows.length;
  return `<div class="panel">${head}
    ${rows.length ? `<div class="scroll">${rows.map((r) => {
      const gd = r.goalsFor - r.goalsAgainst;
      const g = games.games(r.team);
      const zone = S.venue === 'all' ? zoneOf(r.position, total, lg) : 'transparent';
      return `<div class="row st-row st-cols open" data-act="team" data-name="${esc(r.team)}" style="grid-template-columns:${cols};--z:${zone}">
        <div class="pos">${r.position}</div>
        <div class="team">${badge(r.team, 34)}<span>${esc(r.team)}</span></div>
        <div class="cell num">${r.played}</div><div class="cell num">${r.won}</div><div class="cell num">${r.drawn}</div><div class="cell num">${r.lost}</div>
        <div class="cell num">${r.goalsFor}:${r.goalsAgainst}</div>
        <div class="cell num gd ${gd > 0 ? 'pos' : gd < 0 ? 'neg' : 'zero'}">${gd > 0 ? '+' + gd : gd}</div>
        <div class="cell num pts">${r.points}</div>
        <div class="strip">${rb('unknown', '?', nextHelp(games.next(r.team)))}${g.slice(-5).map((x) => rb(resultKind(x.code), resultLetter(x.code), resultHelp(x))).join('')}</div>
      </div>`;
    }).join('')}</div>` : `<div class="empty"><b>${S.loading ? 'Haetaan sarjataulukkoa…' : 'Sarjataulukkoa ei ole vielä saatavilla'}</b></div>`}
  </div><div class="legend">${legendFor(lg)}<span class="grow"></span><span>V = voitto · T = tasapeli · H = häviö · ? = seuraava ottelu</span></div>`;
}

function overUnderMode(code, games) {
  const names = (S.standings[code] || []).length ? S.standings[code].map((r) => r.team) : games.names;
  const limit = S.line.toFixed(1);
  const list = names.map((n) => {
    const g = games.games(n);
    const over = g.filter((x) => x.total > S.line).length;
    const gf = g.reduce((s, x) => s + x.gf, 0), ga = g.reduce((s, x) => s + x.ga, 0);
    return { team: n, g, over, under: g.length - over, played: g.length, gf, ga, avg: g.length ? (gf + ga) / g.length : 0,
      recent: g.slice(-5).filter((x) => x.total > S.line).length };
  });
  cmp(list, (r) => ({ played: r.played, over: r.over, under: r.under, goalsFor: r.gf, average: r.avg, recentOver: r.recent }[S.st.key] ?? r.over),
    (a, b) => b.over - a.over || b.avg - a.avg || a.team.localeCompare(b.team));
  const cols = '40px minmax(180px,1fr) 52px 48px 48px 80px 60px 190px';
  const head = `<div class="head st-cols" style="grid-template-columns:${cols}">
    ${plainHead('#', 'Sija nykyisessä järjestyksessä')}${sortHead('Joukkue', 'team', 'Joukkueen nimi', true)}
    ${sortHead('OTT', 'played', 'Pelatut ottelut')}${sortHead('Yli', 'over', `Otteluita, joissa maaleja tehtiin yli ${limit}`)}
    ${sortHead('Alle', 'under', `Otteluita, joissa maaleja tehtiin alle ${limit}`)}
    ${sortHead('M', 'goalsFor', 'Tehdyt ja päästetyt maalit (lajittelu tehtyjen mukaan)')}
    ${sortHead('M/O', 'average', 'Maaleja keskimäärin per ottelu (molempien joukkueiden maalit yhteensä)')}
    ${sortHead('Viimeiset 5', 'recentOver', `Viiden viimeisimmän ottelun yli/alle ${limit}: + = yli, − = alle. ? = seuraava ottelu`, true)}</div>`;
  if (list.every((r) => r.played === 0)) return `<div class="panel">${head}<div class="empty"><b>Pelattuja otteluita ei ole vielä saatavilla</b></div></div>`;
  return `<div class="panel">${head}<div class="scroll">${list.map((r, i) => `
    <div class="row st-row st-cols open" data-act="team" data-name="${esc(r.team)}" style="grid-template-columns:${cols}">
      <div class="pos">${i + 1}</div><div class="team">${badge(r.team, 34)}<span>${esc(r.team)}</span></div>
      <div class="cell num">${r.played}</div><div class="cell num">${r.over}</div><div class="cell num">${r.under}</div>
      <div class="cell num">${r.gf}:${r.ga}</div><div class="cell num pts">${fmt1(r.avg)}</div>
      <div class="strip">${rb('unknown', '?', nextHelp(games.next(r.team)))}${r.g.slice(-5).map((x) => rb(x.total > S.line ? 'over' : 'under', x.total > S.line ? '+' : '−', `${resultHelp(x)} · maaleja yhteensä ${x.total}`)).join('')}</div>
    </div>`).join('')}</div></div>`;
}

function htftMode(code, games) {
  if (!games.hasHalf) return emptyBox('Puoliaikatuloksia ei ole saatavilla tälle sarjalle');
  const names = (S.standings[code] || []).length ? S.standings[code].map((r) => r.team) : games.names;
  const list = names.map((n) => {
    const g = games.games(n);
    const counts = {};
    g.forEach((x) => { if (x.hcode) counts[x.hcode + x.code] = (counts[x.hcode + x.code] || 0) + 1; });
    const last = g.slice(-5);
    return { team: n, g, rec: recordOf(g), counts, last, fh: last.reduce((s, x) => s + (x.hf || 0), 0) };
  });
  cmp(list, (r) => {
    const k = S.st.key;
    if (k === 'played') return r.rec.played;
    if (k === 'firstHalf') return r.fh;
    if (k.startsWith('combo:')) return r.counts[k.slice(6)] || 0;
    return r.rec.points;
  }, (a, b) => b.rec.points - a.rec.points || b.rec.gd - a.rec.gd || a.team.localeCompare(b.team));
  const cols = `40px minmax(160px,1fr) 48px ${HTFT.map(() => '46px').join(' ')} 52px 190px`;
  const head = `<div class="head st-cols" style="grid-template-columns:${cols}">
    ${plainHead('#', 'Sija nykyisessä järjestyksessä')}${sortHead('Joukkue', 'team', 'Joukkueen nimi', true)}${sortHead('OTT', 'played', 'Pelatut ottelut')}
    ${HTFT.map(([l, c]) => sortHead(l, 'combo:' + c, comboHelp(c))).join('')}
    ${sortHead('PIS', 'points', 'Pisteet (voitto 3, tasapeli 1)')}
    ${sortHead('1. jakso', 'firstHalf', 'Joukkueen tekemät maalit ensimmäisellä puoliajalla viimeisessä viidessä ottelussa: summa ja ottelukohtaiset luvut', true)}</div>`;
  return `<div class="panel">${head}<div class="scroll">${list.map((r, i) => {
    const best = Math.max(0, ...Object.values(r.counts));
    return `<div class="row st-row st-cols open" data-act="team" data-name="${esc(r.team)}" style="grid-template-columns:${cols}">
      <div class="pos">${i + 1}</div><div class="team">${badge(r.team, 34)}<span>${esc(r.team)}</span></div>
      <div class="cell num">${r.rec.played}</div>
      ${HTFT.map(([, c]) => { const v = r.counts[c] || 0; return `<div class="cell"><span class="hc ${v && v === best ? 'best' : ''} ${v ? '' : 'zero'}" title="${esc(r.team)}: ${esc(comboHelp(c))} – ${v} ottelua">${v}</span></div>`; }).join('')}
      <div class="cell num pts">${r.rec.points}</div>
      <div class="strip"><b class="fhsum">${r.fh}</b>${r.last.map((x) => `<span class="fh ${x.hf > 0 ? 'on' : ''}" title="${x.hf != null ? esc(x.opp) + ': ' + x.hf + ' maalia ensimmäisellä jaksolla' : 'Puoliaikatulos ei tiedossa'}">${x.hf != null ? x.hf : '–'}</span>`).join('')}</div>
    </div>`;
  }).join('')}</div></div>`;
}

// ---- Joukkueen ikkuna ----

function teamModalView() {
  const t = S.teamModal;
  const code = focus(); const lg = leagueOf(code);
  const all = buildGames(S.matches[code] || [], t.venue);
  const g = all.games(t.name);
  const shown = t.count === 0 ? g : g.slice(-t.count);
  const rec = recordOf(shown);
  const withHalf = shown.filter((x) => x.hf != null && x.ha != null);
  const hf = withHalf.reduce((s, x) => s + x.hf, 0), ha = withHalf.reduce((s, x) => s + x.ha, 0);
  const over = shown.filter((x) => x.total > 2).length;
  const st = (S.standings[code] || []).find((r) => tkey(r.team) === tkey(t.name));
  const nx = all.next(t.name);
  const sub = [`${lg.name}`, st ? `sija ${st.position} · ${st.points} p` : '', nx ? `seuraava: ${nx.home} – ${nx.away}, ${longDate(nx.date)}` : ''].filter(Boolean).join(' · ');
  const tile = (l, v, help = '') => `<div class="tile" title="${esc(help)}"><small>${l}</small><b>${v}</b></div>`;
  const seg = (items, cur, act) => `<div class="seg">${items.map(([v, l]) => `<button class="${cur === v ? 'sel' : ''}" data-act="${act}" data-v="${v}">${l}</button>`).join('')}</div>`;
  return `<div class="modal-bg" data-act="close-bg"><div class="modal wide" role="dialog" aria-label="${esc(t.name)}">
    <div class="tm-head">${badge(t.name, 52)}<div style="flex:1;min-width:0"><h2>${esc(t.name)}</h2><div class="sub">${esc(sub)}</div></div>
      <button class="ghost" data-act="close" title="Sulje (Esc)">✕</button></div>
    <div class="ctl">${seg([[5, '5 viimeisintä'], [10, '10 viimeisintä'], [0, 'Kaikki']], t.count, 'tmcount')}${seg([['all', 'Yhteensä'], ['home', 'Kotona'], ['away', 'Vieraissa']], t.venue, 'tmvenue')}</div>
    <div class="tiles">${tile('Tulokset', `${rec.won}V ${rec.drawn}T ${rec.lost}H`)}${tile('Maalit', `${rec.goalsFor}:${rec.goalsAgainst}`)}
      ${tile('1. jakson maalit', withHalf.length ? `${hf}:${ha}` : '–', `Tehdyt ja päästetyt maalit ensimmäisellä puoliajalla (${withHalf.length} ottelua, joista puoliaikatulos on tiedossa)`)}
      ${tile('Yli 2.5', `${over}/${shown.length}`, 'Otteluita, joissa tehtiin yli 2,5 maalia')}</div>
    ${shown.length ? `<div class="tm-list">${[...shown].reverse().map((x) => `<div class="tm-row open" data-act="match" data-id="${esc(x.m.id)}" title="Näytä ottelun tilastot">
      <span class="muted">${shortDate(x.m.date)}</span><span class="muted sm">${x.isHome ? 'Koti' : 'Vieras'}</span>
      ${badge(x.opp, 28)}<span class="tm-opp">${esc(x.opp)}</span>
      ${x.m.homeHalf != null && x.m.awayHalf != null ? `<span class="muted sm" title="Puoliaikatulos: ${esc(x.m.home)} ${x.m.homeHalf}–${x.m.awayHalf} ${esc(x.m.away)}">(${x.m.homeHalf}–${x.m.awayHalf})</span>` : ''}
      <b class="tm-score">${x.m.homeGoals ?? 0} – ${x.m.awayGoals ?? 0}</b>${rb(resultKind(x.code), resultLetter(x.code), resultHelp(x))}</div>`).join('')}</div>`
      : '<div class="empty"><b>Pelattuja otteluita ei ole vielä saatavilla</b></div>'}
    <div class="hint">Vain tämän sarjan ottelut. Uusin ottelu ylimpänä.</div>
  </div></div>`;
}

// ---- Otteluohjelma ----

function sw(on, act, label) {
  return `<button class="sw ${on ? 'on' : ''}" role="switch" aria-checked="${on}" data-act="${act}"><i></i><span>${label}</span></button>`;
}

function oddsHelp(o) {
  return `1 (koti) ${fmt2(o.home)} · X (tasapeli) ${fmt2(o.draw)} · 2 (vieras) ${fmt2(o.away)}`
    + (o.over != null || o.under != null ? `\nYli ${o.line.toFixed(1)} maalia ${fmt2(o.over)} · Alle ${fmt2(o.under)}` : '')
    + `\nKeskiarvo ${o.bookmakers} vedonvälittäjältä`;
}

function fixturesView() {
  const all = S.league === null;
  const code = focus(); const lg = leagueOf(code);
  const games = S.matches[code] || [];
  const days = [...new Set(games.map((m) => m.matchday))].sort((a, b) => a - b);
  let list = all ? S.today : S.liveOnly ? games : games.filter((m) => m.matchday === S.matchday);
  if (S.liveOnly) list = list.filter((m) => m.status === 'live');
  list = [...list].sort((a, b) => new Date(a.date) - new Date(b.date));

  let groups;
  if (all) {
    groups = LEAGUES.map((l) => ({ title: `${l.flag ? flagHtml(l.flag) + ' ' : ''}${esc(l.name)}`, day: 0, items: list.filter((m) => m.league === l.code) })).filter((g) => g.items.length);
  } else {
    const map = new Map();
    list.forEach((m) => { const k = dayStart(new Date(m.date)); if (!map.has(k)) map.set(k, []); map.get(k).push(m); });
    groups = [...map.entries()].sort((a, b) => a[0] - b[0]).map(([k, items]) => ({ title: dayHeading(new Date(k)), day: k, items }));
    if (S.hidePast && !S.liveOnly) { const today = dayStart(new Date()); groups = groups.filter((g) => g.day >= today); }
  }
  const emptyText = S.liveOnly ? 'Ei meneillään olevia otteluita'
    : (S.loading || S.loadingToday) && !list.length ? 'Haetaan otteluita…'
    : all ? 'Ei otteluita tänään'
      : list.length ? 'Kierroksen ottelut on jo pelattu.<br>Näytä ne kytkimellä "Näytä menneet päivät".' : 'Otteluita ei ole vielä saatavilla';

  const mid = (m) => {
    if (m.status === 'scheduled') {
      const o = oddsFor(m);
      return `<div class="fx-c"><div class="fx-mid sched">${clock(m.date)}</div>${o ? `<div class="fx-odds" title="${esc(oddsHelp(o))}">${fmt2(o.home)}  ${fmt2(o.draw)}  ${fmt2(o.away)}</div>` : ''}</div>`;
    }
    return `<div class="fx-c"><div class="fx-mid ${m.status === 'live' ? 'live' : ''}">${m.homeGoals ?? 0} – ${m.awayGoals ?? 0}</div></div>`;
  };
  const note = all ? '<small>· kaikki sarjat</small>' : '';
  const nav = `<div class="fx-nav"><div class="fx-title" style="flex:1">${all ? 'Tänään' : (lg.flag ? flagHtml(lg.flag) + ' ' : '') + esc(lg.name)} ${note}</div>
    ${sw(S.liveOnly, 'liveonly', 'Vain meneillään')}
    ${all ? '' : `<div class="fx-ctl ${S.liveOnly ? 'off' : ''}">
      ${S.liveOnly ? '' : sw(!S.hidePast, 'pastday', 'Näytä menneet päivät')}
      <button class="ghost" data-act="md" data-d="-1" ${S.liveOnly || S.matchday <= (days[0] || 1) ? 'disabled' : ''}>‹</button>
      <b>Kierros ${S.matchday}</b>
      <button class="ghost" data-act="md" data-d="1" ${S.liveOnly || S.matchday >= (days[days.length - 1] || 1) ? 'disabled' : ''}>›</button></div>`}</div>`;
  if (!groups.length) return `${nav}<div class="panel" style="flex:none"><div class="empty"><b>${emptyText}</b></div></div>`;
  return `${nav}<div class="fx-scroll"><div class="fx-inner">${groups.map((g) => `
    <div><div class="fx-day">${g.title}</div><div class="fx-group">${g.items.map((m) => `
      <div class="fx-row ${m.status !== 'scheduled' ? 'open' : ''}" ${m.status !== 'scheduled' ? `data-act="match" data-id="${esc(m.id)}" title="Näytä ottelun tilastot"` : ''}><div class="fx-team home">${esc(m.home)}${badge(m.home, 36)}</div>${mid(m)}<div class="fx-team">${badge(m.away, 36)}${esc(m.away)}</div></div>`).join('')}</div></div>`).join('')}</div></div>`;
}

function settingsView() {
  return `<div class="modal-bg" data-act="close-bg"><div class="modal" role="dialog" aria-label="Asetukset">
    <h2>Asetukset</h2>
    <div><h3>football-data.org API-avain</h3>
      <input class="field" type="password" id="apikey" data-bind="apiKey" placeholder="Liitä avain tähän" value="${esc(S.apiKey)}" autocomplete="off">
      <div class="hint">Ilmainen avain: football-data.org/client/register. Valinnainen: ilman avainta kaikki sarjat haetaan ESPN:ltä. Avaimella kuuden suurimman sarjan taulukot ja ottelut tulevat football-datalta, ja pelaajien kansallisuudet (liput) haetaan joukkuekokoonpanoista. Avain tallennetaan salattuna tähän tietokoneeseen.</div></div>
    <div><h3>The Odds API -avain (vedonlyöntikertoimet)</h3>
      <input class="field" type="password" id="oddskey" data-bind="oddsKey" placeholder="Liitä avain tähän" value="${esc(S.oddsKey)}" autocomplete="off">
      <div class="hint">Valinnainen. Ilmainen avain osoitteessa the-odds-api.com (noin 500 krediittiä kuussa). Yksi sarjan haku maksaa 2 krediittiä; kertoimet tallennetaan 6 tunniksi.${S.oddsRemaining != null ? ` Krediittejä jäljellä: ${S.oddsRemaining}.` : ''}${S.oddsError ? `<br>${esc(S.oddsError)}` : ''}</div></div>
    <hr>
    <div><h3>Pelaajatilastot</h3>
      <div class="sub">${S.playersSource === 'understat' ? `Haettu Understatista · ${S.players.length} pelaajaa${S.playersUpdated ? ' · ' + new Date(S.playersUpdated).toLocaleString('fi-FI', { dateStyle: 'short', timeStyle: 'short' }) : ''}${S.playersPartial ? ' · osittain' : ''}` : S.playersSource === 'bundled' ? `Mukana tuleva Understat-data · ${S.players.length} pelaajaa${S.playersUpdated ? ' · tilanne ' + new Date(S.playersUpdated).toLocaleDateString('fi-FI') : ''}` : S.playersSource === 'imported' ? `Tuotu data · ${S.players.length} pelaajaa` : 'Ei pelaajadataa'}${S.enriching ? ' · haetaan kansallisuuksia…' : ''}</div>
      <div class="btns" style="margin-top:8px"><button class="ghost" data-act="updplayers" ${S.updatingPlayers ? 'disabled' : ''}>${S.updatingPlayers ? 'Haetaan…' : '⟳ Päivitä pelaajadata'}</button><button class="ghost" data-act="import">Tuo JSON…</button><button class="ghost" data-act="export">Vie JSON…</button><button class="ghost" data-act="reset">Palauta mukana tuleva data</button></div>
      <div class="hint">Päivitys hakee kausitilastot ja ottelukohtaiset laukaukset Understatista (viisi suurta sarjaa). Ensimmäinen haku kestää hetken, koska jokaisen ottelun laukaukset haetaan; sen jälkeen haetaan vain uudet ottelut. Päivitä-painike hakee pelaajadatan automaattisesti, kun edellisestä hausta on yli 6 tuntia. Tuotua dataa ei korvata automaattisesti.</div>
      ${S.message ? `<div class="msg">${esc(S.message)}</div>` : ''}</div>
    <hr>
    <div><h3>Sovelluksen kuvake</h3>
      <div class="icons">${ICONS.map((i) => `<button class="icon-pick ${S.icon === i.id ? 'sel' : ''}" data-act="icon" data-v="${i.id}"><img src="../assets/icons/${i.file}" alt="">${i.title}</button>`).join('')}</div>
      <div class="hint">Valinta vaihtaa ikkunan ja tehtäväpalkin kuvakkeen. Asennuksen ja työpöydän pikakuvakkeen kuvake on aina Yökenttä.</div></div>
    <div class="foot"><button class="ghost" data-act="close">Valmis</button></div>
  </div></div>`;
}

// ---------- piirto ja tapahtumat ----------

function render(resetScroll = false) {
  const app = document.getElementById('app');
  const act = document.activeElement;
  const keep = act && act.id ? { id: act.id, s: act.selectionStart, e: act.selectionEnd } : null;
  const sels = ['.scroll', '.fx-scroll', '.tm-list'];
  const tops = sels.map((s) => { const el = document.querySelector(s); return el ? el.scrollTop : 0; });
  app.innerHTML = view();
  if (keep) {
    const el = document.getElementById(keep.id);
    if (el) { el.focus(); try { el.setSelectionRange(keep.s, keep.e); } catch { /* ei tekstikenttä */ } }
  }
  if (!resetScroll) sels.forEach((s, i) => { const el = document.querySelector(s); if (el) el.scrollTop = tops[i]; });
}

function persistRatings() { window.api.saveStore({ ratings: S.ratings }); }
function onLeagueOrSection() {
  pickMatchday();
  render(true);
  if (S.league === null && S.section === 'fixtures' && !S.todayUpdated) refreshToday();
  refresh();
  ensureOdds();
}

document.addEventListener('click', async (e) => {
  const t = e.target.closest('[data-act]');
  if (!t) return;
  const a = t.dataset.act;
  if (a === 'close-bg') { if (e.target !== t) return; if (S.matchModal) S.matchModal = null; else if (S.playerModal) S.playerModal = null; else { S.settingsOpen = false; S.teamModal = null; } render(); return; }
  switch (a) {
    case 'league': S.league = t.dataset.v || null; S.team = ''; S.liveOnly = false; onLeagueOrSection(); break;
    case 'section': S.section = t.dataset.v; onLeagueOrSection(); break;
    case 'sort': {
      const k = t.dataset.key;
      if (S.sort === k) S.asc = !S.asc; else { S.sort = k; S.asc = (k === 'name' || k === 'team'); }
      render(true); break;
    }
    case 'stsort': setSort(t.dataset.key); render(true); break;
    case 'stmode':
      S.stMode = t.dataset.v;
      S.st = S.stMode === 'table' ? { key: 'position', asc: true } : S.stMode === 'ou' ? { key: 'over', asc: false } : { key: 'points', asc: false };
      render(true); break;
    case 'venue': S.venue = t.dataset.v; render(true); break;
    case 'line': S.line = +t.dataset.v; render(true); break;
    case 'team': S.teamModal = { name: t.dataset.name, count: 5, venue: 'all' }; render(); break;
    case 'tmcount': S.teamModal.count = +t.dataset.v; render(); break;
    case 'tmvenue': S.teamModal.venue = t.dataset.v; render(); break;
    case 'liveonly': S.liveOnly = !S.liveOnly; render(true); break;
    case 'pastday': S.hidePast = !S.hidePast; window.api.saveStore({ prefs: { hidePast: S.hidePast } }); render(true); break;
    case 'fav': S.favOnly = !S.favOnly; render(true); break;
    case 'clear': S.search = ''; S.team = ''; S.position = ''; S.favOnly = false; render(true); break;
    case 'star': {
      const id = t.dataset.id; const n = +t.dataset.n;
      if ((S.ratings[id] || 0) === n) delete S.ratings[id]; else S.ratings[id] = n;
      persistRatings(); render(); break;
    }
    case 'refresh':
      if (S.section === 'fixtures' && S.league === null) refreshToday(); else refresh(true);
      if (playersStale()) updatePlayers();
      break;
    case 'updplayers': updatePlayers(); break;
    case 'md': {
      const days = [...new Set((S.matches[focus()] || []).map((m) => m.matchday))].sort((a, b) => a - b);
      const i = days.indexOf(S.matchday) + (+t.dataset.d);
      if (i >= 0 && i < days.length) S.matchday = days[i];
      render(true); break;
    }
    case 'settings': S.settingsOpen = true; S.message = ''; render(); break;
    case 'player': openPlayer(t.dataset.id); break;
    case 'pmres': S.playerModal.result = t.dataset.v; render(); break;
    case 'pmsit': S.playerModal.sit = t.dataset.v; render(); break;
    case 'close': if (S.matchModal) S.matchModal = null; else if (S.playerModal) S.playerModal = null; else { S.settingsOpen = false; S.teamModal = null; } render(); break;
    case 'match': openMatch(findMatch(t.dataset.id)); break;
    case 'icon': S.icon = t.dataset.v; window.api.setIcon(S.icon); window.api.saveStore({ icon: S.icon }); render(); break;
    case 'import': {
      const res = await window.api.importPlayers();
      if (res.canceled) break;
      try {
        if (res.error) throw new Error(res.error);
        S.players = normalizePlayers(res.data);
        S.playersSource = 'imported'; S.playersPartial = false; S.playersUpdated = new Date().toISOString();
        applyNationalities();
        await window.api.savePlayers(S.players, 'import');
        S.message = `Tuotu ${S.players.length} pelaajaa`;
      } catch {
        S.message = 'Tiedostoa ei voitu lukea. Tarkista rakenne viemällä esimerkki ensin.';
      }
      render(true); break;
    }
    case 'export': {
      const res = await window.api.exportPlayers(S.players);
      if (res.ok) { S.message = 'Pelaajat viety'; render(); }
      break;
    }
    case 'reset': {
      await window.api.clearPlayers();
      const saved = await window.api.loadStore();
      S.players = saved.players ? normalizePlayers(saved.players) : [];
      S.playersSource = saved.playersSource || 'none'; S.playersUpdated = saved.playersUpdated || null; S.playersPartial = false; S.playersNote = '';
      applyNationalities();
      S.message = 'Mukana tuleva data palautettu'; render(true); break;
    }
  }
});

let searchTimer = null, keyTimer = null;
document.addEventListener('input', (e) => {
  const t = e.target;
  if (t.dataset.bind === 'search') {
    S.search = t.value;
    clearTimeout(searchTimer);
    searchTimer = setTimeout(() => render(true), 120);
  } else if (t.dataset.bind === 'apiKey') {
    S.apiKey = t.value;
    S.live = {};
    clearTimeout(keyTimer);
    keyTimer = setTimeout(() => { window.api.saveStore({ apiKey: S.apiKey }); }, 400);
  } else if (t.dataset.bind === 'oddsKey') {
    S.oddsKey = t.value;
    S.odds = {};
    clearTimeout(keyTimer);
    keyTimer = setTimeout(() => { window.api.saveStore({ oddsKey: S.oddsKey }); }, 400);
  }
});
document.addEventListener('change', (e) => {
  const t = e.target;
  if (t.dataset.bind === 'team') { S.team = t.value; render(true); }
  if (t.dataset.bind === 'position') { S.position = t.value; render(true); }
  if (t.dataset.bind === 'apiKey') { refresh(true); if (S.league === null && S.section === 'fixtures') refreshToday(); enrichNationalities(); }
  if (t.dataset.bind === 'oddsKey') { setTimeout(() => ensureOdds(true), 500); }
});
document.addEventListener('keydown', (e) => {
  if (e.key !== 'Escape') return;
  if (S.matchModal) { S.matchModal = null; render(); }
  else if (S.playerModal) { S.playerModal = null; render(); }
  else if (S.teamModal) { S.teamModal = null; render(); }
  else if (S.settingsOpen) { S.settingsOpen = false; render(); }
});

// Käynnissä olevien otteluiden tulokset päivittyvät minuutin välein
setInterval(() => {
  if (S.section !== 'fixtures' || !anyLive() || S.loading || S.loadingToday) return;
  if (S.league === null) refreshToday(); else refresh(true);
}, 60000);

async function init() {
  try {
    const saved = await window.api.loadStore();
    S.apiKey = saved.apiKey || '';
    S.oddsKey = saved.oddsKey || '';
    S.oddsRemaining = saved.oddsRemaining ?? null;
    S.hidePast = !(saved.prefs && saved.prefs.hidePast === false);
    S.ratings = saved.ratings || {};
    S.icon = saved.icon || 'night';
    S.nationalities = saved.nationalities || {};
    if (saved.players) { S.players = normalizePlayers(saved.players); S.playersSource = saved.playersSource; S.playersUpdated = saved.playersUpdated; S.playersPartial = !!saved.playersPartial; }
    applyNationalities();
  } catch { /* oletusarvot */ }
  pickMatchday();
  render(true);
  window.api.setIcon(S.icon);
  window.api.onPlayersProgress((p) => {
    S.playersStatus = (p && p.text) || '';
    const el = document.querySelector('[data-pstatus]');
    if (el) el.textContent = S.playersStatus;
  });
  refresh();
  ensureCrests();
  enrichNationalities();
  if (playersStale()) updatePlayers();
}
init();
