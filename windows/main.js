'use strict';
const { app, BrowserWindow, ipcMain, dialog, nativeImage, net, safeStorage, Menu } = require('electron');
const fs = require('fs');
const path = require('path');

// Sovelluksen nimi vaihtui (Jalkapallon Laukaustilasto -> Jalkapallotilastot): käytetään vanhaa tallennuskansiota,
// jotta avain, arvostelut ja tuodut pelaajat säilyvät päivityksessä.
app.setPath('userData', path.join(app.getPath('appData'), 'Jalkapallon Laukaustilasto'));

const ICON_FILES = { night: 'IconA.png', floodlight: 'IconB.png', pitchLine: 'IconC.png' };
// football-data.org: sarjakohtaiset haut sekä päivämääräväli kaikille sarjoille
const FD_PATH = /^\/(competitions\/(CL|PL|PD|SA|FL1|BL1)\/(standings|matches)|matches\?dateFrom=\d{4}-\d{2}-\d{2}&dateTo=\d{4}-\d{2}-\d{2})$/;
const ESPN_SLUG = /^[a-z0-9.]{3,32}$/;
const ESPN_KINDS = new Set(['scoreboard', 'standings', 'summary']);
const ESPN_QUERY = new Set(['dates', 'event']);
const ODDS_SPORT = /^soccer_[a-z_]{3,60}$/;
const ODDS_TTL = 6 * 3600 * 1000;

let win = null;

const settingsFile = () => path.join(app.getPath('userData'), 'settings.json');
const playersFile = () => path.join(app.getPath('userData'), 'players.json');
const oddsFile = () => path.join(app.getPath('userData'), 'odds-cache.json');

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
  const players = readJson(playersFile(), null);
  return {
    apiKey: unpackKey(settings, 'apiKey'),
    oddsKey: unpackKey(settings, 'oddsKey'),
    oddsRemaining: typeof settings.oddsRemaining === 'number' ? settings.oddsRemaining : null,
    prefs: settings.prefs && typeof settings.prefs === 'object' ? settings.prefs : {},
    ratings: settings.ratings || {},
    icon: ICON_FILES[settings.icon] ? settings.icon : 'night',
    players: Array.isArray(players) && players.length ? players : null
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

ipcMain.handle('players:save', (_e, players) => {
  if (!Array.isArray(players)) return false;
  writeJson(playersFile(), players);
  return true;
});

ipcMain.handle('players:clear', () => {
  try { fs.unlinkSync(playersFile()); } catch { /* ei tiedostoa */ }
  return true;
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
