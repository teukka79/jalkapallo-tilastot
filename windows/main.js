'use strict';
const { app, BrowserWindow, ipcMain, dialog, nativeImage, net, safeStorage, Menu } = require('electron');
const fs = require('fs');
const path = require('path');

const ICON_FILES = { night: 'IconA.png', floodlight: 'IconB.png', pitchLine: 'IconC.png' };
const FD_PATH = /^\/competitions\/(CL|PL|PD|SA|FL1|BL1)\/(standings|matches)$/;

let win = null;

const settingsFile = () => path.join(app.getPath('userData'), 'settings.json');
const playersFile = () => path.join(app.getPath('userData'), 'players.json');

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

// API-avain tallennetaan Windowsin salauksella, jos se on käytettävissä.
function packKey(key) {
  if (!key) return { apiKey: '' };
  if (safeStorage.isEncryptionAvailable()) {
    return { apiKeyEnc: safeStorage.encryptString(key).toString('base64') };
  }
  return { apiKey: key };
}

function unpackKey(settings) {
  try {
    if (settings.apiKeyEnc && safeStorage.isEncryptionAvailable()) {
      return safeStorage.decryptString(Buffer.from(settings.apiKeyEnc, 'base64'));
    }
  } catch { /* avain ei avaudu, pyydetään uudelleen */ }
  return settings.apiKey || '';
}

function createWindow() {
  const settings = readJson(settingsFile(), {});
  win = new BrowserWindow({
    width: 1320,
    height: 860,
    minWidth: 1200,
    minHeight: 720,
    backgroundColor: '#080F12',
    title: 'Jalkapallon Laukaustilasto',
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
    apiKey: unpackKey(settings),
    ratings: settings.ratings || {},
    icon: ICON_FILES[settings.icon] ? settings.icon : 'night',
    players: Array.isArray(players) && players.length ? players : null
  };
});

ipcMain.handle('store:save', (_e, patch) => {
  const settings = readJson(settingsFile(), {});
  if (patch && typeof patch === 'object') {
    if ('apiKey' in patch) {
      delete settings.apiKey;
      delete settings.apiKeyEnc;
      Object.assign(settings, packKey(String(patch.apiKey || '')));
    }
    if ('ratings' in patch && patch.ratings && typeof patch.ratings === 'object') settings.ratings = patch.ratings;
    if ('icon' in patch && ICON_FILES[patch.icon]) settings.icon = patch.icon;
  }
  writeJson(settingsFile(), settings);
  return true;
});

ipcMain.handle('icon:set', (_e, id) => {
  if (!ICON_FILES[id] || !win) return false;
  win.setIcon(iconImage(id));
  return true;
});

ipcMain.handle('fd:get', async (_e, apiPath, key) => {
  if (typeof apiPath !== 'string' || !FD_PATH.test(apiPath)) return { status: 0, body: null };
  try {
    const res = await net.fetch('https://api.football-data.org/v4' + apiPath, {
      headers: { 'X-Auth-Token': String(key || '') }
    });
    let body = null;
    try { body = await res.json(); } catch { /* ei JSON-vastaus */ }
    return { status: res.status, body };
  } catch {
    return { status: -1, body: null };
  }
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
