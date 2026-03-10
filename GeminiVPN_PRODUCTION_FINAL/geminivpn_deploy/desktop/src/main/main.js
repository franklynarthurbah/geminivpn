/**
 * GeminiVPN Desktop – Main Process
 * Electron main.js: window, tray, IPC, WireGuard integration, auto-updater.
 */

'use strict';

const {
    app, BrowserWindow, Tray, Menu, ipcMain,
    nativeTheme, shell, dialog, nativeImage,
    powerMonitor, systemPreferences
} = require('electron');
const path          = require('path');
const { autoUpdater } = require('electron-updater');
const Store         = require('electron-store');
const keytar        = require('keytar');
const { execFile, exec } = require('child_process');
const { promisify } = require('util');

const execAsync = promisify(exec);

// ─── Constants ────────────────────────────────────────────────────────────────

const IS_DEV      = !app.isPackaged;
const KEYCHAIN_SVC = 'com.geminivpn.desktop';
const RENDERER_URL = IS_DEV ? 'http://localhost:3001' : `file://${path.join(__dirname, '../../dist/index.html')}`;

// ─── Persistent storage (encrypted) ──────────────────────────────────────────

const store = new Store({
    name:           'gemini-settings',
    encryptionKey:  'gemini-vpn-desktop-2026',   // obfuscated; production: use OS keychain
    defaults: {
        killSwitch:      false,
        autoConnect:     false,
        startOnBoot:     false,
        minimiseToTray:  true,
        selectedServerId: null,
        activeClientId:   null,
        windowBounds: { width: 900, height: 680 }
    }
});

// ─── Application state ────────────────────────────────────────────────────────

let mainWindow  = null;
let tray        = null;
let vpnState    = 'disconnected';   // 'disconnected' | 'connecting' | 'connected' | 'error'
let wgProcess   = null;             // WireGuard child process (wg-quick or wireguard.exe)

// ─── App init ─────────────────────────────────────────────────────────────────

app.whenReady().then(async () => {
    // Single instance lock
    if (!app.requestSingleInstanceLock()) {
        app.quit();
        return;
    }

    createMainWindow();
    createTray();
    registerIpcHandlers();
    setupAutoUpdater();
    setupPowerMonitor();

    app.on('activate', () => {
        if (BrowserWindow.getAllWindows().length === 0) createMainWindow();
    });
});

app.on('second-instance', () => {
    if (mainWindow) {
        if (mainWindow.isMinimized()) mainWindow.restore();
        mainWindow.focus();
    }
});

app.on('window-all-closed', () => {
    if (process.platform !== 'darwin') app.quit();
});

app.on('before-quit', async () => {
    await stopVpn();
});

// ─── Main Window ──────────────────────────────────────────────────────────────

function createMainWindow() {
    const { width, height } = store.get('windowBounds');

    mainWindow = new BrowserWindow({
        width,
        height,
        minWidth:  780,
        minHeight: 580,
        title:     'GeminiVPN',
        icon:      getAppIcon(),
        titleBarStyle: process.platform === 'darwin' ? 'hiddenInset' : 'default',
        webPreferences: {
            preload:          path.join(__dirname, 'preload.js'),
            contextIsolation: true,
            nodeIntegration:  false,
            sandbox:          true,
        },
        backgroundColor: '#070A12',
        show: false,   // show after ready-to-show
    });

    mainWindow.loadURL(RENDERER_URL);

    mainWindow.once('ready-to-show', () => {
        mainWindow.show();
        if (IS_DEV) mainWindow.webContents.openDevTools({ mode: 'detach' });
    });

    // Persist window size
    mainWindow.on('resize', () => {
        if (!mainWindow.isMaximized()) {
            store.set('windowBounds', mainWindow.getBounds());
        }
    });

    // Minimise to tray instead of closing
    mainWindow.on('close', (e) => {
        if (store.get('minimiseToTray') && tray) {
            e.preventDefault();
            mainWindow.hide();
        }
    });

    // Open external links in OS browser
    mainWindow.webContents.setWindowOpenHandler(({ url }) => {
        shell.openExternal(url);
        return { action: 'deny' };
    });
}

function getAppIcon() {
    switch (process.platform) {
        case 'win32':  return path.join(__dirname, '../../assets/icon.ico');
        case 'darwin': return path.join(__dirname, '../../assets/icon.icns');
        default:       return path.join(__dirname, '../../assets/icon.png');
    }
}

// ─── System Tray ──────────────────────────────────────────────────────────────

function createTray() {
    const iconPath  = path.join(__dirname, '../../assets/tray-icon.png');
    const trayImage = nativeImage.createFromPath(iconPath).resize({ width: 16, height: 16 });

    tray = new Tray(trayImage);
    tray.setToolTip('GeminiVPN');
    updateTrayMenu();

    tray.on('double-click', () => {
        mainWindow ? mainWindow.show() : createMainWindow();
    });
}

