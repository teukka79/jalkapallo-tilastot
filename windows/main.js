'use strict';
const { app, BrowserWindow, ipcMain, dialog, nativeImage, net, safeStorage, Menu } = require('electron');
const fs = require('fs');
const path = require('path');
const understat = require('./understat');

// Sovelluksen nimi vaihtui (Jalkapallon Laukaustilasto -> Jalkapallotilastot): käytetään vanhaa tallennuskansiota,
// jotta avain, arvostelut ja tuodut pelaajat säilyvät päivityksessä.
app.setPath('userData', path.join(app.getPath('appData'), 'Jalkapallon Laukaustilasto'));

const ICON_FILES = { night: 'IconA.png', floodlight: 'IconB.png', pitchLine: 'IconC.png' };
// football-data.org: sarjakohtaiset haut sekä päivämääräväli kaikille sarjoille
const FD_PATH = /^\/(competitions\/(CL|PL|PD|SA|FL1|BL1)\/(standings|matches)|matches\?dateFrom=\d{4}-\d{2}-\d{2}&dateTo=\d{4}-\d{2}-\d{2}|matches\/\d{1,10}|competitions\/(PL|PD|SA|FL1|BL1)\/teams)$/;
const ESPN_SLUG = /^[a-z0-9.]{3,32}$/;
const ESPN_KINDS = new Set(['scoreboard', 'standings', 'summary']);
const ESPN_QUERY = new Set(['dates', 'event']);
const ODDS_SPORT = /^soccer_[a-z_]{3,60}$/;
const ODDS_TTL = 6 * 3600 * 1000;

let win = null;

const settingsFile = () => path.join(app.getPath('userData'), 'settings.json');
const playersFile = () => path.join(app.getPath('userData'), 'players.json');
const oddsFile = () => path.join(app.getPath('userData'), 'odds-cache.json');
const shotsCacheFile = () => path.join(app.getPath('userData'), 'understat-shots.json');
const shotsFile = () => path.join(app.getPath('userData'), 'shots.json');
const SHOTS_CACHE_VERSION = 3;
const matchesFile = () => path.join(app.getPath('userData'), 'matches.json');

function readJson(file, fallback) {
  try { return JSON.parse(fs.readFileSync(file, 'utf8')); } catch { return fallback; }
}

function writeJson(file, data) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, JSON.stringify(data, null, 2));
}

function iconImage(id) {
  const file = ICON_FILES[id] || ICON_FILES.night;
  return nativeImage.createFromPath(path.join(__dirname, 'assets', 'icons', file));
}

// API-avaimet tallennetaan Windowsin salauksella, jos se on käytettävissä.
function packKey(prop, key) {
  if (!key) return {};
  if (safeStorage.isEncryptionAvailable()) {
    return { [prop + 'Enc']: safeStorage.encryptString(key).toString('base64') };
  }
  return { [prop]: key };
}

function unpackKey(settings, prop) {
  try {
    if (settings[prop + 'Enc'] && safeStorage.isEncryptionAvailable()) {
      return safeStorage.decryptString(Buffer.from(settings[prop + 'Enc'], 'base64'));
    }
  } catch { /* avain ei avaudu, pyydetään uudelleen */ }
  return settings[prop] || '';
}

function createWindow() {
  const settings = readJson(settingsFile(), {});
  win = new BrowserWindow({
    width: 1320,
    height: 860,
    minWidth: 1200,
    minHeight: 720,
    backgroundColor: '#080F12',
    title: 'Jalkapallotilastot',
    icon: iconImage(settings.icon),
    autoHideMenuBar: true,
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      contextIsolation: true,
      nodeIntegration: false,
      sandbox: true
    }
  });
  win.setMenuBarVisibility(false);
  win.webContents.setWindowOpenHandler(() => ({ action: 'deny' }));
  win.webContents.on('will-navigate', (e) => e.preventDefault());
  win.loadFile(path.join(__dirname, 'renderer', 'index.html'));
}

// ---- IPC ----

