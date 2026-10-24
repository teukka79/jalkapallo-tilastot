'use strict';
const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('api', {
  loadStore: () => ipcRenderer.invoke('store:load'),
  saveStore: (patch) => ipcRenderer.invoke('store:save', patch),
  setIcon: (id) => ipcRenderer.invoke('icon:set', id),
  footballData: (apiPath, key) => ipcRenderer.invoke('fd:get', apiPath, key),
  espn: (req) => ipcRenderer.invoke('espn:get', req),
  odds: (sport, key, force) => ipcRenderer.invoke('odds:get', sport, key, !!force),
  savePlayers: (players) => ipcRenderer.invoke('players:save', players),
  clearPlayers: () => ipcRenderer.invoke('players:clear'),
  importPlayers: () => ipcRenderer.invoke('players:import'),
  exportPlayers: (players) => ipcRenderer.invoke('players:export', players)
});
