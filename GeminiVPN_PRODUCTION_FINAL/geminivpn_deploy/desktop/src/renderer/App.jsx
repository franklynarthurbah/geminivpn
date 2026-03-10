/**
 * App.jsx – GeminiVPN Desktop Renderer
 * Full React UI for the Electron desktop client.
 */

import React, { useState, useEffect, useCallback } from 'react';

// ─── API Service (renderer-side) ──────────────────────────────────────────────

const API_BASE = import.meta.env.DEV
    ? 'http://localhost:5000/v1'
    : 'https://geminivpn.zapto.org/api/v1';

async function apiRequest(method, path, body = null, retry = true) {
    const { accessToken } = await window.gemini.auth.getTokens();

    const res = await fetch(`${API_BASE}/${path}`, {
        method,
        headers: {
            'Content-Type': 'application/json',
            ...(accessToken ? { Authorization: `Bearer ${accessToken}` } : {}),
        },
        body: body ? JSON.stringify(body) : undefined,
    });

    if (res.status === 401 && retry) {
        // Refresh token
        const { refreshToken } = await window.gemini.auth.getTokens();
        const refreshRes = await fetch(`${API_BASE}/auth/refresh`, {
            method:  'POST',
            headers: { 'Content-Type': 'application/json' },
            body:    JSON.stringify({ refreshToken }),
        });
        if (refreshRes.ok) {
            const data = await refreshRes.json();
            await window.gemini.auth.saveTokens(data.data.tokens);
            return apiRequest(method, path, body, false);
        }
        await window.gemini.auth.clearTokens();
        window.location.reload();
    }

    return res.json();
}

// ─── Main App ────────────────────────────────────────────────────────────────

export default function App() {
    const [screen,      setScreen]      = useState('loading');  // loading | auth | dashboard
    const [vpnState,    setVpnState]    = useState('disconnected');
    const [servers,     setServers]     = useState([]);
    const [clients,     setClients]     = useState([]);
    const [selectedSrv, setSelectedSrv] = useState(null);
    const [activeClient,setActiveClient]= useState(null);
    const [user,        setUser]        = useState(null);
    const [killSwitch,  setKillSwitchState] = useState(false);
    const [notification,setNotification]= useState(null);
    const [sidebarTab,  setSidebarTab]  = useState('home');

    // ── Init ────────────────────────────────────────────────────────────────

    useEffect(() => {
        (async () => {
            const { accessToken } = await window.gemini.auth.getTokens();
            if (accessToken) {
                await loadData();
                setScreen('dashboard');
            } else {
                setScreen('auth');
            }

            const ks = await window.gemini.settings.get('killSwitch');
            setKillSwitchState(!!ks);
        })();

        // IPC event listeners
        const unsubs = [
            window.gemini.on('vpn-state-changed',    ({ state }) => setVpnState(state)),
            window.gemini.on('kill-switch-activated', () => notify('Kill switch activated – internet blocked', 'warning')),
            window.gemini.on('auto-reconnect',        () => handleConnect()),
            window.gemini.on('update-available',      (info) => notify(`Update ${info.version} available`, 'info')),
            window.gemini.on('update-downloaded',     () => notify('Update ready – restart to install', 'success')),
        ];
        return () => unsubs.forEach(u => u && u());
    }, []);

    async function loadData() {
        const [profileRes, serversRes, clientsRes] = await Promise.all([
            apiRequest('GET', 'auth/profile'),
            apiRequest('GET', 'servers'),
            apiRequest('GET', 'vpn/clients'),
        ]);

        if (profileRes.success) setUser(profileRes.data);
        if (serversRes.success) {
            const active = serversRes.data.filter(s => s.isActive);
            setServers(active);
            if (!selectedSrv) setSelectedSrv(active[0] || null);
        }
        if (clientsRes.success) {
            setClients(clientsRes.data);
            setActiveClient(clientsRes.data.find(c => c.isConnected) || clientsRes.data[0] || null);
        }
    }

    // ── VPN Connect / Disconnect ─────────────────────────────────────────────

    async function handleConnect() {
        if (vpnState === 'connected') {
            await handleDisconnect();
            return;
        }

        setVpnState('connecting');

        try {
            let client = activeClient;

            if (!client && selectedSrv) {
                const res = await apiRequest('POST', 'vpn/clients', {
                    clientName: `${window.gemini.platform} Desktop`,
                    serverId:   selectedSrv.id,
                });
                if (res.success) {
                    client = res.data;
                    setClients(prev => [...prev, client]);
                    setActiveClient(client);
                } else {
                    throw new Error(res.message);
                }
            }

            if (!client?.configFile) throw new Error('No VPN config available');

            const result = await window.gemini.vpn.connect({
                configFile: client.configFile,
                clientId:   client.id,
                serverId:   selectedSrv?.id,
            });

            if (!result.success) throw new Error(result.message);

            // Sync with backend
            await apiRequest('POST', `vpn/clients/${client.id}/connect`);
            notify('Connected to ' + (selectedSrv?.name || 'VPN'), 'success');

        } catch (err) {
            setVpnState('error');
            notify(err.message, 'error');
        }
    }

    async function handleDisconnect() {
        setVpnState('disconnecting');
        try {
            await window.gemini.vpn.disconnect();
            if (activeClient) {
                await apiRequest('POST', `vpn/clients/${activeClient.id}/disconnect`);
            }
            notify('Disconnected', 'info');
        } catch (err) {
            setVpnState('error');
            notify(err.message, 'error');
        }
    }

    // ── Auth ────────────────────────────────────────────────────────────────

    async function handleLoginSuccess(tokens, userData) {
        await window.gemini.auth.saveTokens(tokens);
        setUser(userData);
        await loadData();
        setScreen('dashboard');
    }

    async function handleLogout() {
        await apiRequest('POST', 'auth/logout');
        await window.gemini.auth.clearTokens();
        setUser(null);
        setScreen('auth');
    }

    // ── Kill Switch toggle ───────────────────────────────────────────────────

    async function toggleKillSwitch() {
        const newVal = !killSwitch;
        setKillSwitchState(newVal);
        await window.gemini.settings.set('killSwitch', newVal);
    }

    // ── Helpers ─────────────────────────────────────────────────────────────

    function notify(message, type = 'info') {
        setNotification({ message, type });
        setTimeout(() => setNotification(null), 4000);
    }

    // ── Render ────────────────────────────────────────────────────────────────

    if (screen === 'loading') return <SplashScreen />;
    if (screen === 'auth')    return <AuthScreen onSuccess={handleLoginSuccess} />;

    return (
        <div className="app-shell">
            {/* Custom title bar */}
            <TitleBar />

            <div className="layout">
                {/* Sidebar */}
                <Sidebar tab={sidebarTab} onTabChange={setSidebarTab} user={user} onLogout={handleLogout} />

                {/* Main content */}
                <main className="content">
                    {sidebarTab === 'home'     && (
                        <HomePanel
                            vpnState={vpnState}
                            selectedServer={selectedSrv}
                            servers={servers}
                            activeClient={activeClient}
                            killSwitch={killSwitch}
                            onConnect={handleConnect}
                            onServerChange={setSelectedSrv}
                            onKillSwitchToggle={toggleKillSwitch}
                        />
                    )}
                    {sidebarTab === 'servers'  && <ServersPanel servers={servers} selected={selectedSrv} onSelect={setSelectedSrv} />}
                    {sidebarTab === 'devices'  && <DevicesPanel clients={clients} onRefresh={loadData} />}
                    {sidebarTab === 'settings' && <SettingsPanel onRefresh={loadData} />}
                    {sidebarTab === 'account'  && <AccountPanel user={user} onLogout={handleLogout} />}
                </main>
            </div>

            {/* Toast notification */}
            {notification && <Toast {...notification} />}
        </div>
    );
}