ipcMain.handle('store:load', () => {
  const settings = readJson(settingsFile(), {});
  const imported = readJson(playersFile(), null);
  let players = Array.isArray(imported) && imported.length ? imported : null;
  let playersSource = 'none';
  let playersUpdated = null;
  if (players) {
    playersSource = String(settings.playersKind || '').startsWith('understat') ? 'understat' : 'imported';
    try { playersUpdated = fs.statSync(playersFile()).mtime.toISOString(); } catch { /* ei aikaa */ }
  }
  if (!players) {
    // Sovelluksen mukana tuleva oikea pelaajadata (Understat)
    const bundled = path.join(__dirname, 'data', 'players.json');
    const data = readJson(bundled, null);
    if (Array.isArray(data) && data.length) {
      players = data; playersSource = 'bundled';
      try { playersUpdated = fs.statSync(bundled).mtime.toISOString(); } catch { /* ei aikaa */ }
    }
  }
  return {
    apiKey: unpackKey(settings, 'apiKey'),
    oddsKey: unpackKey(settings, 'oddsKey'),
    oddsRemaining: typeof settings.oddsRemaining === 'number' ? settings.oddsRemaining : null,
    prefs: settings.prefs && typeof settings.prefs === 'object' ? settings.prefs : {},
    ratings: settings.ratings || {},
    icon: ICON_FILES[settings.icon] ? settings.icon : 'night',
    players, playersSource, playersUpdated, playersPartial: settings.playersKind === 'understat-partial',
    nationalities: settings.nationalities && typeof settings.nationalities === 'object' ? settings.nationalities : {}
  };
});

ipcMain.handle('store:save', (_e, patch) => {
  const settings = readJson(settingsFile(), {});
  if (patch && typeof patch === 'object') {
    for (const prop of ['apiKey', 'oddsKey']) {
      if (prop in patch) {
        delete settings[prop];
        delete settings[prop + 'Enc'];
        Object.assign(settings, packKey(prop, String(patch[prop] || '')));
      }
    }
    if ('ratings' in patch && patch.ratings && typeof patch.ratings === 'object') settings.ratings = patch.ratings;
    if ('icon' in patch && ICON_FILES[patch.icon]) settings.icon = patch.icon;
    if ('nationalities' in patch && patch.nationalities && typeof patch.nationalities === 'object') settings.nationalities = patch.nationalities;
    if ('prefs' in patch && patch.prefs && typeof patch.prefs === 'object') {
      settings.prefs = { hidePast: patch.prefs.hidePast !== false };
    }
  }
  writeJson(settingsFile(), settings);
  return true;
});

ipcMain.handle('icon:set', (_e, id) => {
  if (!ICON_FILES[id] || !win) return false;
  win.setIcon(iconImage(id));
  return true;
});

async function getJson(url, headers) {
  try {
    const res = await net.fetch(url, headers ? { headers } : undefined);
    let body = null;
    try { body = await res.json(); } catch { /* ei JSON-vastaus */ }
    return { status: res.status, body, headers: res.headers };
  } catch {
    return { status: -1, body: null, headers: null };
  }
}

ipcMain.handle('fd:get', async (_e, apiPath, key) => {
  if (typeof apiPath !== 'string' || !FD_PATH.test(apiPath)) return { status: 0, body: null };
  const res = await getJson('https://api.football-data.org/v4' + apiPath, { 'X-Auth-Token': String(key || '') });
  return { status: res.status, body: res.body };
});

// ESPN:n julkinen rajapinta (ei avainta): vain sallitut polut ja kyselyparametrit
ipcMain.handle('espn:get', async (_e, req) => {
  const { slug, kind, query } = req || {};
  if (typeof slug !== 'string' || !ESPN_SLUG.test(slug) || !ESPN_KINDS.has(kind)) return { status: 0, body: null };
  const params = new URLSearchParams();
  for (const [k, v] of Object.entries(query || {})) {
    if (!ESPN_QUERY.has(k) || !/^[0-9A-Za-z-]{1,24}$/.test(String(v))) return { status: 0, body: null };
    params.set(k, String(v));
  }
  const base = kind === 'standings'
    ? 'https://site.api.espn.com/apis/v2/sports/soccer/'
    : 'https://site.api.espn.com/apis/site/v2/sports/soccer/';
  const qs = params.toString();
  const res = await getJson(`${base}${slug}/${kind}${qs ? '?' + qs : ''}`);
  return { status: res.status, body: res.body };
});

