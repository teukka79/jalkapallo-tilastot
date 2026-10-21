'use strict';

const LEAGUES = [
  { code: 'CL', name: 'Mestarien liiga', accent: '#5AA9FF' },
  { code: 'PL', name: 'Valioliiga', accent: '#9B7BFF' },
  { code: 'PD', name: 'La Liga', accent: '#FF7A59' },
  { code: 'SA', name: 'Serie A', accent: '#3FD0C9' },
  { code: 'FL1', name: 'Ligue 1', accent: '#D6E85A' },
  { code: 'BL1', name: 'Bundesliiga', accent: '#FF5C7A' }
];
const POSITIONS = ['Maalivahti', 'Puolustaja', 'Keskikenttä', 'Hyökkääjä'];
const ICONS = [
  { id: 'night', title: 'Yökenttä', file: 'IconA.png' },
  { id: 'floodlight', title: 'Valonheitin', file: 'IconB.png' },
  { id: 'pitchLine', title: 'Kenttäviiva', file: 'IconC.png' }
];
const SORTS = {
  name: (p) => p.name, team: (p) => p.team,
  appearances: (p) => p.appearances, goals: (p) => p.goals, shots: (p) => p.shots,
  shotsOnTarget: (p) => p.shotsOnTarget, shotsOnTargetOutsideBox: (p) => p.shotsOnTargetOutsideBox,
  shotsOutsideBox: (p) => p.shotsOutsideBox, onTargetPercent: (p) => onTargetPct(p), perGame: (p) => perGame(p)
};
const leagueOf = (code) => LEAGUES.find((l) => l.code === code);

const S = {
  league: null, section: 'players',
  players: [], playersAreSample: true,
  matches: {}, standings: {}, crests: {}, live: {}, updatedAt: {},
  loading: false, error: null,
  ratings: {}, apiKey: '', icon: 'night',
  search: '', team: '', position: '', favOnly: false, sort: 'goals', asc: false,
  matchday: 1, settingsOpen: false, message: ''
};
const focus = () => S.league || 'PL';

// ---------- apurit ----------

const esc = (v) => String(v ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const num = (x) => (Number.isFinite(+x) ? +x : 0);
const onTargetPct = (p) => (p.shots > 0 ? (p.shotsOnTarget / p.shots) * 100 : 0);
const perGame = (p) => (p.appearances > 0 ? p.shots / p.appearances : 0);
const fmt1 = (v) => v.toLocaleString('fi-FI', { minimumFractionDigits: 1, maximumFractionDigits: 1 });
const pad2 = (n) => String(n).padStart(2, '0');
const clock = (iso) => { const d = new Date(iso); return `${pad2(d.getHours())}:${pad2(d.getMinutes())}`; };
const dayHeading = (d) => {
  const s = new Intl.DateTimeFormat('fi-FI', { weekday: 'long', day: 'numeric', month: 'long' }).format(d);
  return s.charAt(0).toUpperCase() + s.slice(1);
};
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
  return /^[A-Za-z]{2}$/.test(n) ? n.toUpperCase() : '';
}
// Windows ei piirrä lippuemojeja, joten näytetään lippukuva ja varana maakoodi.
function flagHtml(n) {
  const code = flagCode(n);
  if (!code) return esc(n);
  return `<span class="flag"><img src="https://flagcdn.com/24x18/${code.toLowerCase()}.png" alt=""><span class="code">${code}</span></span>`;
}