// ─── Sub-components ───────────────────────────────────────────────────────────

function TitleBar() {
    const isMac = window.gemini.platform === 'darwin';
    return (
        <div className="titlebar" style={{ WebkitAppRegion: 'drag' }}>
            {!isMac && (
                <div className="titlebar-controls" style={{ WebkitAppRegion: 'no-drag' }}>
                    <button onClick={() => window.gemini.window.minimize()}>─</button>
                    <button onClick={() => window.gemini.window.maximize()}>□</button>
                    <button onClick={() => window.gemini.window.close()} className="close">✕</button>
                </div>
            )}
            <span className="titlebar-title">GeminiVPN</span>
        </div>
    );
}

function Sidebar({ tab, onTabChange, user, onLogout }) {
    const items = [
        { id: 'home',     icon: '🛡️', label: 'Home'     },
        { id: 'servers',  icon: '🌐', label: 'Servers'  },
        { id: 'devices',  icon: '💻', label: 'Devices'  },
        { id: 'settings', icon: '⚙️', label: 'Settings' },
        { id: 'account',  icon: '👤', label: 'Account'  },
    ];

    return (
        <aside className="sidebar">
            <div className="sidebar-logo">
                <span className="logo-gem">◆</span>
                <span className="logo-text">GeminiVPN</span>
            </div>
            <nav>
                {items.map(item => (
                    <button
                        key={item.id}
                        className={`nav-item ${tab === item.id ? 'active' : ''}`}
                        onClick={() => onTabChange(item.id)}
                    >
                        <span className="nav-icon">{item.icon}</span>
                        <span className="nav-label">{item.label}</span>
                    </button>
                ))}
            </nav>
            <div className="sidebar-footer">
                {user && <span className="user-email">{user.email}</span>}
            </div>
        </aside>
    );
}

