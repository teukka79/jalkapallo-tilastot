'use strict';
const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('api', {
  loadStore: () => ipcRenderer.invoke('store:load'),
  saveStore: (patch) => ipcRenderer.invoke('store:save', patch),
  crest: (url) => ipcRenderer.invoke('crest:get', url),
  openLink: (url) => ipcRenderer.invoke('link:open', url),
  setIcon: (id) => ipcRenderer.invoke('icon:set', id),
  footballData: (apiPath, key) => ipcRenderer.invoke('fd:get', apiPath, key),
  espn: (req) => ipcRenderer.invoke('espn:get', req),
  odds: (sport, key, force) => ipcRenderer.invoke('odds:get', sport, key, !!force),
  savePlayers: (players, kind) => ipcRenderer.invoke('players:save', players, kind),
  playerMatches: () => ipcRenderer.invoke('matches:get'),
  playerShots: (id) => ipcRenderer.invoke('shots:get', id),
  fetchPlayers: () => ipcRenderer.invoke('players:fetch'),
  onPlayersProgress: (cb) => ipcRenderer.on('players:progress', (_e, p) => cb(p)),
  clearPlayers: () => ipcRenderer.invoke('players:clear'),
  importPlayers: () => ipcRenderer.invoke('players:import'),
  exportPlayers: (players) => ipcRenderer.invoke('players:export', players)
});
