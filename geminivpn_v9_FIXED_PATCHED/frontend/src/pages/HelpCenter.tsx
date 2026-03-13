/**
 * GeminiVPN — Help Center
 */
import React, { useState } from 'react';
import { ArrowLeft, Search, ChevronRight, HelpCircle, Shield, CreditCard, Smartphone, Wifi, Lock, Zap, X } from 'lucide-react';
import { Input } from '@/components/ui/input';

interface HelpCenterProps { onBack: () => void; onContact: () => void; }

const CATEGORIES = [
  {
    id: 'getting-started',
    icon: Zap,
    label: 'Getting Started',
    color: 'text-cyan bg-cyan/10 border-cyan/20',
    articles: [
      { title: 'How to create your GeminiVPN account', content: 'Creating an account takes under 60 seconds. Click "Get GeminiVPN" on the homepage, enter your email address and choose a strong password of at least 8 characters. Your account is created instantly — no email verification delay. Your data is stored securely in our PostgreSQL database and never shared with third parties.' },
      { title: 'Downloading and installing the app', content: 'GeminiVPN is available on iOS (App Store), Android (APK direct download), Windows (.exe installer), macOS (.dmg), and Linux (.AppImage / .deb). Visit the Download section on our homepage and select your platform. The iOS version requires iOS 14 or later; Android requires 8.0 (Oreo) or later.' },
      { title: 'Connecting to your first VPN server', content: 'After installing and signing in, tap the power button on the home screen. GeminiVPN will automatically select the fastest server for your location. To choose a specific region, tap the server name and browse our 60+ country network. Your first connection is protected by WireGuard® — the modern, fastest VPN protocol available.' },
      { title: 'How many devices can I connect?', content: 'Your GeminiVPN subscription covers up to 10 simultaneous devices. Connect your phone, laptop, tablet, and more — all under one account. To manage your devices, log in and visit the Devices section. If you reach the limit, disconnect an existing device to add a new one.' },
    ],
  },
  {
    id: 'billing',
    icon: CreditCard,
    label: 'Billing & Payments',
    color: 'text-emerald-400 bg-emerald-400/10 border-emerald-400/20',
    articles: [
      { title: 'What payment methods do you accept?', content: 'GeminiVPN accepts all major credit/debit cards via Stripe, Square card payments, Paddle subscription billing (which handles tax compliance globally), and cryptocurrency via Coinbase Commerce. All payments are processed securely and we do not store your full card number on our servers.' },
      { title: 'How do I get a refund?', content: 'We offer a 30-day money-back guarantee on all new subscriptions. Contact our support team via WhatsApp or email within 30 days of your purchase. Refunds are typically processed within 3–7 business days depending on your bank. Cryptocurrency refunds are issued as credit to your GeminiVPN account.' },
      { title: 'When will I be billed again?', content: 'Monthly plans renew every 30 days from your initial subscription date. Annual plans renew every 365 days. Two-year plans renew every 730 days. You will receive an email reminder 7 days before your renewal. You can cancel auto-renewal at any time from the Account section.' },
      { title: 'How do I cancel my subscription?', content: 'You can cancel anytime from the Account section — there are no cancellation fees. After cancelling, you retain full access until the end of your billing period. To cancel, sign in, navigate to Account → Subscription, and click "Cancel Plan". Your data is retained for 30 days in case you change your mind.' },
      { title: 'Is my payment information secure?', content: 'Absolutely. GeminiVPN never stores full card numbers. All payment data is handled by our PCI-DSS compliant payment processors (Stripe, Square, Paddle). For cryptocurrency, transactions are verified via Coinbase Commerce. We store only a tokenised reference in our PostgreSQL database — never raw financial details.' },
    ],
  },
  {
    id: 'privacy',
    icon: Shield,
    label: 'Privacy & Security',
    color: 'text-purple-400 bg-purple-400/10 border-purple-400/20',
    articles: [
      { title: 'Does GeminiVPN keep logs?', content: 'No. GeminiVPN operates a strict zero-logs policy. We do not log your VPN traffic, DNS queries, browsing history, IP addresses during sessions, or connection timestamps. The only data we retain is your account email, subscription status, and payment history — all stored in an isolated PostgreSQL database.' },
      { title: 'What is the WireGuard® protocol?', content: 'WireGuard® is a modern, lean VPN protocol developed as an alternative to OpenVPN and IKEv2. It uses state-of-the-art cryptography (Noise protocol, Curve25519, ChaCha20, Poly1305, BLAKE2) and is significantly faster and simpler than older protocols. GeminiVPN uses WireGuard® exclusively for all tunnels.' },
      { title: 'What is the kill switch?', content: 'The kill switch (also called a network lock) automatically cuts your internet connection if the VPN tunnel drops unexpectedly. This prevents your real IP address from being exposed even for a fraction of a second. The GeminiVPN kill switch operates at the system level and is enabled by default on all platforms.' },
      { title: 'What is DNS leak protection?', content: 'Without DNS leak protection, your DNS queries (website lookups) can bypass the VPN tunnel and be seen by your ISP. GeminiVPN routes all DNS traffic through our encrypted servers using hardened DNS resolvers (1.1.1.1 and 1.0.0.1 via tunnel). You can verify your protection at dnsleaktest.com while connected.' },
    ],
  },
  {
    id: 'apps',
    icon: Smartphone,
    label: 'Apps & Devices',
    color: 'text-orange-400 bg-orange-400/10 border-orange-400/20',
    articles: [
      { title: 'How to set up GeminiVPN on Android', content: 'Download GeminiVPN.apk from the Download section. Before installing, enable "Install from Unknown Sources" in Settings → Security (required for sideloaded APKs). Open the APK file and follow the installer. Once installed, sign in with your account credentials. The Android app supports auto-connect, kill switch, and split tunnelling.' },
      { title: 'How to set up GeminiVPN on iOS', content: 'Download GeminiVPN from the App Store (search "GeminiVPN"). Tap Install. When you first connect, iOS will ask permission to add a VPN configuration — tap Allow. Sign in with your account email and password. The iOS app uses the Network Extension framework for background protection.' },
      { title: 'How to set up GeminiVPN on a router', content: 'Setting up GeminiVPN on your router protects all devices on your network without installing the app on each one. Download the Router Setup Guide from the Download section. Our guide covers major router firmwares including OpenWRT, DD-WRT, and AsusWRT. WireGuard® router setup typically takes 10–15 minutes.' },
      { title: 'Why is my connection slow?', content: 'VPN speed depends on several factors: your base ISP speed, the distance to the selected server, and current server load. For best performance: choose a server geographically close to you (the dashboard shows latency in ms), enable auto-select, and ensure no other heavy downloads are running. Our 10 Gbps servers rarely exceed 70% load.' },
    ],
  },
  {
    id: 'troubleshooting',
    icon: Wifi,
    label: 'Troubleshooting',
    color: 'text-yellow-400 bg-yellow-400/10 border-yellow-400/20',
    articles: [
      { title: 'VPN connection keeps dropping', content: 'Intermittent drops are usually caused by a weak base internet connection or an aggressive firewall. Try these steps: 1) Switch to a different server, 2) Check that your firewall allows UDP on port 51820, 3) Enable the auto-reconnect option in Settings, 4) If on mobile, disable battery optimisation for the GeminiVPN app.' },
      { title: 'Cannot log in to my account', content: 'First, verify your email address is exactly as registered (case-sensitive). If you forgot your password, use the "Forgot Password" link on the login dialog. If you receive a "session invalid" error, clear your browser cache or re-install the mobile app. For persistent issues, contact support with your registered email.' },
      { title: 'App is not connecting on my network', content: 'Some networks (hotel Wi-Fi, corporate firewalls, restrictive ISPs) block VPN protocols. Try: 1) Switch from UDP to TCP in Settings → Protocol, 2) Try a different server, 3) Enable "Stealth Mode" which disguises VPN traffic as regular HTTPS. If on a corporate network, consult your IT policy before using a VPN.' },
    ],
  },
  {
    id: 'account',
    icon: Lock,
    label: 'Account Management',
    color: 'text-rose-400 bg-rose-400/10 border-rose-400/20',
    articles: [
      { title: 'How to change my password', content: 'Sign in to GeminiVPN, go to Account → Security → Change Password. Enter your current password, then your new password (minimum 8 characters). Your new password takes effect immediately and all other sessions will be logged out for security.' },
      { title: 'How to delete my account', content: 'To delete your account, contact our support team via email or WhatsApp. Under GDPR and applicable privacy laws, we will permanently delete all your personal data within 30 days of your verified request. Payment transaction records required by law are retained for up to 7 years per financial regulations.' },
      { title: 'Managing connected devices', content: 'Sign in and navigate to Account → Devices. You will see all devices that are currently using your account. To remove a device, click the trash icon next to it. Removing a device immediately revokes its access and the WireGuard® configuration is invalidated. The slot becomes available immediately for a new device.' },
    ],
  },
];