function HomePanel({ vpnState, selectedServer, servers, activeClient, killSwitch, onConnect, onServerChange, onKillSwitchToggle }) {
    const isConnected  = vpnState === 'connected';
    const isConnecting = vpnState === 'connecting' || vpnState === 'disconnecting';

    const stateColors = {
        connected:    '#00e676',
        connecting:   '#ffd740',
        disconnecting:'#ffd740',
        error:        '#ff5252',
        disconnected: '#546e7a',
    };

    return (
        <div className="home-panel">
            {/* Connection ring */}
            <div className="connection-ring" style={{ '--color': stateColors[vpnState] || '#546e7a' }}>
                <div className="ring-inner">
                    <span className="ring-icon">{isConnected ? '🛡️' : '🔓'}</span>
                    <span className="ring-status">{
                        isConnected ? 'Protected' :
                        vpnState === 'connecting' ? 'Connecting…' :
                        vpnState === 'error' ? 'Error' : 'Unprotected'
                    }</span>
                    {activeClient?.assignedIp && isConnected && (
                        <span className="ring-ip">{activeClient.assignedIp}</span>
                    )}
                </div>
            </div>

            {/* Server selector */}
            <div className="server-selector">
                <label>Server</label>
                <select value={selectedServer?.id || ''} onChange={e => onServerChange(servers.find(s => s.id === e.target.value))}>
                    {servers.map(s => (
                        <option key={s.id} value={s.id}>
                            {s.name} — {s.city} ({s.latencyMs}ms)
                        </option>
                    ))}
                </select>
            </div>

            {/* Connect button */}
            <button
                className={`connect-btn ${isConnected ? 'disconnect' : 'connect'}`}
                onClick={onConnect}
                disabled={isConnecting}
            >
                {isConnecting ? '…' : isConnected ? 'Disconnect' : 'Connect'}
            </button>

            {/* Kill switch */}
            <div className="kill-switch-row">
                <div>
                    <div className="ks-title">Kill Switch</div>
                    <div className="ks-sub">Block internet if VPN drops</div>
                </div>
                <div
                    className={`toggle ${killSwitch ? 'on' : 'off'}`}
                    onClick={onKillSwitchToggle}
                />
            </div>
        </div>
    );
}

function ServersPanel({ servers, selected, onSelect }) {
    const [search, setSearch] = useState('');
    const filtered = servers.filter(s =>
        s.name.toLowerCase().includes(search.toLowerCase()) ||
        s.city.toLowerCase().includes(search.toLowerCase()) ||
        s.country.toLowerCase().includes(search.toLowerCase())
    );

    return (
        <div className="servers-panel">
            <h2>Servers</h2>
            <input className="search" placeholder="Search servers…" value={search} onChange={e => setSearch(e.target.value)} />
            <div className="server-list">
                {filtered.map(server => (
                    <div
                        key={server.id}
                        className={`server-item ${selected?.id === server.id ? 'selected' : ''}`}
                        onClick={() => onSelect(server)}
                    >
                        <div className="srv-info">
                            <span className="srv-name">{server.name}</span>
                            <span className="srv-location">{server.city}, {server.country}</span>
                        </div>
                        <div className="srv-stats">
                            <span className="latency">{server.latencyMs}ms</span>
                            <span className={`load load-${server.loadPercentage < 30 ? 'low' : server.loadPercentage < 70 ? 'med' : 'high'}`}>
                                {server.loadPercentage}%
                            </span>
                        </div>
                    </div>
                ))}
            </div>
        </div>
    );
}

function DevicesPanel({ clients, onRefresh }) {
    async function exportConfig(client) {
        if (!client.configFile) return;
        await window.gemini.config.exportWireGuard({
            configContent: client.configFile,
            filename: `geminivpn-${client.clientName.replace(/\s+/g, '-')}.conf`
        });
    }

    return (
        <div className="devices-panel">
            <h2>Devices <button onClick={onRefresh} className="refresh-btn">↻</button></h2>
            {clients.length === 0 ? (
                <p className="empty">No devices yet. Connect to create one.</p>
            ) : (
                <div className="device-list">
                    {clients.map(c => (
                        <div key={c.id} className="device-item">
                            <div className="dev-icon">💻</div>
                            <div className="dev-info">
                                <span className="dev-name">{c.clientName}</span>
                                <span className="dev-ip">{c.assignedIp}</span>
                            </div>
                            <div className="dev-actions">
                                <span className={`status-dot ${c.isConnected ? 'on' : 'off'}`} />
                                <button onClick={() => exportConfig(c)} className="export-btn">Export</button>
                            </div>
                        </div>
                    ))}
                </div>
            )}
        </div>
    );
}