function updateTrayMenu() {
    const connected   = vpnState === 'connected';
    const connecting  = vpnState === 'connecting';

    const menu = Menu.buildFromTemplate([
        {
            label:   connected ? '● Connected' : '○ Disconnected',
            enabled: false
        },
        { type: 'separator' },
        {
            label:    connected ? 'Disconnect' : 'Connect',
            enabled:  !connecting,
            click:    connected ? () => stopVpn() : () => startVpnFromTray()
        },
        {
            label: 'Open GeminiVPN',
            click: () => { mainWindow ? mainWindow.show() : createMainWindow(); }
        },
        { type: 'separator' },
        {
            label: 'Kill Switch',
            type:  'checkbox',
            checked: store.get('killSwitch'),
            click: (item) => {
                store.set('killSwitch', item.checked);
                if (!item.checked) removeKillSwitchRules();
                sendToRenderer('settings-changed', { killSwitch: item.checked });
            }
        },
        { type: 'separator' },
        {
            label: 'Quit GeminiVPN',
            click: () => app.quit()
        }
    ]);

    tray.setContextMenu(menu);
    tray.setToolTip(connected ? 'GeminiVPN – Connected' : 'GeminiVPN – Disconnected');
}

// ─── IPC Handlers ─────────────────────────────────────────────────────────────

function registerIpcHandlers() {

    // ── Auth ────────────────────────────────────────────────────────────────

    ipcMain.handle('auth:saveTokens', async (_, { accessToken, refreshToken }) => {
        await keytar.setPassword(KEYCHAIN_SVC, 'access_token',  accessToken);
        await keytar.setPassword(KEYCHAIN_SVC, 'refresh_token', refreshToken);
    });

    ipcMain.handle('auth:getTokens', async () => {
        const accessToken  = await keytar.getPassword(KEYCHAIN_SVC, 'access_token');
        const refreshToken = await keytar.getPassword(KEYCHAIN_SVC, 'refresh_token');
        return { accessToken, refreshToken };
    });

    ipcMain.handle('auth:clearTokens', async () => {
        await keytar.deletePassword(KEYCHAIN_SVC, 'access_token');
        await keytar.deletePassword(KEYCHAIN_SVC, 'refresh_token');
    });

    // ── VPN ─────────────────────────────────────────────────────────────────

    ipcMain.handle('vpn:connect', async (_, { configFile, clientId, serverId }) => {
        return await startVpn(configFile, clientId, serverId);
    });

    ipcMain.handle('vpn:disconnect', async () => {
        return await stopVpn();
    });

    ipcMain.handle('vpn:getState', () => vpnState);

    // ── Settings ─────────────────────────────────────────────────────────────

    ipcMain.handle('settings:get', (_, key) => store.get(key));
    ipcMain.handle('settings:set', (_, { key, value }) => {
        store.set(key, value);
        if (key === 'startOnBoot') {
            app.setLoginItemSettings({ openAtLogin: value, openAsHidden: true });
        }
        if (key === 'killSwitch' && !value) {
            removeKillSwitchRules();
        }
    });
    ipcMain.handle('settings:getAll', () => store.store);

    // ── Config file ──────────────────────────────────────────────────────────

    ipcMain.handle('config:exportWireGuard', async (_, { configContent, filename }) => {
        const { filePath } = await dialog.showSaveDialog(mainWindow, {
            title:       'Export WireGuard Config',
            defaultPath: filename || 'geminivpn.conf',
            filters: [{ name: 'WireGuard Config', extensions: ['conf'] }]
        });
        if (filePath) {
            const fs = require('fs').promises;
            await fs.writeFile(filePath, configContent, 'utf8');
            return { saved: true, path: filePath };
        }
        return { saved: false };
    });

    // ── Window ───────────────────────────────────────────────────────────────

    ipcMain.on('window:minimize', () => mainWindow?.minimize());
    ipcMain.on('window:maximize', () => {
        mainWindow?.isMaximized() ? mainWindow.unmaximize() : mainWindow?.maximize();
    });
    ipcMain.on('window:close', () => {
        store.get('minimiseToTray') ? mainWindow?.hide() : app.quit();
    });

    // ── Updates ──────────────────────────────────────────────────────────────

    ipcMain.handle('updater:checkForUpdates', () => autoUpdater.checkForUpdatesAndNotify());
    ipcMain.handle('updater:installUpdate', () => autoUpdater.quitAndInstall());
}

// ─── VPN Control ──────────────────────────────────────────────────────────────

async function startVpn(configFile, clientId, serverId) {
    if (vpnState === 'connected' || vpnState === 'connecting') {
        return { success: false, message: 'Already connected or connecting' };
    }

    setVpnState('connecting');

    try {
        // Write config to a temp file (production: use secure temp dir)
        const os   = require('os');
        const fs   = require('fs').promises;
        const tmpConf = path.join(os.tmpdir(), `geminivpn-${Date.now()}.conf`);
        await fs.writeFile(tmpConf, configFile, { mode: 0o600 });

        // Store config path for cleanup
        store.set('_tmpConf', tmpConf);
        store.set('activeClientId', clientId);
        store.set('activeServerId', serverId);

        // Platform-specific WireGuard start
        if (process.platform === 'win32') {
            await startWireGuardWindows(tmpConf);
        } else if (process.platform === 'darwin') {
            await startWireGuardMac(tmpConf);
        } else {
            await startWireGuardLinux(tmpConf);
        }

        setVpnState('connected');
        return { success: true };

    } catch (error) {
        setVpnState('error');
        if (store.get('killSwitch')) applyKillSwitchRules();
        return { success: false, message: error.message };
    }
}