export default function HelpCenter({ onBack, onContact }: HelpCenterProps) {
  const [query, setQuery]             = useState('');
  const [activeCategory, setActiveCategory] = useState<string | null>(null);
  const [activeArticle, setActiveArticle]   = useState<{ title: string; content: string } | null>(null);

  const allArticles = CATEGORIES.flatMap((c) => c.articles.map((a) => ({ ...a, categoryLabel: c.label })));
  const filtered = query.trim()
    ? allArticles.filter((a) => a.title.toLowerCase().includes(query.toLowerCase()) || a.content.toLowerCase().includes(query.toLowerCase()))
    : [];

  const activeCat = CATEGORIES.find((c) => c.id === activeCategory);

  return (
    <div className="min-h-screen bg-navy-primary text-white">
      {/* Header */}
      <div className="sticky top-0 z-50 bg-navy-primary/90 backdrop-blur-md border-b border-white/5">
        <div className="max-w-4xl mx-auto px-4 sm:px-6 h-16 flex items-center gap-4">
          <button onClick={activeArticle ? () => setActiveArticle(null) : activeCategory ? () => setActiveCategory(null) : onBack}
            className="p-2 hover:bg-white/5 rounded-lg transition-colors" aria-label="Go back">
            <ArrowLeft size={20} className="text-white/70" />
          </button>
          <div className="flex items-center gap-3 flex-1">
            <HelpCircle size={20} className="text-cyan" />
            <h1 className="font-orbitron font-bold tracking-wider text-sm sm:text-base">
              {activeArticle ? activeArticle.title.slice(0, 32) + (activeArticle.title.length > 32 ? '…' : '') :
               activeCat ? activeCat.label :
               'HELP CENTER'}
            </h1>
          </div>
          <button onClick={onContact}
            className="hidden sm:flex items-center gap-2 px-3 py-1.5 bg-cyan/10 border border-cyan/20 rounded-lg text-cyan text-xs font-mono hover:bg-cyan/20 transition-colors">
            Contact Support
          </button>
        </div>
      </div>

      {/* Article view */}
      {activeArticle && (
        <div className="max-w-3xl mx-auto px-4 sm:px-6 py-10">
          <h2 className="font-orbitron text-2xl sm:text-3xl font-bold mb-6 leading-tight">{activeArticle.title}</h2>
          <div className="prose prose-invert max-w-none">
            {activeArticle.content.split('. ').reduce((acc: string[], sentence, i, arr) => {
              if (i % 3 === 0) acc.push(arr.slice(i, i + 3).join('. ') + (i + 3 < arr.length ? '.' : ''));
              return acc;
            }, []).map((para, i) => (
              <p key={i} className="text-white/70 leading-relaxed text-base mb-4">{para}</p>
            ))}
          </div>
          <div className="mt-10 pt-6 border-t border-white/10">
            <p className="text-sm text-white/40 mb-4">Was this article helpful?</p>
            <div className="flex gap-3">
              <button onClick={() => { setActiveArticle(null); }} className="px-5 py-2 bg-emerald-400/10 border border-emerald-400/20 rounded-lg text-emerald-400 text-sm hover:bg-emerald-400/20 transition-colors">👍 Yes</button>
              <button onClick={onContact} className="px-5 py-2 bg-white/5 border border-white/10 rounded-lg text-white/60 text-sm hover:bg-white/10 transition-colors">No — Contact Support</button>
            </div>
          </div>
        </div>
      )}

      {/* Category article list */}
      {!activeArticle && activeCat && (
        <div className="max-w-4xl mx-auto px-4 sm:px-6 py-8">
          <div className={`inline-flex items-center gap-2 px-3 py-1.5 rounded-full border text-sm mb-6 ${activeCat.color}`}>
            <activeCat.icon size={14} />
            <span className="font-mono text-xs uppercase tracking-wider">{activeCat.label}</span>
          </div>
          <div className="space-y-2">
            {activeCat.articles.map((a, i) => (
              <button key={i} onClick={() => setActiveArticle(a)}
                className="w-full flex items-center justify-between p-5 bg-navy-secondary rounded-xl border border-white/10 hover:border-cyan/30 transition-colors text-left group">
                <span className="font-medium text-sm pr-4">{a.title}</span>
                <ChevronRight size={16} className="text-white/30 group-hover:text-cyan transition-colors flex-shrink-0" />
              </button>
            ))}
          </div>
        </div>
      )}

      {/* Home: search + categories */}
      {!activeArticle && !activeCat && (
        <div className="max-w-4xl mx-auto px-4 sm:px-6 py-8">
          {/* Hero */}
          <div className="text-center mb-10">
            <h2 className="font-orbitron text-3xl sm:text-4xl font-bold mb-3">How can we help?</h2>
            <p className="text-white/50 text-sm">Search our knowledge base or browse by category</p>
          </div>

          {/* Search */}
          <div className="relative mb-8">
            <Search size={18} className="absolute left-4 top-1/2 -translate-y-1/2 text-white/30" />
            <Input value={query} onChange={(e) => setQuery(e.target.value)} placeholder="Search articles…"
              className="bg-navy-secondary border-white/10 text-white placeholder:text-white/30 pl-12 h-12 text-sm" />
            {query && <button onClick={() => setQuery('')} className="absolute right-4 top-1/2 -translate-y-1/2 text-white/30 hover:text-white"><X size={16} /></button>}
          </div>

          {/* Search results */}
          {query && (
            <div className="mb-8">
              <p className="font-mono text-xs text-white/30 uppercase tracking-wider mb-3">{filtered.length} result{filtered.length !== 1 ? 's' : ''}</p>
              {filtered.length === 0 ? (
                <div className="text-center py-10 text-white/30 text-sm">No articles match "{query}"</div>
              ) : (
                <div className="space-y-2">
                  {filtered.map((a, i) => (
                    <button key={i} onClick={() => setActiveArticle(a)}
                      className="w-full flex items-start justify-between p-5 bg-navy-secondary rounded-xl border border-white/10 hover:border-cyan/30 transition-colors text-left group">
                      <div>
                        <p className="font-medium text-sm">{a.title}</p>
                        <p className="text-xs text-white/30 mt-0.5 font-mono">{a.categoryLabel}</p>
                      </div>
                      <ChevronRight size={16} className="text-white/30 group-hover:text-cyan transition-colors flex-shrink-0 mt-0.5" />
                    </button>
                  ))}
                </div>
              )}
            </div>
          )}

          {/* Categories */}
          {!query && (
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
              {CATEGORIES.map((cat) => (
                <button key={cat.id} onClick={() => setActiveCategory(cat.id)}
                  className="flex items-start gap-4 p-6 bg-navy-secondary rounded-2xl border border-white/10 hover:border-white/20 transition-colors text-left group">
                  <div className={`w-10 h-10 rounded-xl flex items-center justify-center border flex-shrink-0 ${cat.color}`}>
                    <cat.icon size={18} />
                  </div>
                  <div className="flex-1">
                    <p className="font-semibold text-sm">{cat.label}</p>
                    <p className="text-xs text-white/40 mt-0.5">{cat.articles.length} articles</p>
                  </div>
                  <ChevronRight size={16} className="text-white/20 group-hover:text-white/60 transition-colors mt-0.5" />
                </button>
              ))}
            </div>
          )}

          {/* Contact prompt */}
          <div className="mt-10 text-center p-8 bg-navy-secondary rounded-2xl border border-white/10">
            <p className="font-semibold text-sm mb-1">Didn't find what you were looking for?</p>
            <p className="text-xs text-white/40 mb-4">Our support team responds within 2 hours on average.</p>
            <button onClick={onContact}
              className="px-6 py-2.5 bg-cyan/10 border border-cyan/30 rounded-xl text-cyan text-sm font-mono hover:bg-cyan/20 transition-colors">
              Contact Support →
            </button>
          </div>
        </div>
      )}
    </div>
  );
}