function SettingsPanel() {
    const [settings, setSettings] = useState({});

    useEffect(() => {
        window.gemini.settings.getAll().then(setSettings);
    }, []);

    async function toggle(key) {
        const newVal = !settings[key];
        await window.gemini.settings.set(key, newVal);
        setSettings(prev => ({ ...prev, [key]: newVal }));
    }

    return (
        <div className="settings-panel">
            <h2>Settings</h2>
            {[
                { key: 'killSwitch',     label: 'Kill Switch',      sub: 'Block internet if VPN disconnects' },
                { key: 'autoConnect',    label: 'Auto-Connect',     sub: 'Connect on app startup' },
                { key: 'startOnBoot',    label: 'Launch at Boot',   sub: 'Start GeminiVPN when computer starts' },
                { key: 'minimiseToTray', label: 'Minimise to Tray', sub: 'Keep running in system tray when closed' },
            ].map(item => (
                <div key={item.key} className="setting-row">
                    <div>
                        <div className="setting-label">{item.label}</div>
                        <div className="setting-sub">{item.sub}</div>
                    </div>
                    <div
                        className={`toggle ${settings[item.key] ? 'on' : 'off'}`}
                        onClick={() => toggle(item.key)}
                    />
                </div>
            ))}
            <button className="btn-secondary mt" onClick={() => window.gemini.updater.checkForUpdates()}>
                Check for Updates
            </button>
        </div>
    );
}

function AccountPanel({ user, onLogout }) {
    if (!user) return null;
    const isActive = ['active', 'trial'].includes(user.subscriptionStatus);

    return (
        <div className="account-panel">
            <h2>Account</h2>
            <div className="account-card">
                <div className="acc-avatar">{(user.name || user.email)[0].toUpperCase()}</div>
                <div className="acc-info">
                    <div className="acc-name">{user.name || '—'}</div>
                    <div className="acc-email">{user.email}</div>
                    <span className={`sub-badge ${isActive ? 'active' : 'expired'}`}>
                        {user.subscriptionStatus?.toUpperCase()}
                    </span>
                </div>
            </div>
            {!isActive && (
                <a href="https://geminivpn.com/plans" target="_blank" className="btn-primary">
                    Upgrade Plan
                </a>
            )}
            <button className="btn-danger" onClick={onLogout}>Sign Out</button>
        </div>
    );
}

function AuthScreen({ onSuccess }) {
    const [mode, setMode]       = useState('login');
    const [email, setEmail]     = useState('');
    const [password, setPass]   = useState('');
    const [name, setName]       = useState('');
    const [error, setError]     = useState('');
    const [loading, setLoading] = useState(false);

    async function submit(e) {
        e.preventDefault();
        setLoading(true);
        setError('');
        try {
            const endpoint = mode === 'login' ? 'auth/login' : 'auth/register';
            const body     = mode === 'login' ? { email, password } : { email, password, name };
            const res      = await fetch(`${API_BASE}/${endpoint}`, {
                method:  'POST',
                headers: { 'Content-Type': 'application/json' },
                body:    JSON.stringify(body),
            });
            const data = await res.json();
            if (data.success) {
                onSuccess(data.data.tokens, data.data.user);
            } else {
                setError(data.message || 'Authentication failed');
            }
        } catch {
            setError('Network error. Check your connection.');
        }
        setLoading(false);
    }

    return (
        <div className="auth-screen">
            <div className="auth-card">
                <div className="auth-logo">◆ GeminiVPN</div>
                <h2>{mode === 'login' ? 'Sign In' : 'Create Account'}</h2>
                <form onSubmit={submit}>
                    {mode === 'register' && (
                        <input placeholder="Full Name" value={name} onChange={e => setName(e.target.value)} required />
                    )}
                    <input type="email" placeholder="Email" value={email} onChange={e => setEmail(e.target.value)} required />
                    <input type="password" placeholder="Password" value={password} onChange={e => setPass(e.target.value)} required />
                    {error && <div className="auth-error">{error}</div>}
                    <button type="submit" className="btn-primary" disabled={loading}>
                        {loading ? '…' : mode === 'login' ? 'Sign In' : 'Create Account'}
                    </button>
                </form>
                <button className="auth-toggle" onClick={() => setMode(mode === 'login' ? 'register' : 'login')}>
                    {mode === 'login' ? "Don't have an account? Register" : 'Already have an account? Sign In'}
                </button>
            </div>
        </div>
    );
}

function SplashScreen() {
    return (
        <div className="splash">
            <span className="splash-logo">◆</span>
            <span className="splash-text">GeminiVPN</span>
        </div>
    );
}

function Toast({ message, type }) {
    const colours = { success: '#00e676', error: '#ff5252', warning: '#ffd740', info: '#40c4ff' };
    return (
        <div className="toast" style={{ borderLeft: `4px solid ${colours[type] || '#40c4ff'}` }}>
            {message}
        </div>
    );
}
