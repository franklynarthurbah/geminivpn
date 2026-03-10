/**
 * preload.js – GeminiVPN Desktop
 * Secure context-bridge between renderer (React) and main process.
 * All IPC is explicitly whitelisted here.
 */

'use strict';

const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('gemini', {

    // ── Auth ─────────────────────────────────────────────────────────────────
    auth: {
        saveTokens:  (tokens) => ipcRenderer.invoke('auth:saveTokens', tokens),
        getTokens:   ()        => ipcRenderer.invoke('auth:getTokens'),
        clearTokens: ()        => ipcRenderer.invoke('auth:clearTokens'),
    },

    // ── VPN ──────────────────────────────────────────────────────────────────
    vpn: {
        connect:    (args) => ipcRenderer.invoke('vpn:connect', args),
        disconnect: ()     => ipcRenderer.invoke('vpn:disconnect'),
        getState:   ()     => ipcRenderer.invoke('vpn:getState'),
    },

    // ── Settings ─────────────────────────────────────────────────────────────
    settings: {
        get:    (key)          => ipcRenderer.invoke('settings:get', key),
        set:    (key, value)   => ipcRenderer.invoke('settings:set', { key, value }),
        getAll: ()             => ipcRenderer.invoke('settings:getAll'),
    },

    // ── Config ───────────────────────────────────────────────────────────────
    config: {
        exportWireGuard: (args) => ipcRenderer.invoke('config:exportWireGuard', args),
    },

    // ── Window controls (custom title bar) ────────────────────────────────────
    window: {
        minimize: () => ipcRenderer.send('window:minimize'),
        maximize: () => ipcRenderer.send('window:maximize'),
        close:    () => ipcRenderer.send('window:close'),
    },

    // ── Updater ──────────────────────────────────────────────────────────────
    updater: {
        checkForUpdates: () => ipcRenderer.invoke('updater:checkForUpdates'),
        installUpdate:   () => ipcRenderer.invoke('updater:installUpdate'),
    },

    // ── Event listeners (main → renderer) ────────────────────────────────────
    on: (channel, callback) => {
        const ALLOWED_CHANNELS = [
            'vpn-state-changed',
            'kill-switch-activated',
            'auto-reconnect',
            'tray-connect-request',
            'update-available',
            'update-downloaded',
            'settings-changed',
        ];
        if (ALLOWED_CHANNELS.includes(channel)) {
            const subscription = (_event, ...args) => callback(...args);
            ipcRenderer.on(channel, subscription);
            return () => ipcRenderer.removeListener(channel, subscription);
        }
    },

    // ── Platform info ─────────────────────────────────────────────────────────
    platform: process.platform,
});
