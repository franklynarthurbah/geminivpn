/**
 * GeminiVPN — Status Page
 * Shows: Engine status, server statuses, user payment confirmations, account timeline
 * Payment/account sections are ONLY shown to authenticated users
 */
import React, { useState, useEffect, useCallback } from 'react';
import { ArrowLeft, RefreshCw, Server, Shield, CreditCard, Clock, CheckCircle, XCircle, AlertTriangle, Zap, Globe, Activity } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { toast } from 'sonner';

const API_BASE = (window as any).GEMINI_API_URL ?? '/api/v1';

async function apiGet(endpoint: string, token?: string | null) {
  const res = await fetch(`${API_BASE}${endpoint}`, {
    headers: {
      'Content-Type': 'application/json',
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
  });
  const json = await res.json();
  return { ok: res.ok, data: json };
}

interface StatusPageProps { user: { email: string; name: string; subscriptionStatus?: string } | null; onBack: () => void; }

type EngineStatus = 'operational' | 'degraded' | 'down' | 'loading';
type ServerStatus = { id: string; name: string; country: string; city: string; loadPercentage: number; latencyMs: number; isActive?: boolean; isMaintenance?: boolean };
type Payment = { id: string; amount: number; currency: string; status: string; createdAt: string; provider?: string; providerPaymentId?: string; stripePaymentId?: string };

const StatusBadge = ({ status }: { status: EngineStatus | string }) => {
  const map: Record<string, { label: string; color: string; dot: string }> = {
    operational: { label: 'Operational',  color: 'text-emerald-400 bg-emerald-400/10 border-emerald-400/20', dot: 'bg-emerald-400' },
    degraded:    { label: 'Degraded',     color: 'text-yellow-400 bg-yellow-400/10 border-yellow-400/20',   dot: 'bg-yellow-400' },
    down:        { label: 'Disruption',   color: 'text-red-400    bg-red-400/10    border-red-400/20',       dot: 'bg-red-400' },
    loading:     { label: 'Checking…',   color: 'text-white/40  bg-white/5       border-white/10',          dot: 'bg-white/40 animate-pulse' },
    ACTIVE:      { label: 'Active',       color: 'text-emerald-400 bg-emerald-400/10 border-emerald-400/20', dot: 'bg-emerald-400' },
    TRIAL:       { label: 'Trial',        color: 'text-cyan bg-cyan/10 border-cyan/20',                      dot: 'bg-cyan animate-pulse' },
    EXPIRED:     { label: 'Expired',      color: 'text-red-400 bg-red-400/10 border-red-400/20',             dot: 'bg-red-400' },
    CANCELLED:   { label: 'Cancelled',    color: 'text-white/50 bg-white/5 border-white/10',                 dot: 'bg-white/40' },
    SUSPENDED:   { label: 'Suspended',    color: 'text-orange-400 bg-orange-400/10 border-orange-400/20',    dot: 'bg-orange-400' },
    PAID:        { label: 'Paid',         color: 'text-emerald-400 bg-emerald-400/10 border-emerald-400/20', dot: 'bg-emerald-400' },
    PENDING:     { label: 'Pending',      color: 'text-yellow-400 bg-yellow-400/10 border-yellow-400/20',    dot: 'bg-yellow-400 animate-pulse' },
    FAILED:      { label: 'Failed',       color: 'text-red-400 bg-red-400/10 border-red-400/20',             dot: 'bg-red-400' },
    REFUNDED:    { label: 'Refunded',     color: 'text-purple-400 bg-purple-400/10 border-purple-400/20',    dot: 'bg-purple-400' },
  };
  const s = map[status] ?? map['loading'];
  return (
    <span className={`inline-flex items-center gap-1.5 px-2.5 py-1 rounded-full border text-xs font-mono uppercase tracking-wider ${s.color}`}>
      <span className={`w-1.5 h-1.5 rounded-full ${s.dot}`} />
      {s.label}
    </span>
  );
};

const loadColor = (n: number) => n >= 80 ? 'bg-red-400' : n >= 60 ? 'bg-yellow-400' : 'bg-emerald-400';
const latColor  = (ms: number) => ms <= 15 ? 'text-emerald-400' : ms <= 30 ? 'text-yellow-400' : 'text-orange-400';

const fmtDate = (iso: string) => {
  const d = new Date(iso);
  return d.toLocaleDateString('en-GB', { day: '2-digit', month: 'short', year: 'numeric' }) + ' · ' +
         d.toLocaleTimeString('en-GB', { hour: '2-digit', minute: '2-digit' });
};

const fmtAmount = (cents: number, currency: string) =>
  new Intl.NumberFormat('en-US', { style: 'currency', currency: currency.toUpperCase() }).format(cents / 100);

export default function StatusPage({ user, onBack }: StatusPageProps) {
  const [engineStatus,   setEngineStatus]   = useState<EngineStatus>('loading');
  const [paymentStatus,  setPaymentStatus]  = useState<Record<string, boolean>>({});
  const [servers,        setServers]        = useState<ServerStatus[]>([]);
  const [payments,       setPayments]       = useState<Payment[]>([]);
  const [profile,        setProfile]        = useState<any>(null);
  const [lastRefresh,    setLastRefresh]    = useState<Date | null>(null);
  const [isRefreshing,   setIsRefreshing]   = useState(false);
  const [serversLoading, setServersLoading] = useState(true);

  const token = localStorage.getItem('gemini_access_token');

  const refresh = useCallback(async () => {
    setIsRefreshing(true);
    try {
      // 1. Engine health
      const health = await fetch('/health').then(r => r.json()).then(d => ({ ok: true, data: d })).catch(() => ({ ok: false, data: {} }));
      if (health.ok && health.data.status === 'healthy') {
        setEngineStatus('operational');
        setPaymentStatus(health.data.payments || {});
      } else {
        setEngineStatus('degraded');
      }
    } catch {
      setEngineStatus('down');
    }

    // 2. Servers
    setServersLoading(true);
    try {
      const srv = await apiGet('/servers');
      if (srv.ok && srv.data.data) setServers(srv.data.data);
    } catch { /* non-fatal */ }
    setServersLoading(false);

    // 3. User profile + payments (authenticated only)
    if (user && token) {
      try {
        const prof = await apiGet('/auth/profile', token);
        if (prof.ok && prof.data.data) {
          setProfile(prof.data.data);
          setPayments(prof.data.data.payments || []);
        }
      } catch { /* non-fatal */ }
    }

    setLastRefresh(new Date());
    setIsRefreshing(false);
  }, [user, token]);

  useEffect(() => { refresh(); }, [refresh]);

  // Build account timeline events from profile data
  const timelineEvents = React.useMemo(() => {
    if (!profile) return [];
    const events: { date: string; label: string; detail: string; type: 'success' | 'info' | 'warning' | 'error' }[] = [];
    if (profile.createdAt) events.push({ date: profile.createdAt, label: 'Account Created', detail: profile.email, type: 'success' });
    if (profile.emailVerified && profile.createdAt) events.push({ date: profile.createdAt, label: 'Email Verified', detail: 'Identity confirmed', type: 'info' });
    (profile.payments || []).slice().reverse().forEach((p: Payment) => {
      const provider = p.provider || (p.stripePaymentId ? 'Stripe' : 'Unknown');
      events.push({
        date:   p.createdAt,
        label:  `Payment ${p.status === 'PAID' ? 'Confirmed' : p.status}`,
        detail: `${fmtAmount(p.amount, p.currency)} via ${provider}`,
        type:   p.status === 'PAID' ? 'success' : p.status === 'FAILED' ? 'error' : 'warning',
      });
    });
    if (profile.subscriptionEndsAt) {
      const isExpired = new Date(profile.subscriptionEndsAt) < new Date();
      events.push({
        date:   profile.subscriptionEndsAt,
        label:  isExpired ? 'Subscription Expired' : 'Subscription Active Until',
        detail: new Date(profile.subscriptionEndsAt).toLocaleDateString('en-GB', { day:'2-digit', month:'long', year:'numeric' }),
        type:   isExpired ? 'warning' : 'success',
      });
    }
    return events.sort((a, b) => new Date(b.date).getTime() - new Date(a.date).getTime());
  }, [profile]);

  return (
    <div className="min-h-screen bg-navy-primary text-white">
      {/* Header */}
      <div className="sticky top-0 z-50 bg-navy-primary/90 backdrop-blur-md border-b border-white/5">
        <div className="max-w-5xl mx-auto px-4 sm:px-6 h-16 flex items-center gap-4">
          <button onClick={onBack} className="p-2 hover:bg-white/5 rounded-lg transition-colors" aria-label="Go back">
            <ArrowLeft size={20} className="text-white/70" />
          </button>
          <div className="flex items-center gap-3 flex-1">
            <Activity size={20} className="text-cyan" />
            <h1 className="font-orbitron font-bold tracking-wider text-sm sm:text-base">SYSTEM STATUS</h1>
          </div>
          <div className="flex items-center gap-3">
            {lastRefresh && <span className="hidden sm:block font-mono text-xs text-white/30">Updated {lastRefresh.toLocaleTimeString()}</span>}
            <button onClick={refresh} disabled={isRefreshing} className="p-2 hover:bg-white/5 rounded-lg transition-colors disabled:opacity-40" aria-label="Refresh">
              <RefreshCw size={16} className={`text-white/50 ${isRefreshing ? 'animate-spin' : ''}`} />
            </button>
          </div>
        </div>
      </div>

      <div className="max-w-5xl mx-auto px-4 sm:px-6 py-8 space-y-8">

        {/* Overall Status Banner */}
        <div className={`rounded-2xl border p-6 flex items-center gap-4 ${engineStatus === 'operational' ? 'bg-emerald-400/5 border-emerald-400/20' : engineStatus === 'degraded' ? 'bg-yellow-400/5 border-yellow-400/20' : 'bg-red-400/5 border-red-400/20'}`}>
          {engineStatus === 'operational' ? <CheckCircle size={32} className="text-emerald-400 flex-shrink-0" /> :
           engineStatus === 'degraded'    ? <AlertTriangle size={32} className="text-yellow-400 flex-shrink-0" /> :
           engineStatus === 'loading'     ? <RefreshCw size={32} className="text-white/40 animate-spin flex-shrink-0" /> :
                                            <XCircle size={32} className="text-red-400 flex-shrink-0" />}
          <div>
            <p className="font-orbitron font-bold text-lg">
              {engineStatus === 'operational' ? 'All Systems Operational' :
               engineStatus === 'degraded'    ? 'Partial Service Degradation' :
               engineStatus === 'loading'     ? 'Checking Systems…' :
                                                'Service Disruption Detected'}
            </p>
            <p className="text-sm text-white/50 mt-0.5 font-mono">geminivpn.zapto.org · as of {lastRefresh ? lastRefresh.toUTCString() : '—'}</p>
          </div>
        </div>

        {/* VPN Engine Status */}
        <section>
          <div className="flex items-center gap-2 mb-4">
            <Shield size={16} className="text-cyan" />
            <h2 className="font-mono text-xs uppercase tracking-[0.18em] text-white/50">VPN Engine</h2>
          </div>
          <div className="bg-navy-secondary rounded-2xl border border-white/10 divide-y divide-white/5">
            {[
              { label: 'GeminiVPN Core Engine',    desc: 'WireGuard® tunnel management', status: engineStatus },
              { label: 'Authentication Service',   desc: 'JWT + session management',     status: engineStatus },
              { label: 'API Gateway',              desc: 'REST API v1',                  status: engineStatus },
              { label: 'Database',                 desc: 'PostgreSQL — primary store',    status: engineStatus },
              { label: 'Self-Healing Monitor',     desc: 'Auto-reconnect & recovery',    status: engineStatus === 'operational' ? 'operational' : 'degraded' },
            ].map((row) => (
              <div key={row.label} className="flex items-center justify-between px-6 py-4">
                <div>
                  <p className="font-medium text-sm">{row.label}</p>
                  <p className="text-xs text-white/40 mt-0.5 font-mono">{row.desc}</p>
                </div>
                <StatusBadge status={row.status} />
              </div>
            ))}
          </div>
        </section>

        {/* Payment Engine */}
        <section>
          <div className="flex items-center gap-2 mb-4">
            <CreditCard size={16} className="text-cyan" />
            <h2 className="font-mono text-xs uppercase tracking-[0.18em] text-white/50">Payment Processors</h2>
          </div>
          <div className="bg-navy-secondary rounded-2xl border border-white/10 divide-y divide-white/5">
            {[
              { key: 'stripe',   label: 'Stripe',           desc: 'Card payments & subscriptions' },
              { key: 'square',   label: 'Square',           desc: 'Card & in-person payments' },
              { key: 'paddle',   label: 'Paddle',           desc: 'Subscription billing & tax' },
              { key: 'coinbase', label: 'Coinbase Commerce', desc: 'Cryptocurrency payments' },
            ].map((p) => (
              <div key={p.key} className="flex items-center justify-between px-6 py-4">
                <div>
                  <p className="font-medium text-sm">{p.label}</p>
                  <p className="text-xs text-white/40 mt-0.5 font-mono">{p.desc}</p>
                </div>
                <StatusBadge status={paymentStatus[p.key] ? 'operational' : engineStatus === 'loading' ? 'loading' : 'degraded'} />
              </div>
            ))}
          </div>
          {!user && (
            <p className="text-xs text-white/30 font-mono mt-3 px-1">
              Payment confirmation history is available to authenticated users only.
            </p>
          )}
        </section>

        {/* Server Engine Status */}
        <section>
          <div className="flex items-center gap-2 mb-4">
            <Server size={16} className="text-cyan" />
            <h2 className="font-mono text-xs uppercase tracking-[0.18em] text-white/50">Server Network</h2>
          </div>
          {serversLoading ? (
            <div className="bg-navy-secondary rounded-2xl border border-white/10 p-8 text-center">
              <RefreshCw size={24} className="text-white/30 animate-spin mx-auto" />
            </div>
          ) : servers.length === 0 ? (
            <div className="bg-navy-secondary rounded-2xl border border-white/10 p-8 text-center text-white/30 text-sm font-mono">
              Server status unavailable
            </div>
          ) : (
            <div className="bg-navy-secondary rounded-2xl border border-white/10 divide-y divide-white/5">
              {servers.map((s) => (
                <div key={s.id} className="flex items-center gap-4 px-6 py-4">
                  <Globe size={16} className="text-cyan/60 flex-shrink-0" />
                  <div className="flex-1 min-w-0">
                    <div className="flex items-center gap-2">
                      <p className="font-medium text-sm truncate">{s.name || `${s.city}, ${s.country}`}</p>
                    </div>
                    <div className="flex items-center gap-3 mt-1">
                      <span className={`font-mono text-xs ${latColor(s.latencyMs)}`}>{s.latencyMs} ms</span>
                      <div className="flex items-center gap-1.5">
                        <div className="w-20 h-1 bg-white/10 rounded-full overflow-hidden">
                          <div className={`h-full rounded-full transition-all ${loadColor(s.loadPercentage)}`} style={{ width: `${s.loadPercentage}%` }} />
                        </div>
                        <span className="font-mono text-xs text-white/30">{s.loadPercentage}%</span>
                      </div>
                    </div>
                  </div>
                  <StatusBadge status={s.isMaintenance ? 'degraded' : (s.isActive !== false) ? 'operational' : 'down'} />
                </div>
              ))}
            </div>
          )}
        </section>

        {/* Payment Confirmations — AUTHENTICATED ONLY */}
        {user && (
          <section>
            <div className="flex items-center gap-2 mb-4">
              <CreditCard size={16} className="text-cyan" />
              <h2 className="font-mono text-xs uppercase tracking-[0.18em] text-white/50">Your Payment Confirmations</h2>
            </div>
            {payments.length === 0 ? (
              <div className="bg-navy-secondary rounded-2xl border border-white/10 p-8 text-center">
                <CreditCard size={32} className="text-white/20 mx-auto mb-3" />
                <p className="text-sm text-white/40">No payment records found.</p>
              </div>
            ) : (
              <div className="bg-navy-secondary rounded-2xl border border-white/10 divide-y divide-white/5">
                {payments.map((p) => {
                  const provider = p.provider || (p.stripePaymentId ? 'Stripe' : 'System');
                  const paymentId = p.providerPaymentId || p.stripePaymentId || p.id;
                  return (
                    <div key={p.id} className="flex items-start gap-4 px-6 py-4">
                      <div className={`mt-0.5 w-8 h-8 rounded-full flex items-center justify-center flex-shrink-0 ${p.status === 'PAID' ? 'bg-emerald-400/10' : 'bg-red-400/10'}`}>
                        {p.status === 'PAID' ? <CheckCircle size={16} className="text-emerald-400" /> : <XCircle size={16} className="text-red-400" />}
                      </div>
                      <div className="flex-1 min-w-0">
                        <div className="flex items-center justify-between gap-2">
                          <p className="font-medium text-sm">{fmtAmount(p.amount, p.currency)}</p>
                          <StatusBadge status={p.status} />
                        </div>
                        <p className="text-xs text-white/40 font-mono mt-1">
                          {provider} · {paymentId.slice(0, 24)}{paymentId.length > 24 ? '…' : ''}
                        </p>
                        <p className="text-xs text-white/30 font-mono mt-0.5">{fmtDate(p.createdAt)}</p>
                      </div>
                    </div>
                  );
                })}
              </div>
            )}
          </section>
        )}

        {/* Account Validation Timeline — AUTHENTICATED ONLY */}
        {user && (
          <section>
            <div className="flex items-center gap-2 mb-4">
              <Clock size={16} className="text-cyan" />
              <h2 className="font-mono text-xs uppercase tracking-[0.18em] text-white/50">Account Validation Timeline</h2>
            </div>
            <div className="bg-navy-secondary rounded-2xl border border-white/10 p-6">
              {/* Subscription status header */}
              <div className="flex items-center justify-between mb-6 pb-4 border-b border-white/5">
                <div>
                  <p className="text-sm text-white/50 font-mono">Subscription Status</p>
                  <p className="font-orbitron font-bold mt-1">{profile?.email || user.email}</p>
                </div>
                <StatusBadge status={profile?.subscriptionStatus || user.subscriptionStatus || 'loading'} />
              </div>

              {/* Timeline */}
              {timelineEvents.length === 0 ? (
                <div className="text-center py-6">
                  <Clock size={32} className="text-white/20 mx-auto mb-3" />
                  <p className="text-sm text-white/40">Loading account history…</p>
                </div>
              ) : (
                <div className="relative">
                  <div className="absolute left-[19px] top-0 bottom-0 w-px bg-white/10" />
                  <div className="space-y-4">
                    {timelineEvents.map((ev, i) => {
                      const iconColor = ev.type === 'success' ? 'bg-emerald-400/20 text-emerald-400 border-emerald-400/30' :
                                        ev.type === 'error'   ? 'bg-red-400/20 text-red-400 border-red-400/30' :
                                        ev.type === 'warning' ? 'bg-yellow-400/20 text-yellow-400 border-yellow-400/30' :
                                                                'bg-cyan/20 text-cyan border-cyan/30';
                      return (
                        <div key={i} className="flex gap-4">
                          <div className={`relative z-10 w-10 h-10 rounded-full border flex items-center justify-center flex-shrink-0 ${iconColor}`}>
                            {ev.type === 'success' ? <CheckCircle size={16} /> :
                             ev.type === 'error'   ? <XCircle size={16} /> :
                             ev.type === 'warning' ? <AlertTriangle size={16} /> :
                                                     <Zap size={16} />}
                          </div>
                          <div className="flex-1 pb-4">
                            <p className="font-medium text-sm">{ev.label}</p>
                            <p className="text-xs text-white/40 mt-0.5">{ev.detail}</p>
                            <p className="text-xs text-white/20 font-mono mt-0.5">{fmtDate(ev.date)}</p>
                          </div>
                        </div>
                      );
                    })}
                  </div>
                </div>
              )}
            </div>
          </section>
        )}

        {!user && (
          <div className="bg-cyan/5 border border-cyan/20 rounded-2xl p-6 text-center">
            <Shield size={32} className="text-cyan/50 mx-auto mb-3" />
            <p className="font-semibold text-sm">Sign in to view your account details</p>
            <p className="text-xs text-white/40 mt-1">Payment confirmations and account timeline require authentication.</p>
          </div>
        )}
      </div>
    </div>
  );
}