// The Odds API: haku kuuden tunnin välimuistilla (ilmainen taso ~500 krediittiä kuussa, haku = 2 krediittiä)
function summarizeOdds(events) {
  const mean = (a) => (a.length ? a.reduce((x, y) => x + y, 0) / a.length : null);
  return (Array.isArray(events) ? events : []).map((ev) => {
    const hp = [], dp = [], ap = [], op = [], up = [];
    for (const bm of ev.bookmakers || []) {
      for (const mk of bm.markets || []) {
        for (const o of mk.outcomes || []) {
          if (mk.key === 'h2h') {
            if (o.name === ev.home_team) hp.push(o.price);
            else if (o.name === ev.away_team) ap.push(o.price);
            else if (o.name === 'Draw') dp.push(o.price);
          } else if (mk.key === 'totals' && o.point === 2.5) {
            if (o.name === 'Over') op.push(o.price); else if (o.name === 'Under') up.push(o.price);
          }
        }
      }
    }
    return {
      homeName: ev.home_team, awayName: ev.away_team, commence: ev.commence_time,
      home: mean(hp), draw: mean(dp), away: mean(ap), line: 2.5, over: mean(op), under: mean(up),
      bookmakers: (ev.bookmakers || []).length
    };
  });
}

ipcMain.handle('odds:get', async (_e, sport, key, force) => {
  if (typeof sport !== 'string' || !ODDS_SPORT.test(sport)) return { status: 0, entries: [] };
  const settings = readJson(settingsFile(), {});
  const remaining = typeof settings.oddsRemaining === 'number' ? settings.oddsRemaining : null;
  const cache = readJson(oddsFile(), {});
  const hit = cache[sport];
  if (hit && !force && Date.now() - hit.fetched < ODDS_TTL) {
    return { status: 200, entries: hit.entries, fetched: hit.fetched, cached: true, remaining };
  }
  const stale = hit ? hit.entries : [];
  if (!key) return { status: stale.length ? 200 : 401, entries: stale, remaining };
  if (remaining !== null && remaining < 2) return { status: 429, entries: stale, remaining };
  const url = `https://api.the-odds-api.com/v4/sports/${sport}/odds?apiKey=${encodeURIComponent(String(key))}`
    + '&regions=eu&markets=h2h,totals&oddsFormat=decimal&dateFormat=iso';
  const res = await getJson(url);
  const left = res.headers ? parseInt(res.headers.get('x-requests-remaining'), 10) : NaN;
  if (Number.isFinite(left)) { settings.oddsRemaining = left; writeJson(settingsFile(), settings); }
  const rem = Number.isFinite(left) ? left : remaining;
  if (res.status === 200 || res.status === 404 || res.status === 422) {
    const entries = res.status === 200 ? summarizeOdds(res.body) : [];
    cache[sport] = { fetched: Date.now(), entries };
    writeJson(oddsFile(), cache);
    return { status: 200, entries, fetched: Date.now(), cached: false, remaining: rem };
  }
  return { status: res.status, entries: stale, remaining: rem };
});

function setPlayersKind(kind) {
  const settings = readJson(settingsFile(), {});
  if (kind) settings.playersKind = kind; else delete settings.playersKind;
  writeJson(settingsFile(), settings);
}

ipcMain.handle('players:save', (_e, players, kind) => {
  if (!Array.isArray(players)) return false;
  writeJson(playersFile(), players);
  setPlayersKind(kind === 'understat' || kind === 'understat-partial' ? kind : 'import');
  return true;
});

ipcMain.handle('players:clear', () => {
  try { fs.unlinkSync(playersFile()); } catch { /* ei tiedostoa */ }
  setPlayersKind(null);
  return true;
});

// Understat-haku: vain moduulin rakentamat understat.com-osoitteet
async function understatGet(url, opts = {}) {
  const headers = { Accept: opts.ajax ? 'application/json, text/javascript, */*; q=0.01' : 'text/html,application/xhtml+xml,*/*' };
  if (opts.ajax) headers['X-Requested-With'] = 'XMLHttpRequest';
  if (opts.referer) headers.Referer = opts.referer;
  let last = new Error('haku epäonnistui');
  for (let i = 0; i < 3; i++) {
    const ctrl = new AbortController();
    const timer = setTimeout(() => ctrl.abort(), 25000);
    try {
      const res = await net.fetch(url, { headers, signal: ctrl.signal });
      if (res.status === 429 || res.status >= 500) throw new Error('HTTP ' + res.status);
      if (!res.ok) { const err = new Error('HTTP ' + res.status); err.noRetry = true; throw err; }
      return await res.text();
    } catch (e) {
      last = e;
      if (e && e.noRetry) break;
      await new Promise((r) => setTimeout(r, 800 * (i + 1)));
    } finally {
      clearTimeout(timer);
    }
  }
  throw last;
}