async function stopVpn() {
    if (vpnState === 'disconnected') return { success: true };

    try {
        if (process.platform === 'win32') {
            await execAsync('Stop-Service -Name WireGuardTunnel$GeminiVPN -Force', { shell: 'powershell.exe' });
        } else {
            const tmpConf = store.get('_tmpConf');
            if (tmpConf) {
                await execAsync(`wg-quick down "${tmpConf}"`);
                require('fs').unlink(tmpConf, () => {});
                store.delete('_tmpConf');
            }
        }

        removeKillSwitchRules();
        setVpnState('disconnected');
        return { success: true };

    } catch (error) {
        setVpnState('error');
        if (store.get('killSwitch')) applyKillSwitchRules();
        return { success: false, message: error.message };
    }
}

async function startWireGuardWindows(configPath) {
    // wireguard.exe /installtunnelservice <config>
    await execAsync(
        `"${path.join(process.resourcesPath || '.', 'wireguard', 'wireguard.exe')}" /installtunnelservice "${configPath}"`,
        { windowsHide: true }
    );
}

async function startWireGuardMac(configPath) {
    await execAsync(`wg-quick up "${configPath}"`);
}

async function startWireGuardLinux(configPath) {
    await execAsync(`wg-quick up "${configPath}"`);
}

// ─── Kill Switch (firewall rules) ─────────────────────────────────────────────

async function applyKillSwitchRules() {
    try {
        if (process.platform === 'win32') {
            await execAsync(
                'New-NetFirewallRule -DisplayName "GeminiVPN-KillSwitch" -Direction Outbound -Action Block -Enabled True -Profile Any',
                { shell: 'powershell.exe' }
            );
        } else if (process.platform === 'darwin') {
            await execAsync('pfctl -e -f /etc/pf.conf');
        } else {
            await execAsync('iptables -I OUTPUT -j DROP -m comment --comment "geminivpn-killswitch"');
            await execAsync('ip6tables -I OUTPUT -j DROP -m comment --comment "geminivpn-killswitch"');
        }
        sendToRenderer('kill-switch-activated', {});
    } catch (err) {
        console.error('Kill switch error:', err.message);
    }
}

async function removeKillSwitchRules() {
    try {
        if (process.platform === 'win32') {
            await execAsync(
                'Remove-NetFirewallRule -DisplayName "GeminiVPN-KillSwitch" -ErrorAction SilentlyContinue',
                { shell: 'powershell.exe' }
            );
        } else if (process.platform === 'linux') {
            await execAsync('iptables -D OUTPUT -j DROP -m comment --comment "geminivpn-killswitch" 2>/dev/null; true');
            await execAsync('ip6tables -D OUTPUT -j DROP -m comment --comment "geminivpn-killswitch" 2>/dev/null; true');
        }
    } catch (_) { /* best-effort cleanup */ }
}

// ─── Power Monitor ─────────────────────────────────────────────────────────────

function setupPowerMonitor() {
    powerMonitor.on('suspend', async () => {
        if (vpnState === 'connected') await stopVpn();
    });

    powerMonitor.on('resume', () => {
        if (store.get('autoConnect')) {
            sendToRenderer('auto-reconnect', {});
        }
    });
}

// ─── Auto Updater ─────────────────────────────────────────────────────────────

function setupAutoUpdater() {
    if (IS_DEV) return;

    autoUpdater.autoDownload  = true;
    autoUpdater.autoInstallOnAppQuit = true;

    autoUpdater.on('update-available',  (info) => sendToRenderer('update-available',  info));
    autoUpdater.on('update-downloaded', (info) => sendToRenderer('update-downloaded', info));
    autoUpdater.on('error',             (err)  => console.error('Updater error:', err));

    // Check on startup and every 4 hours
    autoUpdater.checkForUpdatesAndNotify();
    setInterval(() => autoUpdater.checkForUpdatesAndNotify(), 4 * 60 * 60 * 1000);
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

function setVpnState(state) {
    vpnState = state;
    sendToRenderer('vpn-state-changed', { state });
    updateTrayMenu();
}

function sendToRenderer(channel, data) {
    if (mainWindow && !mainWindow.isDestroyed()) {
        mainWindow.webContents.send(channel, data);
    }
}

async function startVpnFromTray() {
    const activeClientId = store.get('activeClientId');
    const activeServerId = store.get('activeServerId');
    if (activeClientId && activeServerId) {
        sendToRenderer('tray-connect-request', { clientId: activeClientId, serverId: activeServerId });
    } else {
        mainWindow ? mainWindow.show() : createMainWindow();
    }
}
