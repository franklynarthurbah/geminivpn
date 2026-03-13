/**
 * GeminiVPN — Transparency Report
 */
import React from 'react';
import { ArrowLeft, Eye, ShieldOff, AlertTriangle, CheckCircle, Lock } from 'lucide-react';

interface TransparencyReportProps { onBack: () => void; }

export default function TransparencyReport({ onBack }: TransparencyReportProps) {
  return (
    <div className="min-h-screen bg-navy-primary text-white">
      {/* Header */}
      <div className="sticky top-0 z-50 bg-navy-primary/90 backdrop-blur-md border-b border-white/5">
        <div className="max-w-4xl mx-auto px-4 sm:px-6 h-16 flex items-center gap-4">
          <button onClick={onBack} className="p-2 hover:bg-white/5 rounded-lg transition-colors" aria-label="Go back">
            <ArrowLeft size={20} className="text-white/70" />
          </button>
          <div className="flex items-center gap-3">
            <Eye size={20} className="text-cyan" />
            <h1 className="font-orbitron font-bold tracking-wider text-sm sm:text-base">TRANSPARENCY REPORT</h1>
          </div>
          <span className="ml-auto font-mono text-xs text-white/30">2026 Annual</span>
        </div>
      </div>

      <div className="max-w-4xl mx-auto px-4 sm:px-6 py-10">

        {/* Hero */}
        <div className="mb-12 text-center">
          <h2 className="font-orbitron text-3xl sm:text-4xl font-bold mb-4">Radical Transparency</h2>
          <p className="text-white/55 text-sm max-w-xl mx-auto leading-relaxed">
            Trust is built through openness. This report details every government request, legal demand,
            and data disclosure affecting our users — published annually, with zero omissions.
          </p>
        </div>

        {/* Warrant canary */}
        <div className="mb-10 p-6 bg-emerald-400/5 border border-emerald-400/20 rounded-2xl flex items-start gap-4">
          <div className="w-10 h-10 rounded-full bg-emerald-400/15 flex items-center justify-center flex-shrink-0">
            <CheckCircle size={20} className="text-emerald-400" />
          </div>
          <div>
            <p className="font-orbitron font-bold text-emerald-400 mb-1">Warrant Canary — Active</p>
            <p className="text-sm text-white/65 leading-relaxed">
              As of 1 January 2026, GeminiVPN has <strong className="text-white">not</strong> received any
              National Security Letters, FISA court orders, gag orders, or any other classified government
              requests that would prevent us from disclosing legal demands. If this canary is ever removed
              or not updated, it should be interpreted as a signal that our legal situation has changed.
            </p>
            <p className="font-mono text-xs text-white/30 mt-2">Next update: 1 January 2027</p>
          </div>
        </div>

        {/* Stats grid */}
        <div className="grid grid-cols-2 sm:grid-cols-4 gap-4 mb-12">
          {[
            { value: '0',  label: 'User Logs Disclosed',      sub: 'because none exist',       color: 'text-emerald-400' },
            { value: '0',  label: 'Law Enforcement Requests', sub: '2025 — 2026',               color: 'text-emerald-400' },
            { value: '0',  label: 'Court Orders Complied',    sub: 'relating to VPN activity',  color: 'text-emerald-400' },
            { value: '100%', label: 'Requests Resisted',      sub: 'without VPN activity data', color: 'text-cyan' },
          ].map((stat) => (
            <div key={stat.label} className="bg-navy-secondary rounded-2xl border border-white/10 p-5 text-center">
              <p className={`font-orbitron text-3xl font-bold mb-1 ${stat.color}`}>{stat.value}</p>
              <p className="text-xs font-semibold text-white/70 leading-tight">{stat.label}</p>
              <p className="text-xs text-white/30 font-mono mt-1">{stat.sub}</p>
            </div>
          ))}
        </div>

        {/* Sections */}
        <div className="space-y-8">

          <div className="bg-navy-secondary rounded-2xl border border-white/10 p-6">
            <div className="flex items-center gap-3 mb-4">
              <div className="w-8 h-8 rounded-lg bg-cyan/10 flex items-center justify-center"><Lock size={16} className="text-cyan" /></div>
              <h3 className="font-orbitron font-bold text-lg">Government & Legal Requests</h3>
            </div>
            <div className="space-y-4 text-white/65 text-[15px] leading-relaxed">
              <p>During the reporting period (1 January 2025 – 31 December 2025), GeminiVPN received <strong className="text-white">zero</strong> requests from any government, law enforcement agency, or intelligence body seeking disclosure of user information.</p>
              <p>In the event we were to receive such a request, our response would be governed by our <strong className="text-white">no-logs architecture</strong>: because we do not retain VPN activity data, we are technically incapable of providing traffic logs, connection timestamps, DNS queries, or IP addresses to any requesting authority — regardless of the legal framework applied.</p>
              <p>The only data we could produce in response to a legally enforceable order is: account registration email, subscription status, and payment transaction references. No browsing or connection data exists to be produced.</p>
            </div>
          </div>

          <div className="bg-navy-secondary rounded-2xl border border-white/10 p-6">
            <div className="flex items-center gap-3 mb-4">
              <div className="w-8 h-8 rounded-lg bg-purple-400/10 flex items-center justify-center"><ShieldOff size={16} className="text-purple-400" /></div>
              <h3 className="font-orbitron font-bold text-lg">What Data We Could Not Produce (By Design)</h3>
            </div>
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
              {[
                'Originating IP addresses during VPN sessions',
                'Exit/outbound IP addresses per user',
                'DNS queries made through our resolvers',
                'Connection timestamps or session durations',
                'Bandwidth consumed per user session',
                'Websites or applications accessed',
                'Traffic content or payload data',
                'Per-device activity or usage patterns',
              ].map((item) => (
                <div key={item} className="flex items-start gap-2 p-3 bg-navy-primary rounded-xl">
                  <CheckCircle size={14} className="text-emerald-400 flex-shrink-0 mt-0.5" />
                  <span className="text-sm text-white/60">{item}</span>
                </div>
              ))}
            </div>
            <p className="text-xs text-white/30 font-mono mt-4">None of the above data is generated or retained. Absence is structural — not a deletion policy.</p>
          </div>

          <div className="bg-navy-secondary rounded-2xl border border-white/10 p-6">
            <div className="flex items-center gap-3 mb-4">
              <div className="w-8 h-8 rounded-lg bg-yellow-400/10 flex items-center justify-center"><AlertTriangle size={16} className="text-yellow-400" /></div>
              <h3 className="font-orbitron font-bold text-lg">Security Incidents</h3>
            </div>
            <div className="space-y-4 text-white/65 text-[15px] leading-relaxed">
              <p>During 2025, GeminiVPN experienced <strong className="text-white">zero</strong> confirmed security incidents, data breaches, or unauthorised access events affecting user data.</p>
              <p>No user credentials, payment tokens, or account records were exposed or compromised during the reporting period.</p>
              <p>Our infrastructure is protected by: end-to-end TLS 1.3, UFW firewall with allowlist-only ingress rules, fail2ban brute-force protection, SQLite database running in an isolated private Docker network (not internet-accessible), and bcrypt password hashing (cost factor 12).</p>
            </div>
          </div>

          <div className="bg-navy-secondary rounded-2xl border border-white/10 p-6">
            <div className="flex items-center gap-3 mb-4">
              <div className="w-8 h-8 rounded-lg bg-cyan/10 flex items-center justify-center"><Eye size={16} className="text-cyan" /></div>
              <h3 className="font-orbitron font-bold text-lg">Infrastructure & Data Sovereignty</h3>
            </div>
            <div className="space-y-3 text-white/65 text-[15px] leading-relaxed">
              <p>GeminiVPN operates its own infrastructure. User account data is stored exclusively on our dedicated server (167.172.96.225). We do not use:</p>
              <div className="grid grid-cols-1 sm:grid-cols-2 gap-2 my-3">
                {['AWS / Google Cloud / Azure user databases', 'Third-party analytics platforms', 'External session stores (data in SQLite only)', 'Advertising or tracking networks', 'CDN-stored user data', 'SaaS CRM tools with user PII'].map((item) => (
                  <div key={item} className="flex items-center gap-2 text-sm">
                    <span className="w-4 h-4 rounded-full bg-white/5 border border-white/10 flex items-center justify-center text-white/30 text-[10px]">✕</span>
                    <span>{item}</span>
                  </div>
                ))}
              </div>
              <p>Payment data is handled exclusively by our PCI-DSS certified payment partners (Stripe, Square, Paddle, Coinbase Commerce). We receive only a transaction reference token — never raw card data.</p>
            </div>
          </div>

          <div className="bg-navy-secondary rounded-2xl border border-white/10 p-6">
            <h3 className="font-orbitron font-bold text-lg mb-4">Our Commitment Going Forward</h3>
            <div className="space-y-3 text-white/65 text-[15px] leading-relaxed">
              <p>GeminiVPN commits to publishing this Transparency Report annually, no later than 31 January of each year covering the prior calendar year. We will always disclose:</p>
              <p>• The total number and types of legal requests received.</p>
              <p>• The outcome of each request (complied, contested, or technically unable to fulfil).</p>
              <p>• Any security incidents and the data types affected.</p>
              <p>• Structural changes to our data handling or infrastructure that affect user privacy.</p>
              <p>Transparency is not a marketing feature for us — it is a foundational commitment to our users. Your privacy is the product we are in business to protect.</p>
            </div>
          </div>

        </div>

        <div className="mt-12 pt-6 border-t border-white/5 text-center">
          <p className="font-mono text-xs text-white/20">GeminiVPN Transparency Report · Period: 2025 · Published: 1 January 2026</p>
        </div>
      </div>
    </div>
  );
}