let shotsMem = null;
function getShots() {
  if (!shotsMem) {
    const data = readJson(shotsFile(), null);
    shotsMem = data && data.shots && typeof data.shots === 'object' ? data.shots : null;
  }
  return shotsMem || {};
}

ipcMain.handle('shots:get', (_e, playerId) => {
  if (typeof playerId !== 'string' || !/^[A-Za-z0-9._-]{1,40}$/.test(playerId)) return { available: false, shots: [] };
  const all = getShots();
  const available = shotsMem !== null && Object.keys(all).length > 0;
  return { available, shots: Array.isArray(all[playerId]) ? all[playerId] : [] };
});

let matchesMem = null;
function getMatches() {
  if (!matchesMem) {
    const data = readJson(matchesFile(), null);
    matchesMem = data && data.matches && typeof data.matches === 'object' ? data.matches : null;
  }
  return matchesMem || {};
}

ipcMain.handle('matches:get', () => getMatches());

let playersFetch = null;
ipcMain.handle('players:fetch', () => {
  if (playersFetch) return playersFetch;
  const send = (p) => { try { if (win && !win.isDestroyed()) win.webContents.send('players:progress', p); } catch { /* ikkuna suljettu */ } };
  playersFetch = (async () => {
    const year = understat.defaultSeasonYear();
    const stored = readJson(shotsCacheFile(), {});
    const cache = { v: SHOTS_CACHE_VERSION, [year]: stored.v === SHOTS_CACHE_VERSION ? stored[year] || {} : {} }; // vain kuluva kausi säilytetään
    try {
      const r = await understat.fetchPlayers({ getText: understatGet, year, cache, onProgress: send });
      fs.mkdirSync(path.dirname(shotsCacheFile()), { recursive: true });
      fs.writeFileSync(shotsCacheFile(), JSON.stringify(cache));
      // Laukauskartan tiedot: epäonnistuneiden sarjojen vanhat laukaukset säilyvät
      const lost = new Set(r.failed.map((f) => f.league));
      const merged = {};
      for (const [id, list] of Object.entries(getShots())) if (lost.has(id.split('-')[0])) merged[id] = list;
      Object.assign(merged, r.shots);
      fs.writeFileSync(shotsFile(), JSON.stringify({ shots: merged }));
      shotsMem = merged;
      // Ottelukohtaiset tiedot (Viim. ottelut -sarake): samoin epäonnistuneiden sarjojen vanhat säilyvät
      const mergedMatches = {};
      for (const [id, list] of Object.entries(getMatches())) if (lost.has(id.split('-')[0])) mergedMatches[id] = list;
      Object.assign(mergedMatches, r.matches);
      fs.writeFileSync(matchesFile(), JSON.stringify({ matches: mergedMatches }));
      matchesMem = mergedMatches;
      return { ok: true, players: r.players, failed: r.failed };
    } catch (e) {
      return { ok: false, error: e && e.message ? e.message : String(e) };
    }
  })().finally(() => { playersFetch = null; });
  return playersFetch;
});

ipcMain.handle('players:import', async () => {
  const result = await dialog.showOpenDialog(win, {
    title: 'Tuo pelaajat',
    filters: [{ name: 'JSON', extensions: ['json'] }],
    properties: ['openFile']
  });
  if (result.canceled || !result.filePaths.length) return { canceled: true };
  try {
    return { data: JSON.parse(fs.readFileSync(result.filePaths[0], 'utf8')) };
  } catch {
    return { error: 'Tiedostoa ei voitu lukea.' };
  }
});

ipcMain.handle('players:export', async (_e, players) => {
  const result = await dialog.showSaveDialog(win, {
    title: 'Vie pelaajat',
    defaultPath: 'pelaajat.json',
    filters: [{ name: 'JSON', extensions: ['json'] }]
  });
  if (result.canceled || !result.filePath) return { canceled: true };
  fs.writeFileSync(result.filePath, JSON.stringify(players, null, 2));
  return { ok: true };
});

app.whenReady().then(() => {
  Menu.setApplicationMenu(null);
  createWindow();
  app.on('activate', () => { if (BrowserWindow.getAllWindows().length === 0) createWindow(); });
});

app.on('window-all-closed', () => { if (process.platform !== 'darwin') app.quit(); });