function badge(name, size = 28) {
  const url = S.crests[name];
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

function loadSample() {
  S.players = []; S.matches = {}; S.standings = {};
  LEAGUES.forEach((l) => {
    S.players.push(...Sample.players(l.code));
    S.matches[l.code] = Sample.matches(l.code);
    S.standings[l.code] = Sample.standings(S.matches[l.code], Sample.TEAMS[l.code]);
  });
  S.playersAreSample = true;
}

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

async function fdGet(path) {
  const res = await window.api.footballData(path, S.apiKey.trim());
  if (res.status === 429) throw new Error('Kyselyraja täynnä, yritä minuutin kuluttua uudelleen');
  if (res.status === 401 || res.status === 403) throw new Error('API-avain ei kelpaa tähän sarjaan');
  if (res.status <= 0) throw new Error('Yhteys football-data.org:iin epäonnistui');
  if (res.status < 200 || res.status >= 300) throw new Error(`Palvelin vastasi virheellä ${res.status}`);
  return res.body;
}

async function refresh(force = false) {
  if (!S.apiKey.trim()) return;
  const code = focus();
  if (!force && S.live[code]) return;
  S.loading = true; S.error = null; render();
  try {
    const [st, ma] = await Promise.all([
      fdGet(`/competitions/${code}/standings`),
      fdGet(`/competitions/${code}/matches`)
    ]);
    const tname = (t) => t.shortName || t.name;
    const groups = st.standings || [];
    const group = groups.find((g) => g.type === 'TOTAL') || groups[0];
    const rows = (group ? group.table : []).map((r) => {
      if (r.team.crest) S.crests[tname(r.team)] = r.team.crest;
      return {
        position: r.position, team: tname(r.team), played: r.playedGames, won: r.won, drawn: r.draw, lost: r.lost,
        goalsFor: r.goalsFor, goalsAgainst: r.goalsAgainst, points: r.points,
        form: (r.form || '').split(',').filter(Boolean)
      };
    });
    const games = (ma.matches || []).map((m) => {
      if (m.homeTeam.crest) S.crests[tname(m.homeTeam)] = m.homeTeam.crest;
      if (m.awayTeam.crest) S.crests[tname(m.awayTeam)] = m.awayTeam.crest;
      const status = ['FINISHED', 'AWARDED'].includes(m.status) ? 'finished'
        : ['IN_PLAY', 'PAUSED'].includes(m.status) ? 'live' : 'scheduled';
      return {
        id: `${code}-${m.id}`, league: code, matchday: m.matchday || 0, date: m.utcDate,
        home: tname(m.homeTeam), away: tname(m.awayTeam),
        homeGoals: m.score.fullTime.home, awayGoals: m.score.fullTime.away, status
      };
    });
    S.standings[code] = rows; S.matches[code] = games;
    S.live[code] = true; S.updatedAt[code] = new Date();
    pickMatchday();
  } catch (e) {
    S.error = e.message;
  }
  S.loading = false; render();
}

function pickMatchday() {
  const games = S.matches[focus()] || [];
  const open = games.filter((m) => m.status !== 'finished' && m.matchday > 0).map((m) => m.matchday);
  const all = games.map((m) => m.matchday);
  S.matchday = open.length ? Math.min(...open) : (all.length ? Math.max(...all) : 1);
}

// ---------- näkymät ----------

function view() {
  const rated = Object.values(S.ratings).filter((v) => v > 0).length;
  const code = focus();
  const live = S.live[code];
  const status = live
    ? `${leagueOf(code).name}: live-data, päivitetty ${pad2(S.updatedAt[code].getHours())}:${pad2(S.updatedAt[code].getMinutes())}`
    : (S.apiKey.trim() ? 'Taulukot ja ottelut: esimerkkidata, haetaan…' : 'Taulukot ja ottelut: esimerkkidata\nLisää API-avain asetuksissa');
  return `<div class="app">
    <div class="header">
      <div class="titles"><h1>Jalkapallon Laukaustilasto</h1>
        <div class="sub">Kausi 2026/2027 · ${S.players.length} pelaajaa · ${rated} arvosteltu</div></div>
      <div class="status ${live ? 'live' : ''}">${esc(status)}</div>
      <button class="ghost" data-act="refresh" ${S.loading || !S.apiKey.trim() ? 'disabled' : ''}>⟳ ${S.loading ? 'Haetaan…' : 'Päivitä'}</button>
      <button class="ghost" data-act="settings" title="Asetukset">⚙</button>
    </div>
    <div class="chips">
      <button class="chip ${S.league === null ? 'sel' : ''}" data-act="league" data-v="" style="--c:var(--amber)">Kaikki</button>
      ${LEAGUES.map((l) => `<button class="chip ${S.league === l.code ? 'sel' : ''}" data-act="league" data-v="${l.code}" style="--c:${l.accent}"><i></i>${esc(l.name)}</button>`).join('')}
    </div>
    <div class="toolbar">
      <div class="seg">${[['players', 'Pelaajat'], ['standings', 'Sarjataulukko'], ['fixtures', 'Otteluohjelma']]
        .map(([id, label]) => `<button class="${S.section === id ? 'sel' : ''}" data-act="section" data-v="${id}">${label}</button>`).join('')}</div>
      ${S.error ? `<span class="err">⚠ ${esc(S.error)}</span>` : ''}
    </div>
    ${S.section === 'players' ? playersView() : S.section === 'standings' ? standingsView() : fixturesView()}
  </div>${S.settingsOpen ? settingsView() : ''}`;
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
  const rows = filteredPlayers();
  const scope = S.league ? S.players.filter((p) => p.league === S.league) : S.players;
  const teams = [...new Set(scope.map((p) => p.team))].sort((a, b) => a.localeCompare(b, 'fi'));
  const H = (label, key, help, left) => `<button class="hcell ${left ? 'left' : ''} ${S.sort === key ? 'hot' : ''}" data-act="sort" data-key="${key}" title="${esc(help || label.replace('\n', ' '))}">${label}${S.sort === key ? (S.asc ? ' ▴' : ' ▾') : ''}</button>`;
  const plain = (label) => `<button class="hcell" disabled>${label}</button>`;
  return `
    ${S.playersAreSample ? `<div class="banner"><b>ⓘ</b> Esimerkkidata: pelaajat ja luvut on generoitu havainnollistamiseen. Tuo omat tilastot asetuksista (JSON).</div>` : ''}
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
    <div class="cell player">${badge(p.team, 30)}<div style="min-width:0"><div class="pname">${esc(p.name)}</div>
      <div class="psub">${lg ? `<i style="--c:${lg.accent}"></i>` : ''}${esc(p.team)}</div></div></div>
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

function zoneOf(pos, count, code) {
  if (code === 'CL') return pos <= 8 ? 'var(--pos)' : pos <= 24 ? 'var(--eu)' : 'transparent';
  if (pos <= 4) return 'var(--pos)';
  if (pos <= 6) return 'var(--eu)';
  if (count > 0 && pos > count - 3) return 'var(--neg)';
  return 'transparent';
}

function standingsView() {
  const code = focus(); const lg = leagueOf(code);
  const rows = S.standings[code] || [];
  const note = S.league === null ? '<small>· valitse sarja yläpalkista</small>' : '';
  const legend = code === 'CL'
    ? '<span><i style="background:var(--pos)"></i>Suoraan jatkoon</span><span><i style="background:var(--eu)"></i>Jatkopelit</span>'
    : '<span><i style="background:var(--pos)"></i>Mestarien liiga</span><span><i style="background:var(--eu)"></i>Eurooppa-sarjat</span><span><i style="background:var(--neg)"></i>Putoamisalue</span>';
  const th = (t, left) => `<button class="hcell ${left ? 'left' : ''}" disabled style="height:36px">${t}</button>`;
  return `<div class="st-title">${esc(lg.name)} ${note}</div>
    <div class="panel">
      <div class="head st-cols">${th('#')}${th('Joukkue', true)}${th('O')}${th('V')}${th('T')}${th('H')}${th('Maalit')}${th('ME')}${th('P')}${th('Muoto')}</div>
      ${rows.length ? `<div class="scroll">${rows.map((r) => {
        const gd = r.goalsFor - r.goalsAgainst;
        return `<div class="row st-row st-cols" style="--z:${zoneOf(r.position, rows.length, code)}">
          <div class="pos">${r.position}</div>
          <div class="team">${badge(r.team, 26)}<span>${esc(r.team)}</span></div>
          <div class="cell num">${r.played}</div><div class="cell num">${r.won}</div><div class="cell num">${r.drawn}</div><div class="cell num">${r.lost}</div>
          <div class="cell num">${r.goalsFor}:${r.goalsAgainst}</div>
          <div class="cell num gd ${gd > 0 ? 'pos' : gd < 0 ? 'neg' : 'zero'}">${gd > 0 ? '+' + gd : gd}</div>
          <div class="cell num pts">${r.points}</div>
          <div class="cell"><span class="form">${r.form.map((f) => `<i class="${f}"></i>`).join('')}</span></div>
        </div>`;
      }).join('')}</div>` : '<div class="empty"><b>Sarjataulukkoa ei ole vielä saatavilla</b></div>'}
    </div>
    <div class="legend">${legend}</div>`;
}

function fixturesView() {
  const code = focus(); const lg = leagueOf(code);
  const all = S.matches[code] || [];
  const days = [...new Set(all.map((m) => m.matchday))].sort((a, b) => a - b);
  const cur = all.filter((m) => m.matchday === S.matchday).sort((a, b) => new Date(a.date) - new Date(b.date));
  const groups = new Map();
  cur.forEach((m) => {
    const d = new Date(m.date); const k = new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime();
    if (!groups.has(k)) groups.set(k, []);
    groups.get(k).push(m);
  });
  const mid = (m) => m.status === 'scheduled'
    ? `<div class="fx-mid sched">${clock(m.date)}</div>`
    : `<div class="fx-mid ${m.status === 'live' ? 'live' : ''}">${m.homeGoals ?? 0} – ${m.awayGoals ?? 0}</div>`;
  const note = S.league === null ? '<small>· valitse sarja yläpalkista</small>' : '';
  return `<div class="fx-nav"><div class="fx-title grow" style="flex:1">${esc(lg.name)} ${note}</div>
      <button class="ghost" data-act="md" data-d="-1" ${S.matchday <= (days[0] || 1) ? 'disabled' : ''}>‹</button>
      <b>Kierros ${S.matchday}</b>
      <button class="ghost" data-act="md" data-d="1" ${S.matchday >= (days[days.length - 1] || 1) ? 'disabled' : ''}>›</button></div>
    ${cur.length ? `<div class="fx-scroll">${[...groups.entries()].sort((a, b) => a[0] - b[0]).map(([k, list]) => `
      <div><div class="fx-day">${dayHeading(new Date(k))}</div><div class="fx-group">${list.map((m) => `
        <div class="fx-row"><div class="fx-team home">${esc(m.home)}${badge(m.home, 28)}</div>${mid(m)}<div class="fx-team">${badge(m.away, 28)}${esc(m.away)}</div></div>`).join('')}</div></div>`).join('')}</div>`
      : '<div class="panel"><div class="empty"><b>Otteluita ei ole vielä saatavilla</b></div></div>'}`;
}

function settingsView() {
  return `<div class="modal-bg" data-act="close-bg"><div class="modal" role="dialog" aria-label="Asetukset">
    <h2>Asetukset</h2>
    <div><h3>football-data.org API-avain</h3>
      <input class="field" type="password" id="apikey" data-bind="apiKey" placeholder="Liitä avain tähän" value="${esc(S.apiKey)}" autocomplete="off">
      <div class="hint">Ilmainen avain: football-data.org/client/register. Se antaa live-sarjataulukot ja otteluohjelmat kaikille kuudelle sarjalle (10 kyselyä minuutissa). Avain tallennetaan salattuna tähän tietokoneeseen.</div></div>
    <hr>
    <div><h3>Pelaajatilastot</h3>
      <div class="sub">${S.playersAreSample ? 'Käytössä esimerkkidata' : `Käytössä tuotu data · ${S.players.length} pelaajaa`}</div>
      <div class="btns" style="margin-top:8px"><button class="ghost" data-act="import">Tuo JSON…</button><button class="ghost" data-act="export">Vie JSON…</button><button class="ghost" data-act="reset">Palauta esimerkkidata</button></div>
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
  const sc = document.querySelector('.scroll');
  const top = sc ? sc.scrollTop : 0;
  app.innerHTML = view();
  if (keep) {
    const el = document.getElementById(keep.id);
    if (el) { el.focus(); try { el.setSelectionRange(keep.s, keep.e); } catch { /* ei tekstikenttä */ } }
  }
  const sc2 = document.querySelector('.scroll');
  if (sc2 && !resetScroll) sc2.scrollTop = top;
}

function persistRatings() { window.api.saveStore({ ratings: S.ratings }); }

document.addEventListener('click', async (e) => {
  const t = e.target.closest('[data-act]');
  if (!t) return;
  const a = t.dataset.act;
  if (a === 'close-bg') { if (e.target !== t) return; S.settingsOpen = false; render(); return; }
  switch (a) {
    case 'league': S.league = t.dataset.v || null; S.team = ''; pickMatchday(); render(true); refresh(); break;
    case 'section': S.section = t.dataset.v; render(true); break;
    case 'sort': {
      const k = t.dataset.key;
      if (S.sort === k) S.asc = !S.asc; else { S.sort = k; S.asc = (k === 'name' || k === 'team'); }
      render(true); break;
    }
    case 'fav': S.favOnly = !S.favOnly; render(true); break;
    case 'clear': S.search = ''; S.team = ''; S.position = ''; S.favOnly = false; render(true); break;
    case 'star': {
      const id = t.dataset.id; const n = +t.dataset.n;
      if ((S.ratings[id] || 0) === n) delete S.ratings[id]; else S.ratings[id] = n;
      persistRatings(); render(); break;
    }
    case 'refresh': refresh(true); break;
    case 'md': {
      const days = [...new Set((S.matches[focus()] || []).map((m) => m.matchday))].sort((a, b) => a - b);
      const i = days.indexOf(S.matchday) + (+t.dataset.d);
      if (i >= 0 && i < days.length) S.matchday = days[i];
      render(true); break;
    }
    case 'settings': S.settingsOpen = true; S.message = ''; render(); break;
    case 'close': S.settingsOpen = false; render(); break;
    case 'icon': S.icon = t.dataset.v; window.api.setIcon(S.icon); window.api.saveStore({ icon: S.icon }); render(); break;
    case 'import': {
      const res = await window.api.importPlayers();
      if (res.canceled) break;
      try {
        if (res.error) throw new Error(res.error);
        S.players = normalizePlayers(res.data);
        S.playersAreSample = false;
        await window.api.savePlayers(S.players);
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
    case 'reset':
      await window.api.clearPlayers();
      S.players = LEAGUES.flatMap((l) => Sample.players(l.code));
      S.playersAreSample = true; S.message = 'Esimerkkidata palautettu'; render(true); break;
  }
});

let searchTimer = null;
document.addEventListener('input', (e) => {
  const t = e.target;
  if (t.dataset.bind === 'search') {
    S.search = t.value;
    clearTimeout(searchTimer);
    searchTimer = setTimeout(() => render(true), 120);
  } else if (t.dataset.bind === 'apiKey') {
    S.apiKey = t.value;
    S.live = {};
    clearTimeout(searchTimer);
    searchTimer = setTimeout(() => { window.api.saveStore({ apiKey: S.apiKey }); }, 400);
  }
});
document.addEventListener('change', (e) => {
  const t = e.target;
  if (t.dataset.bind === 'team') { S.team = t.value; render(true); }
  if (t.dataset.bind === 'position') { S.position = t.value; render(true); }
  if (t.dataset.bind === 'apiKey') { refresh(true); }
});
document.addEventListener('keydown', (e) => { if (e.key === 'Escape' && S.settingsOpen) { S.settingsOpen = false; render(); } });

async function init() {
  loadSample();
  try {
    const saved = await window.api.loadStore();
    S.apiKey = saved.apiKey || '';
    S.ratings = saved.ratings || {};
    S.icon = saved.icon || 'night';
    if (saved.players) { S.players = normalizePlayers(saved.players); S.playersAreSample = false; }
  } catch { /* oletusarvot */ }
  pickMatchday();
  render(true);
  window.api.setIcon(S.icon);
  refresh();
}
init();
