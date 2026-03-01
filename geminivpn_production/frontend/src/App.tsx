import { useState, useEffect, useRef } from 'react';
import { gsap } from 'gsap';
import { ScrollTrigger } from 'gsap/ScrollTrigger';
import {
  Shield, Zap, Globe, Lock, Smartphone,
  ChevronDown, Menu, X, Check, Server,
  Play, Pause, RefreshCw, Wifi,
  Apple, Monitor, Tablet, ArrowUp
} from 'lucide-react';
import { Button } from '@/components/ui/button';
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { Input } from '@/components/ui/input';
import { Accordion, AccordionContent, AccordionItem, AccordionTrigger } from '@/components/ui/accordion';
import { toast } from 'sonner';

gsap.registerPlugin(ScrollTrigger);

// ─── Types ───────────────────────────────────────────────────────────────────
interface ServerLocation {
  id: string;
  city: string;
  country: string;
  flag: string;
  latency: number;
  load: number;
}

interface User {
  email: string;
  name: string;
}

// ─── Data ────────────────────────────────────────────────────────────────────
const SERVER_LOCATIONS: ServerLocation[] = [
  { id: 'us-ny', city: 'New York',    country: 'USA',         flag: '🇺🇸', latency: 9,  load: 45 },
  { id: 'us-la', city: 'Los Angeles', country: 'USA',         flag: '🇺🇸', latency: 12, load: 38 },
  { id: 'uk-ln', city: 'London',      country: 'UK',          flag: '🇬🇧', latency: 15, load: 52 },
  { id: 'de-be', city: 'Berlin',      country: 'Germany',     flag: '🇩🇪', latency: 18, load: 41 },
  { id: 'jp-tk', city: 'Tokyo',       country: 'Japan',       flag: '🇯🇵', latency: 22, load: 67 },
  { id: 'sg-sg', city: 'Singapore',   country: 'Singapore',   flag: '🇸🇬', latency: 25, load: 55 },
  { id: 'au-sy', city: 'Sydney',      country: 'Australia',   flag: '🇦🇺', latency: 28, load: 43 },
  { id: 'br-sp', city: 'São Paulo',   country: 'Brazil',      flag: '🇧🇷', latency: 35, load: 39 },
  { id: 'fr-pa', city: 'Paris',       country: 'France',      flag: '🇫🇷', latency: 16, load: 30 },
  { id: 'nl-am', city: 'Amsterdam',   country: 'Netherlands', flag: '🇳🇱', latency: 14, load: 28 },
];

const PRICING_PLANS = [
  {
    name: 'Monthly',
    price: '$11.99',
    period: '/mo',
    billed: 'Billed monthly',
    cta: 'Start Monthly',
    highlighted: false,
    features: ['10 devices', '10 Gbps servers', 'No logs', 'Kill switch', '24/7 support'],
  },
  {
    name: '1-Year',
    price: '$4.99',
    period: '/mo',
    billed: 'Billed $59.88/year',
    cta: 'Start 1-Year',
    highlighted: true,
    features: ['10 devices', '10 Gbps servers', 'No logs', 'Kill switch', '24/7 support', 'Priority routing'],
  },
  {
    name: '2-Year',
    price: '$3.49',
    period: '/mo',
    billed: 'Billed $83.76/2 years',
    cta: 'Start 2-Year',
    highlighted: false,
    features: ['10 devices', '10 Gbps servers', 'No logs', 'Kill switch', '24/7 support', 'Priority routing'],
  },
];

const FAQ_ITEMS = [
  {
    question: 'Does GeminiVPN keep logs?',
    answer: 'No. GeminiVPN operates under a strict no-logs policy. We do not track, store, or share any of your online activity or personal information.',
  },
  {
    question: 'How many devices can I connect?',
    answer: 'You can connect up to 10 devices simultaneously with a single GeminiVPN account across all major platforms.',
  },
  {
    question: 'Will it slow down my internet?',
    answer: 'GeminiVPN is optimized for ultra-low latency with our 10 Gbps server network. Most users experience minimal to no speed reduction.',
  },
  {
    question: 'Can I use it for streaming?',
    answer: 'Yes! GeminiVPN unlocks popular streaming services and is optimized for HD and 4K streaming without buffering.',
  },
  {
    question: 'What if I need a refund?',
    answer: "We offer a 30-day money-back guarantee. If you're not satisfied, contact our 24/7 support for a full refund.",
  },
  {
    question: 'Is WireGuard protocol supported?',
    answer: 'Yes! We use WireGuard® — the fastest, most modern VPN protocol. It offers better speeds and stronger security than OpenVPN or IKEv2.',
  },
  {
    question: 'Does it work on all devices?',
    answer: 'GeminiVPN works on iOS, Android, Windows, macOS, Linux, and routers. One account, all your devices.',
  },
];

// ─── Helper: latency colour ───────────────────────────────────────────────────
const latencyColor = (ms: number) =>
  ms <= 12 ? 'text-green-400' : ms <= 25 ? 'text-yellow-400' : 'text-orange-400';

// ─── Navigation ──────────────────────────────────────────────────────────────
function Navigation({
  user, onLogout, onLoginClick, onRegisterClick,
}: {
  user: User | null;
  onLogout: () => void;
  onLoginClick: () => void;
  onRegisterClick: () => void;
}) {
  const [isScrolled, setIsScrolled] = useState(false);
  const [isMobileMenuOpen, setIsMobileMenuOpen] = useState(false);

  useEffect(() => {
    const handleScroll = () => setIsScrolled(window.scrollY > 50);
    window.addEventListener('scroll', handleScroll, { passive: true });
    return () => window.removeEventListener('scroll', handleScroll);
  }, []);

  const scrollToSection = (id: string) => {
    document.getElementById(id)?.scrollIntoView({ behavior: 'smooth' });
    setIsMobileMenuOpen(false);
  };

  const navLinks = ['features', 'servers', 'pricing', 'download', 'support'];

  return (
    <nav
      className={`fixed top-0 left-0 right-0 z-50 transition-all duration-300 ${
        isScrolled ? 'bg-navy-primary/90 backdrop-blur-md border-b border-white/5' : 'bg-transparent'
      }`}
      role="navigation"
      aria-label="Main navigation"
    >
      <div className="w-full px-4 sm:px-6 lg:px-8 xl:px-12">
        <div className="flex items-center justify-between h-16 lg:h-20">
          {/* Logo */}
          <a
            href="#"
            onClick={(e) => { e.preventDefault(); window.scrollTo({ top: 0, behavior: 'smooth' }); }}
            className="flex items-center gap-3 focus:outline-none focus-visible:ring-2 focus-visible:ring-cyan rounded-lg"
            aria-label="GeminiVPN Home"
          >
            <img src="/geminivpn-logo.png" alt="GeminiVPN Logo" className="w-8 h-8 lg:w-10 lg:h-10" />
            <span className="font-orbitron font-bold text-lg lg:text-xl tracking-wider text-white">
              GEMINI<span className="text-cyan">VPN</span>
            </span>
          </a>

          {/* Desktop Nav */}
          <div className="hidden lg:flex items-center gap-8">
            {navLinks.map((item) => (
              <button
                key={item}
                onClick={() => scrollToSection(item)}
                className="font-mono text-xs uppercase tracking-[0.18em] text-white/70 hover:text-cyan transition-colors focus:outline-none focus-visible:text-cyan"
              >
                {item}
              </button>
            ))}
          </div>

          {/* Auth */}
          <div className="hidden lg:flex items-center gap-4">
            {user ? (
              <div className="flex items-center gap-4">
                <span className="text-sm text-white/70 max-w-[160px] truncate">{user.email}</span>
                <Button
                  variant="outline"
                  size="sm"
                  onClick={onLogout}
                  className="border-cyan/50 text-cyan hover:bg-cyan/10"
                >
                  Logout
                </Button>
              </div>
            ) : (
              <>
                <Button
                  variant="ghost"
                  size="sm"
                  onClick={onLoginClick}
                  className="text-white/70 hover:text-white"
                >
                  Login
                </Button>
                <Button
                  size="sm"
                  onClick={onRegisterClick}
                  className="bg-cyan text-navy-primary hover:bg-cyan-dark font-semibold"
                >
                  Get GeminiVPN
                </Button>
              </>
            )}
          </div>

          {/* Mobile toggle */}
          <button
            onClick={() => setIsMobileMenuOpen(!isMobileMenuOpen)}
            className="lg:hidden p-2 text-white focus:outline-none focus-visible:ring-2 focus-visible:ring-cyan rounded-lg"
            aria-label={isMobileMenuOpen ? 'Close menu' : 'Open menu'}
            aria-expanded={isMobileMenuOpen}
          >
            {isMobileMenuOpen ? <X size={24} /> : <Menu size={24} />}
          </button>
        </div>
      </div>

      {/* Mobile menu */}
      {isMobileMenuOpen && (
        <div className="lg:hidden bg-navy-primary/95 backdrop-blur-md border-t border-white/5">
          <div className="px-4 py-6 space-y-4">
            {navLinks.map((item) => (
              <button
                key={item}
                onClick={() => scrollToSection(item)}
                className="block w-full text-left font-mono text-sm uppercase tracking-[0.18em] text-white/70 hover:text-cyan py-2 transition-colors"
              >
                {item}
              </button>
            ))}
            <div className="pt-4 border-t border-white/10 space-y-3">
              {user ? (
                <>
                  <span className="block text-sm text-white/70 truncate">{user.email}</span>
                  <Button
                    variant="outline"
                    className="w-full border-cyan/50 text-cyan"
                    onClick={() => { onLogout(); setIsMobileMenuOpen(false); }}
                  >
                    Logout
                  </Button>
                </>
              ) : (
                <>
                  <Button
                    variant="outline"
                    className="w-full border-white/20 text-white"
                    onClick={() => { onLoginClick(); setIsMobileMenuOpen(false); }}
                  >
                    Login
                  </Button>
                  <Button
                    className="w-full bg-cyan text-navy-primary font-semibold"
                    onClick={() => { onRegisterClick(); setIsMobileMenuOpen(false); }}
                  >
                    Get GeminiVPN
                  </Button>
                </>
              )}
            </div>
          </div>
        </div>
      )}
    </nav>
  );
}

// ─── Auth Dialog ─────────────────────────────────────────────────────────────
function AuthDialog({
  isOpen, onClose, type, onSuccess,
}: {
  isOpen: boolean;
  onClose: () => void;
  type: 'login' | 'register';
  onSuccess: (user: User) => void;
}) {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [name, setName] = useState('');
  const [isLoading, setIsLoading] = useState(false);
  const [errors, setErrors] = useState<{ email?: string; password?: string }>({});

  // Reset form when dialog opens
  useEffect(() => {
    if (isOpen) {
      setEmail('');
      setPassword('');
      setName('');
      setErrors({});
    }
  }, [isOpen, type]);

  const validate = () => {
    const newErrors: { email?: string; password?: string } = {};
    if (!email.includes('@')) newErrors.email = 'Enter a valid email';
    if (password.length < 6) newErrors.password = 'Password must be at least 6 characters';
    setErrors(newErrors);
    return Object.keys(newErrors).length === 0;
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!validate()) return;

    setIsLoading(true);
    // Simulate API call
    await new Promise((res) => setTimeout(res, 800));

    const user: User = { email, name: name || email.split('@')[0] };
    onSuccess(user);
    onClose();
    toast.success(type === 'login' ? `Welcome back, ${user.name}!` : 'Account created! Welcome to GeminiVPN 🚀');
    setIsLoading(false);
  };

  return (
    <Dialog open={isOpen} onOpenChange={onClose}>
      <DialogContent className="bg-navy-secondary border-white/10 text-white max-w-md">
        <DialogHeader>
          <DialogTitle className="font-orbitron text-2xl text-center">
            {type === 'login' ? 'Welcome Back' : 'Create Account'}
          </DialogTitle>
        </DialogHeader>
        <form onSubmit={handleSubmit} className="space-y-4 mt-4" noValidate>
          {type === 'register' && (
            <div>
              <label className="text-sm text-white/70 mb-1 block" htmlFor="auth-name">Name</label>
              <Input
                id="auth-name"
                type="text"
                value={name}
                onChange={(e) => setName(e.target.value)}
                placeholder="Your name"
                className="bg-navy-primary border-white/10 text-white placeholder:text-white/30"
              />
            </div>
          )}
          <div>
            <label className="text-sm text-white/70 mb-1 block" htmlFor="auth-email">Email</label>
            <Input
              id="auth-email"
              type="email"
              value={email}
              onChange={(e) => { setEmail(e.target.value); setErrors((p) => ({ ...p, email: undefined })); }}
              placeholder="you@example.com"
              className={`bg-navy-primary border-white/10 text-white placeholder:text-white/30 ${errors.email ? 'border-red-500' : ''}`}
              required
              aria-describedby={errors.email ? 'email-error' : undefined}
            />
            {errors.email && <p id="email-error" className="text-xs text-red-400 mt-1">{errors.email}</p>}
          </div>
          <div>
            <label className="text-sm text-white/70 mb-1 block" htmlFor="auth-password">Password</label>
            <Input
              id="auth-password"
              type="password"
              value={password}
              onChange={(e) => { setPassword(e.target.value); setErrors((p) => ({ ...p, password: undefined })); }}
              placeholder="••••••••"
              className={`bg-navy-primary border-white/10 text-white placeholder:text-white/30 ${errors.password ? 'border-red-500' : ''}`}
              required
              aria-describedby={errors.password ? 'password-error' : undefined}
            />
            {errors.password && <p id="password-error" className="text-xs text-red-400 mt-1">{errors.password}</p>}
          </div>
          <Button
            type="submit"
            disabled={isLoading}
            className="w-full bg-cyan text-navy-primary hover:bg-cyan-dark font-semibold disabled:opacity-60"
          >
            {isLoading ? 'Please wait...' : type === 'login' ? 'Login' : 'Create Account'}
          </Button>
          <p className="text-center text-xs text-white/40">
            {type === 'login' ? "Don't have an account? " : 'Already have an account? '}
            <button
              type="button"
              onClick={() => { onClose(); }}
              className="text-cyan hover:underline"
            >
              {type === 'login' ? 'Sign up' : 'Log in'}
            </button>
          </p>
        </form>
      </DialogContent>
    </Dialog>
  );
}

// ─── VPN Dashboard ────────────────────────────────────────────────────────────
function VPNDashboard({
  user, onActivate,
}: {
  user: User | null;
  onActivate: () => void;
}) {
  const [isConnected, setIsConnected] = useState(false);
  const [isConnecting, setIsConnecting] = useState(false);
  const [selectedServer, setSelectedServer] = useState(SERVER_LOCATIONS[0]);
  const [latency, setLatency] = useState(9);
  const [showServerMenu, setShowServerMenu] = useState(false);
  const [isAutoRefresh, setIsAutoRefresh] = useState(true);
  const [connectionTime, setConnectionTime] = useState(0);
  const [dataDown, setDataDown] = useState(0);
  const [dataUp, setDataUp] = useState(0);

  // Simulate latency fluctuation
  useEffect(() => {
    if (!isConnected) return;
    const interval = setInterval(() => {
      setLatency(selectedServer.latency + Math.floor(Math.random() * 4) - 1);
      setDataDown((d) => d + Math.floor(Math.random() * 800 + 200));
      setDataUp((u) => u + Math.floor(Math.random() * 120 + 30));
    }, 2000);
    return () => clearInterval(interval);
  }, [isConnected, selectedServer.latency]);

  // Connection timer
  useEffect(() => {
    if (!isConnected) { setConnectionTime(0); return; }
    const interval = setInterval(() => setConnectionTime((t) => t + 1), 1000);
    return () => clearInterval(interval);
  }, [isConnected]);

  const formatTime = (s: number) => {
    const h = Math.floor(s / 3600).toString().padStart(2, '0');
    const m = Math.floor((s % 3600) / 60).toString().padStart(2, '0');
    const sec = (s % 60).toString().padStart(2, '0');
    return `${h}:${m}:${sec}`;
  };

  const formatBytes = (bytes: number) => {
    if (bytes < 1024) return `${bytes} B`;
    if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
    return `${(bytes / (1024 * 1024)).toFixed(2)} MB`;
  };

  const handleConnect = async () => {
    if (!user) { onActivate(); return; }
    if (isConnecting) return;

    setIsConnecting(true);
    await new Promise((res) => setTimeout(res, 1200));
    setIsConnecting(false);

    if (!isConnected) {
      setIsConnected(true);
      setDataDown(0);
      setDataUp(0);
      toast.success(`🔒 Connected to ${selectedServer.flag} ${selectedServer.city}`);
    } else {
      setIsConnected(false);
      toast.info('🔓 Disconnected');
    }
  };

  const handleServerSwitch = (server: typeof selectedServer) => {
    setSelectedServer(server);
    setShowServerMenu(false);
    setLatency(server.latency);
    if (isConnected) toast.success(`↔ Switched to ${server.flag} ${server.city}`);
  };

  return (
    <div className="bg-navy-secondary/80 backdrop-blur-xl rounded-2xl border border-white/10 p-6 shadow-card">
      {/* Status Header */}
      <div className="flex items-center justify-between mb-6">
        <div className="flex items-center gap-3">
          <div
            className={`w-3 h-3 rounded-full transition-colors ${
              isConnecting ? 'bg-yellow-400 animate-pulse' :
              isConnected  ? 'bg-green-500 animate-pulse' : 'bg-red-500'
            }`}
            aria-label={isConnecting ? 'Connecting' : isConnected ? 'Connected' : 'Disconnected'}
          />
          <span className="font-mono text-sm uppercase tracking-wider">
            {isConnecting ? 'Connecting...' : isConnected ? 'Protected' : 'Unprotected'}
          </span>
        </div>
        <button
          onClick={() => setIsAutoRefresh(!isAutoRefresh)}
          className={`p-2 rounded-lg transition-colors ${isAutoRefresh ? 'bg-cyan/20 text-cyan' : 'bg-white/5 text-white/50'}`}
          title="Auto-refresh stats"
          aria-label={isAutoRefresh ? 'Disable auto-refresh' : 'Enable auto-refresh'}
        >
          <RefreshCw size={16} className={isAutoRefresh && isConnected ? 'animate-spin' : ''} />
        </button>
      </div>

      {/* Power Button */}
      <div className="flex flex-col items-center mb-6">
        <button
          onClick={handleConnect}
          disabled={isConnecting}
          aria-label={isConnected ? 'Disconnect VPN' : 'Connect VPN'}
          className={`w-32 h-32 rounded-full flex items-center justify-center transition-all duration-300 disabled:opacity-70 ${
            isConnected
              ? 'bg-green-500/20 border-4 border-green-500 shadow-[0_0_40px_rgba(34,197,94,0.3)]'
              : 'bg-cyan/20 border-4 border-cyan shadow-glow-strong hover:scale-105'
          }`}
        >
          {isConnecting ? (
            <RefreshCw size={40} className="animate-spin text-yellow-400" />
          ) : isConnected ? (
            <Pause size={40} className="text-green-500" />
          ) : (
            <Play size={40} className="text-cyan ml-1" fill="#00F0FF" />
          )}
        </button>
        <p className="mt-4 font-orbitron text-base font-semibold">
          {isConnecting ? 'Establishing Tunnel...' : isConnected ? 'Tap to Disconnect' : 'Tap to Connect'}
        </p>
        {!user && (
          <p className="text-xs text-white/50 mt-1">Sign in to connect</p>
        )}
      </div>

      {/* Server Selector */}
      <div className="relative mb-6">
        <button
          onClick={() => setShowServerMenu(!showServerMenu)}
          className="w-full flex items-center justify-between p-4 bg-navy-primary rounded-xl border border-white/10 hover:border-cyan/50 transition-colors"
          aria-expanded={showServerMenu}
          aria-haspopup="listbox"
        >
          <div className="flex items-center gap-3">
            <Globe size={20} className="text-cyan flex-shrink-0" />
            <div className="text-left">
              <p className="font-medium">
                {selectedServer.flag} {selectedServer.city}, {selectedServer.country}
              </p>
              <p className={`text-xs ${latencyColor(selectedServer.latency)}`}>
                {selectedServer.latency} ms · {selectedServer.load}% load
              </p>
            </div>
          </div>
          <ChevronDown
            size={20}
            className={`transition-transform flex-shrink-0 ${showServerMenu ? 'rotate-180' : ''}`}
          />
        </button>

        {showServerMenu && (
          <div
            className="absolute top-full left-0 right-0 mt-2 bg-navy-primary rounded-xl border border-white/10 shadow-card max-h-64 overflow-auto z-20"
            role="listbox"
            aria-label="Select server"
          >
            {SERVER_LOCATIONS.map((server) => (
              <button
                key={server.id}
                onClick={() => handleServerSwitch(server)}
                role="option"
                aria-selected={selectedServer.id === server.id}
                className={`w-full flex items-center justify-between p-4 hover:bg-white/5 transition-colors ${
                  selectedServer.id === server.id ? 'bg-cyan/10' : ''
                }`}
              >
                <div className="flex items-center gap-2">
                  <span>{server.flag}</span>
                  <span className="text-sm">{server.city}, {server.country}</span>
                  {selectedServer.id === server.id && (
                    <Check size={14} className="text-cyan ml-1" />
                  )}
                </div>
                <div className="flex items-center gap-3">
                  <span className={`text-xs font-mono ${latencyColor(server.latency)}`}>
                    {server.latency}ms
                  </span>
                  <div className="w-14 h-1.5 bg-white/10 rounded-full overflow-hidden" title={`${server.load}% load`}>
                    <div
                      className={`h-full rounded-full transition-all ${server.load > 60 ? 'bg-orange-400' : 'bg-green-400'}`}
                      style={{ width: `${server.load}%` }}
                    />
                  </div>
                </div>
              </button>
            ))}
          </div>
        )}
      </div>

      {/* Stats */}
      <div className="grid grid-cols-3 gap-3 mb-4">
        <div className="text-center p-3 bg-navy-primary rounded-xl">
          <p className={`font-mono text-xl font-bold ${latencyColor(latency)}`}>{isConnected ? latency : '--'}</p>
          <p className="text-xs text-white/50 mt-0.5">ms Ping</p>
        </div>
        <div className="text-center p-3 bg-navy-primary rounded-xl">
          <p className="font-mono text-sm font-bold text-cyan">{isConnected ? formatTime(connectionTime) : '--:--:--'}</p>
          <p className="text-xs text-white/50 mt-0.5">Uptime</p>
        </div>
        <div className="text-center p-3 bg-navy-primary rounded-xl">
          <p className="font-mono text-xl font-bold text-cyan">10G</p>
          <p className="text-xs text-white/50 mt-0.5">Bandwidth</p>
        </div>
      </div>

      {/* Data transfer (visible when connected) */}
      {isConnected && (
        <div className="grid grid-cols-2 gap-3 mb-4">
          <div className="flex items-center gap-2 p-3 bg-navy-primary rounded-xl">
            <span className="text-green-400 text-xs">▼</span>
            <div>
              <p className="font-mono text-sm text-white">{formatBytes(dataDown)}</p>
              <p className="text-xs text-white/40">Download</p>
            </div>
          </div>
          <div className="flex items-center gap-2 p-3 bg-navy-primary rounded-xl">
            <span className="text-cyan text-xs">▲</span>
            <div>
              <p className="font-mono text-sm text-white">{formatBytes(dataUp)}</p>
              <p className="text-xs text-white/40">Upload</p>
            </div>
          </div>
        </div>
      )}

      {/* Self-Healing Status */}
      <div className={`flex items-center justify-between p-3 rounded-xl border ${
        isConnected
          ? 'bg-green-500/10 border-green-500/20'
          : 'bg-white/5 border-white/10'
      }`}>
        <div className="flex items-center gap-2">
          <Shield size={16} className={isConnected ? 'text-green-400' : 'text-white/40'} />
          <span className={`text-sm ${isConnected ? 'text-green-400' : 'text-white/40'}`}>
            Self-healing {isConnected ? 'active' : 'standby'}
          </span>
        </div>
        <span className="text-xs text-white/40">
          {isConnected ? 'Auto-recovery on' : 'WireGuard® ready'}
        </span>
      </div>
    </div>
  );
}

// ─── Scroll-to-top button (NOT the Kimi icon — GeminiVPN's own) ──────────────
function ScrollToTopButton({ isVisible }: { isVisible: boolean }) {
  if (!isVisible) return null;
  return (
    <button
      onClick={() => window.scrollTo({ top: 0, behavior: 'smooth' })}
      className="fixed bottom-6 right-6 z-40 w-12 h-12 bg-navy-secondary border border-cyan/30 rounded-full flex items-center justify-center shadow-glow hover:bg-cyan/20 hover:scale-110 transition-all"
      aria-label="Back to top"
      title="Back to top"
    >
      <ArrowUp size={20} className="text-cyan" />
    </button>
  );
}

// ─── PWA Install Prompt ───────────────────────────────────────────────────────
function InstallPrompt({ isVisible, onClose }: { isVisible: boolean; onClose: () => void }) {
  const [deferredPrompt, setDeferredPrompt] = useState<any>(null);

  useEffect(() => {
    const handler = (e: Event) => { e.preventDefault(); setDeferredPrompt(e); };
    window.addEventListener('beforeinstallprompt', handler);
    return () => window.removeEventListener('beforeinstallprompt', handler);
  }, []);

  if (!isVisible) return null;

  const handleInstall = async () => {
    if (deferredPrompt) {
      deferredPrompt.prompt();
      const { outcome } = await deferredPrompt.userChoice;
      if (outcome === 'accepted') toast.success('GeminiVPN added to home screen!');
      setDeferredPrompt(null);
    } else {
      toast.info('Tap Share → "Add to Home Screen" to install');
    }
    onClose();
  };

  return (
    <div
      className="fixed bottom-20 right-4 z-40 bg-navy-secondary border border-cyan/30 rounded-2xl p-4 shadow-glow max-w-xs w-[calc(100vw-2rem)] sm:w-80"
      role="dialog"
      aria-label="Install GeminiVPN"
    >
      <div className="flex items-start gap-3">
        <div className="w-10 h-10 bg-cyan/20 rounded-xl flex items-center justify-center flex-shrink-0">
          <img src="/geminivpn-logo.png" alt="" className="w-6 h-6" />
        </div>
        <div>
          <p className="font-semibold text-sm">Add to Home Screen</p>
          <p className="text-xs text-white/60 mt-1">
            Access GeminiVPN instantly from your home screen
          </p>
        </div>
        <button onClick={onClose} className="text-white/40 hover:text-white ml-auto flex-shrink-0" aria-label="Close">
          <X size={16} />
        </button>
      </div>
      <div className="flex gap-2 mt-4">
        <Button variant="outline" size="sm" onClick={onClose} className="flex-1 border-white/20 text-white">
          Later
        </Button>
        <Button size="sm" onClick={handleInstall} className="flex-1 bg-cyan text-navy-primary font-semibold">
          Install
        </Button>
      </div>
    </div>
  );
}

// ─── Main App ────────────────────────────────────────────────────────────────
function App() {
  const [user, setUser] = useState<User | null>(null);
  const [showLogin, setShowLogin] = useState(false);
  const [showRegister, setShowRegister] = useState(false);
  const [showScrollTop, setShowScrollTop] = useState(false);
  const [showInstallPrompt, setShowInstallPrompt] = useState(false);
  const [ctaEmail, setCtaEmail] = useState('');
  const mainRef = useRef<HTMLDivElement>(null);

  // GSAP animations
  useEffect(() => {
    const ctx = gsap.context(() => {
      gsap.fromTo('.hero-headline',   { y: 40, opacity: 0 }, { y: 0, opacity: 1, duration: 1,   delay: 0.3, ease: 'power3.out' });
      gsap.fromTo('.hero-subheadline',{ y: 30, opacity: 0 }, { y: 0, opacity: 1, duration: 0.8, delay: 0.5, ease: 'power3.out' });
      gsap.fromTo('.hero-cta',        { y: 20, opacity: 0 }, { y: 0, opacity: 1, duration: 0.6, delay: 0.7, ease: 'power3.out' });
      gsap.fromTo('.hero-stats',      { opacity: 0 },        { opacity: 1, duration: 0.8, delay: 0.9, ease: 'power2.out' });

      document.querySelectorAll('.scroll-section').forEach((section) => {
        gsap.fromTo(
          section,
          { y: 60, opacity: 0 },
          {
            y: 0, opacity: 1, duration: 0.8, ease: 'power3.out',
            scrollTrigger: { trigger: section, start: 'top 80%', toggleActions: 'play none none reverse' },
          }
        );
      });
    }, mainRef);
    return () => ctx.revert();
  }, []);

  // Install prompt after 6 seconds
  useEffect(() => {
    const t = setTimeout(() => setShowInstallPrompt(true), 6000);
    return () => clearTimeout(t);
  }, []);

  // Scroll-to-top button
  useEffect(() => {
    const fn = () => setShowScrollTop(window.scrollY > 500);
    window.addEventListener('scroll', fn, { passive: true });
    return () => window.removeEventListener('scroll', fn);
  }, []);

  const handleLogout = () => {
    setUser(null);
    toast.success('Logged out. See you soon!');
  };

  const handleCtaSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    if (ctaEmail && ctaEmail.includes('@')) {
      setShowRegister(true);
    } else {
      toast.error('Please enter a valid email address.');
    }
  };

  return (
    <div ref={mainRef} className="min-h-screen bg-navy-primary text-white overflow-x-hidden">

      <Navigation
        user={user}
        onLogout={handleLogout}
        onLoginClick={() => setShowLogin(true)}
        onRegisterClick={() => setShowRegister(true)}
      />

      {/* ── Hero ── */}
      <section className="relative min-h-screen flex flex-col items-center justify-center overflow-hidden">
        <div className="absolute inset-0">
          <img src="/hero_city.jpg" alt="" className="w-full h-full object-cover opacity-60" aria-hidden="true" />
          <div className="absolute inset-0 bg-gradient-to-b from-navy-primary/80 via-navy-primary/50 to-navy-primary" />
        </div>

        {/* Decorative SVG lines */}
        <svg className="absolute inset-0 w-full h-full pointer-events-none opacity-40" style={{ zIndex: 2 }} aria-hidden="true">
          <defs>
            <linearGradient id="lineGradient" x1="0%" y1="0%" x2="100%" y2="0%">
              <stop offset="0%"   stopColor="#00F0FF" stopOpacity="0" />
              <stop offset="50%"  stopColor="#00F0FF" stopOpacity="0.5" />
              <stop offset="100%" stopColor="#00F0FF" stopOpacity="0" />
            </linearGradient>
          </defs>
          <path d="M0,300 Q400,200 800,350 T1600,300" fill="none" stroke="url(#lineGradient)" strokeWidth="1" className="animate-pulse-slow" />
          <path d="M200,500 Q600,400 1000,450 T1800,400" fill="none" stroke="url(#lineGradient)" strokeWidth="1" className="animate-pulse-slow" style={{ animationDelay: '1s' }} />
        </svg>

        {/* Hero content */}
        <div className="relative z-10 text-center px-4 max-w-5xl mx-auto pt-20 pb-8">
          <div className="flex justify-between mb-8 hero-stats">
            <span className="font-mono text-xs uppercase tracking-[0.18em] text-cyan">ENCRYPTED</span>
            <span className="font-mono text-xs uppercase tracking-[0.18em] text-cyan">NO LOGS</span>
          </div>

          <h1 className="hero-headline font-orbitron text-4xl sm:text-5xl md:text-6xl lg:text-7xl font-bold uppercase tracking-[0.08em] mb-6">
            Browse at <span className="text-gradient">Lightspeed</span>
          </h1>
          <p className="hero-subheadline text-lg sm:text-xl text-white/70 max-w-2xl mx-auto mb-10">
            The VPN built for speed, privacy, and zero compromise.
            Experience ultra-low latency with military-grade encryption.
          </p>

          <div className="hero-cta flex flex-col sm:flex-row gap-4 justify-center mb-16">
            <Button
              size="lg"
              onClick={() => setShowRegister(true)}
              className="bg-cyan text-navy-primary hover:bg-cyan-dark font-semibold text-lg px-8 py-6 rounded-xl shadow-glow"
            >
              <Zap size={20} className="mr-2" />
              Get GeminiVPN
            </Button>
            <Button
              size="lg"
              variant="outline"
              onClick={() => document.getElementById('pricing')?.scrollIntoView({ behavior: 'smooth' })}
              className="border-white/20 text-white hover:bg-white/10 text-lg px-8 py-6 rounded-xl"
            >
              View Plans
            </Button>
          </div>

          <div className="hero-stats flex flex-wrap justify-center gap-8 sm:gap-16">
            {[
              { value: '9', label: 'ms Latency' },
              { value: '10G', label: 'Server Speed' },
              { value: '60+', label: 'Countries' },
            ].map((s) => (
              <div key={s.label} className="text-center">
                <p className="font-orbitron text-3xl sm:text-4xl font-bold text-cyan">{s.value}</p>
                <p className="font-mono text-xs uppercase tracking-[0.18em] text-white/50 mt-1">{s.label}</p>
              </div>
            ))}
          </div>
        </div>

        {/* VPN Dashboard */}
        <div className="relative z-10 w-full max-w-md mx-auto px-4 pb-12 lg:absolute lg:bottom-8 lg:right-8 lg:max-w-sm lg:pb-0">
          <VPNDashboard user={user} onActivate={() => setShowRegister(true)} />
        </div>
      </section>

      {/* ── Speed Feature ── */}
      <section id="features" className="scroll-section relative min-h-screen flex items-center py-20">
        <div className="absolute inset-0">
          <img src="/tunnel_road.jpg" alt="" className="w-full h-full object-cover opacity-40" aria-hidden="true" />
          <div className="absolute inset-0 bg-gradient-to-r from-navy-primary via-navy-primary/80 to-transparent" />
        </div>
        <div className="relative z-10 w-full px-4 sm:px-6 lg:px-12">
          <div className="max-w-xl">
            <span className="font-mono text-xs uppercase tracking-[0.18em] text-cyan mb-4 block">Performance</span>
            <h2 className="font-orbitron text-4xl sm:text-5xl lg:text-6xl font-bold uppercase tracking-wider mb-6">
              Warp Speed
            </h2>
            <p className="text-lg text-white/70 mb-8">
              A global network tuned for low latency and high throughput—so your stream,
              game, and download never stutter.
            </p>
            <div className="flex flex-wrap gap-4">
              {[
                { icon: Zap,  label: '10 Gbps' },
                { icon: Wifi, label: '9 ms'     },
                { icon: Lock, label: 'WireGuard®' },
              ].map(({ icon: Icon, label }) => (
                <div key={label} className="flex items-center gap-2 px-4 py-2 bg-navy-secondary/80 rounded-full border border-white/10">
                  <Icon size={16} className="text-cyan" />
                  <span className="text-sm">{label}</span>
                </div>
              ))}
            </div>
          </div>
        </div>
      </section>

      {/* ── Privacy ── */}
      <section className="scroll-section relative min-h-screen flex items-center py-20">
        <div className="absolute inset-0">
          <img src="/hooded_figure.jpg" alt="" className="w-full h-full object-cover opacity-40" aria-hidden="true" />
          <div className="absolute inset-0 bg-gradient-to-l from-navy-primary via-navy-primary/80 to-transparent" />
        </div>
        <div className="relative z-10 w-full px-4 sm:px-6 lg:px-12">
          <div className="max-w-xl ml-auto text-right">
            <span className="font-mono text-xs uppercase tracking-[0.18em] text-cyan mb-4 block">Privacy</span>
            <h2 className="font-orbitron text-4xl sm:text-5xl lg:text-6xl font-bold uppercase tracking-wider mb-6">
              True Privacy
            </h2>
            <p className="text-lg text-white/70 mb-8">
              We don't track what you do. No traffic logs, no session logs, no compromise.
              Your data belongs to you alone.
            </p>
            <div className="flex flex-wrap justify-end gap-4">
              {['No logs', 'Kill switch', 'DNS leak protection'].map((f) => (
                <div key={f} className="flex items-center gap-2 px-4 py-2 bg-navy-secondary/80 rounded-full border border-white/10">
                  <Check size={16} className="text-cyan" />
                  <span className="text-sm">{f}</span>
                </div>
              ))}
            </div>
          </div>
        </div>
      </section>

      {/* ── Global Servers ── */}
      <section id="servers" className="scroll-section relative min-h-screen flex items-center py-20">
        <div className="absolute inset-0">
          <img src="/server_room.jpg" alt="" className="w-full h-full object-cover opacity-40" aria-hidden="true" />
          <div className="absolute inset-0 bg-gradient-to-b from-navy-primary via-navy-primary/70 to-navy-primary" />
        </div>
        <div className="relative z-10 w-full px-4 sm:px-6 lg:px-12 text-center">
          <span className="font-mono text-xs uppercase tracking-[0.18em] text-cyan mb-4 block">Network</span>
          <h2 className="font-orbitron text-4xl sm:text-5xl lg:text-6xl font-bold uppercase tracking-wider mb-16">
            Global Servers
          </h2>
          <div className="grid grid-cols-1 sm:grid-cols-3 gap-8 max-w-4xl mx-auto mb-12">
            {[{ value: '100+', label: 'Cities' }, { value: '60+', label: 'Countries' }, { value: '10G', label: 'Per Node' }].map((s) => (
              <div key={s.label} className="p-8 bg-navy-secondary/80 rounded-2xl border border-white/10">
                <p className="font-orbitron text-5xl sm:text-6xl font-bold text-cyan mb-2">{s.value}</p>
                <p className="font-mono text-sm uppercase tracking-[0.18em] text-white/50">{s.label}</p>
              </div>
            ))}
          </div>
          {/* Live server list preview */}
          <div className="max-w-2xl mx-auto grid grid-cols-2 sm:grid-cols-5 gap-2">
            {SERVER_LOCATIONS.slice(0, 10).map((s) => (
              <div key={s.id} className="flex items-center gap-2 px-3 py-2 bg-navy-secondary/60 rounded-xl border border-white/5 text-sm">
                <span>{s.flag}</span>
                <span className="text-white/70 truncate">{s.city}</span>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* ── Streaming ── */}
      <section className="scroll-section relative min-h-screen flex items-center py-20">
        <div className="absolute inset-0">
          <img src="/neon_corridor.jpg" alt="" className="w-full h-full object-cover opacity-40" aria-hidden="true" />
          <div className="absolute inset-0 bg-gradient-to-r from-navy-primary via-navy-primary/80 to-transparent" />
        </div>
        <div className="relative z-10 w-full px-4 sm:px-6 lg:px-12">
          <div className="max-w-xl">
            <span className="font-mono text-xs uppercase tracking-[0.18em] text-cyan mb-4 block">Streaming</span>
            <h2 className="font-orbitron text-4xl sm:text-5xl lg:text-6xl font-bold uppercase tracking-wider mb-6">
              Stream Without Borders
            </h2>
            <p className="text-lg text-white/70 mb-8">
              Watch what you want, where you want. Optimized paths for HD and 4K without buffering.
            </p>
            <div className="inline-flex items-center gap-3 px-6 py-4 bg-navy-secondary/80 rounded-2xl border border-cyan/20">
              <div className="w-10 h-10 rounded-full bg-cyan/20 border-2 border-cyan flex items-center justify-center">
                <Play size={16} className="text-cyan ml-0.5" fill="#00F0FF" />
              </div>
              <div className="text-left">
                <p className="font-orbitron font-bold text-cyan text-sm">UNBLOCK ALL</p>
                <p className="text-xs text-white/50">Netflix, Hulu, BBC iPlayer & more</p>
              </div>
            </div>
          </div>
        </div>
      </section>

      {/* ── Security ── */}
      <section className="scroll-section relative min-h-screen flex items-center py-20">
        <div className="absolute inset-0">
          <img src="/server_lock.jpg" alt="" className="w-full h-full object-cover opacity-40" aria-hidden="true" />
          <div className="absolute inset-0 bg-gradient-to-t from-navy-primary via-navy-primary/70 to-navy-primary/50" />
        </div>
        <div className="relative z-10 w-full px-4 sm:px-6 lg:px-12 text-center">
          <span className="font-mono text-xs uppercase tracking-[0.18em] text-cyan mb-4 block">Security</span>
          <h2 className="font-orbitron text-4xl sm:text-5xl lg:text-6xl font-bold uppercase tracking-wider mb-6">
            Lock Down Your Data
          </h2>
          <p className="text-lg text-white/70 max-w-2xl mx-auto mb-8">
            AES-256 encryption, WireGuard® protocol, and a kill switch that actually works.
            Your connection is fortress-grade secure.
          </p>
          <div className="w-20 h-20 mx-auto rounded-full bg-cyan/20 border-2 border-cyan flex items-center justify-center animate-float">
            <Lock size={32} className="text-cyan" />
          </div>
        </div>
      </section>

      {/* ── Multi-Device ── */}
      <section className="scroll-section relative min-h-screen flex items-center py-20">
        <div className="absolute inset-0">
          <img src="/devices_city.jpg" alt="" className="w-full h-full object-cover opacity-40" aria-hidden="true" />
          <div className="absolute inset-0 bg-gradient-to-l from-navy-primary via-navy-primary/80 to-transparent" />
        </div>
        <div className="relative z-10 w-full px-4 sm:px-6 lg:px-12">
          <div className="max-w-xl ml-auto text-right">
            <span className="font-mono text-xs uppercase tracking-[0.18em] text-cyan mb-4 block">Multi-Device</span>
            <h2 className="font-orbitron text-4xl sm:text-5xl lg:text-6xl font-bold uppercase tracking-wider mb-6">
              One Account, Every Device
            </h2>
            <p className="text-lg text-white/70 mb-8">
              Connect up to 10 devices at once. Apps for iOS, Android, Windows, macOS, and more.
            </p>
            <div className="flex justify-end gap-4">
              {[Smartphone, Monitor, Tablet].map((Icon, i) => (
                <div key={i} className="w-14 h-14 rounded-xl bg-navy-secondary/80 border border-white/10 flex items-center justify-center">
                  <Icon size={24} className="text-cyan" />
                </div>
              ))}
            </div>
          </div>
        </div>
      </section>

      {/* ── Support ── */}
      <section id="support" className="scroll-section relative min-h-screen flex items-center py-20">
        <div className="absolute inset-0">
          <img src="/headset_support.jpg" alt="" className="w-full h-full object-cover opacity-40" aria-hidden="true" />
          <div className="absolute inset-0 bg-gradient-to-r from-navy-primary via-navy-primary/80 to-transparent" />
        </div>
        <div className="relative z-10 w-full px-4 sm:px-6 lg:px-12">
          <div className="max-w-xl">
            <span className="font-mono text-xs uppercase tracking-[0.18em] text-cyan mb-4 block">Support</span>
            <h2 className="font-orbitron text-4xl sm:text-5xl lg:text-6xl font-bold uppercase tracking-wider mb-6">
              Real Support, Real Humans
            </h2>
            <p className="text-lg text-white/70 mb-8">
              Stuck? Our team is here around the clock with clear answers—no bots, no runarounds.
            </p>
            <div className="flex gap-4">
              <div className="flex items-center justify-center w-24 h-24 rounded-full bg-cyan/20 border-2 border-cyan">
                <span className="font-orbitron font-bold text-cyan text-2xl">24/7</span>
              </div>
              <div className="flex flex-col gap-3 justify-center">
                <button
                  onClick={() => toast.info('Support chat coming soon!')}
                  className="px-4 py-2 bg-cyan/20 border border-cyan/30 rounded-lg text-cyan text-sm hover:bg-cyan/30 transition-colors text-left"
                >
                  💬 Live Chat
                </button>
                <button
                  onClick={() => toast.info('Email: support@geminivpn.access.ly')}
                  className="px-4 py-2 bg-white/5 border border-white/10 rounded-lg text-white/70 text-sm hover:bg-white/10 transition-colors text-left"
                >
                  ✉️ Email Support
                </button>
              </div>
            </div>
          </div>
        </div>
      </section>

      {/* ── Pricing ── */}
      <section id="pricing" className="scroll-section py-20 lg:py-32 bg-navy-secondary">
        <div className="w-full px-4 sm:px-6 lg:px-12">
          <div className="text-center mb-16">
            <h2 className="font-orbitron text-4xl sm:text-5xl font-bold uppercase tracking-wider mb-4">
              Choose Your Plan
            </h2>
            <p className="text-white/60">No contracts. Cancel anytime. 30-day money-back guarantee.</p>
          </div>
          <div className="grid grid-cols-1 md:grid-cols-3 gap-6 max-w-5xl mx-auto">
            {PRICING_PLANS.map((plan) => (
              <div
                key={plan.name}
                className={`p-8 rounded-2xl border ${
                  plan.highlighted
                    ? 'bg-navy-primary border-cyan shadow-glow'
                    : 'bg-navy-primary/50 border-white/10'
                }`}
              >
                {plan.highlighted && (
                  <span className="inline-block px-3 py-1 bg-cyan/20 text-cyan text-xs font-mono uppercase tracking-wider rounded-full mb-4">
                    Most Popular
                  </span>
                )}
                <h3 className="font-orbitron text-xl font-bold mb-2">{plan.name}</h3>
                <div className="flex items-baseline gap-1 mb-2">
                  <span className="font-orbitron text-4xl font-bold text-cyan">{plan.price}</span>
                  <span className="text-white/50">{plan.period}</span>
                </div>
                <p className="text-sm text-white/50 mb-6">{plan.billed}</p>
                <ul className="space-y-3 mb-8">
                  {plan.features.map((f) => (
                    <li key={f} className="flex items-center gap-2 text-sm">
                      <Check size={16} className="text-cyan flex-shrink-0" />
                      {f}
                    </li>
                  ))}
                </ul>
                <Button
                  className={`w-full ${
                    plan.highlighted
                      ? 'bg-cyan text-navy-primary hover:bg-cyan-dark'
                      : 'bg-white/10 text-white hover:bg-white/20'
                  } font-semibold`}
                  onClick={() => setShowRegister(true)}
                >
                  {plan.cta}
                </Button>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* ── Download ── */}
      <section id="download" className="scroll-section py-20 lg:py-32">
        <div className="w-full px-4 sm:px-6 lg:px-12">
          <div className="max-w-4xl mx-auto">
            <div className="text-center mb-12">
              <h2 className="font-orbitron text-4xl sm:text-5xl font-bold uppercase tracking-wider mb-4">
                Download GeminiVPN
              </h2>
              <p className="text-white/60">Get the app for your device. Sign in once, connect everywhere.</p>
            </div>
            <div className="grid grid-cols-2 sm:grid-cols-3 gap-4">
              {[
                { name: 'iOS',     icon: Apple,      badge: 'App Store' },
                { name: 'Android', icon: Smartphone,  badge: 'Play Store' },
                { name: 'Windows', icon: Monitor,     badge: 'Download .exe' },
                { name: 'macOS',   icon: Apple,       badge: 'Download .dmg' },
                { name: 'Linux',   icon: Server,      badge: 'Download .deb' },
                { name: 'Router',  icon: Wifi,        badge: 'Setup Guide' },
              ].map((p) => (
                <button
                  key={p.name}
                  className="flex flex-col items-center gap-3 p-6 bg-navy-secondary/50 rounded-2xl border border-white/10 hover:border-cyan/50 hover:bg-navy-secondary transition-all group"
                  onClick={() => toast.info(`${p.name}: ${p.badge} — coming soon!`)}
                  aria-label={`Download for ${p.name}`}
                >
                  <p.icon size={32} className="text-white/50 group-hover:text-cyan transition-colors" />
                  <span className="font-medium">{p.name}</span>
                  <span className="text-xs text-white/40 group-hover:text-cyan/60 transition-colors">{p.badge}</span>
                </button>
              ))}
            </div>
          </div>
        </div>
      </section>

      {/* ── FAQ ── */}
      <section className="scroll-section py-20 lg:py-32 bg-navy-secondary">
        <div className="w-full px-4 sm:px-6 lg:px-12">
          <div className="max-w-3xl mx-auto">
            <h2 className="font-orbitron text-4xl sm:text-5xl font-bold uppercase tracking-wider text-center mb-12">
              Frequently Asked
            </h2>
            <Accordion type="single" collapsible className="space-y-4">
              {FAQ_ITEMS.map((item, index) => (
                <AccordionItem
                  key={index}
                  value={`item-${index}`}
                  className="bg-navy-primary rounded-xl border border-white/10 px-6"
                >
                  <AccordionTrigger className="text-left hover:no-underline py-4 font-medium">
                    {item.question}
                  </AccordionTrigger>
                  <AccordionContent className="text-white/60 pb-4 leading-relaxed">
                    {item.answer}
                  </AccordionContent>
                </AccordionItem>
              ))}
            </Accordion>
          </div>
        </div>
      </section>

      {/* ── Final CTA ── */}
      <section className="scroll-section relative py-20 lg:py-32">
        <div className="absolute inset-0">
          <img src="/final_city.jpg" alt="" className="w-full h-full object-cover opacity-30" aria-hidden="true" />
          <div className="absolute inset-0 bg-gradient-to-t from-navy-primary via-navy-primary/90 to-navy-primary/70" />
        </div>
        <div className="relative z-10 w-full px-4 sm:px-6 lg:px-12">
          <div className="max-w-xl mx-auto text-center">
            <h2 className="font-orbitron text-4xl sm:text-5xl font-bold uppercase tracking-wider mb-4">
              Join the Network
            </h2>
            <p className="text-white/60 mb-8">
              Enter your email to create an account and start your first connection.
            </p>
            <form onSubmit={handleCtaSubmit} className="flex flex-col sm:flex-row gap-4">
              <Input
                type="email"
                placeholder="you@example.com"
                value={ctaEmail}
                onChange={(e) => setCtaEmail(e.target.value)}
                className="flex-1 bg-navy-primary border-white/10 text-white placeholder:text-white/30 h-12"
                aria-label="Email address"
              />
              <Button
                type="submit"
                className="bg-cyan text-navy-primary hover:bg-cyan-dark font-semibold h-12 px-8"
              >
                Create Account
              </Button>
            </form>
            <p className="text-xs text-white/40 mt-4">
              By signing up, you agree to the{' '}
              <button onClick={() => toast.info('Terms of Service — coming soon')} className="underline hover:text-white/70">Terms of Service</button>
              {' '}and{' '}
              <button onClick={() => toast.info('Privacy Policy — coming soon')} className="underline hover:text-white/70">Privacy Policy</button>.
            </p>
          </div>
        </div>
      </section>

      {/* ── Footer ── */}
      <footer className="bg-navy-secondary border-t border-white/5 py-12" role="contentinfo">
        <div className="w-full px-4 sm:px-6 lg:px-12">
          <div className="grid grid-cols-2 md:grid-cols-4 gap-8 max-w-5xl mx-auto mb-12">
            <div className="col-span-2 md:col-span-1">
              <a
                href="#"
                onClick={(e) => { e.preventDefault(); window.scrollTo({ top: 0, behavior: 'smooth' }); }}
                className="flex items-center gap-2 mb-4"
                aria-label="GeminiVPN Home"
              >
                <img src="/geminivpn-logo.png" alt="GeminiVPN" className="w-8 h-8" />
                <span className="font-orbitron font-bold tracking-wider">
                  GEMINI<span className="text-cyan">VPN</span>
                </span>
              </a>
              <p className="text-sm text-white/50">Browse at lightspeed. Stay invisible.</p>
            </div>

            <div>
              <h3 className="font-mono text-xs uppercase tracking-[0.18em] text-white/50 mb-4">Product</h3>
              <ul className="space-y-2">
                {[
                  { label: 'Features', id: 'features' },
                  { label: 'Servers',  id: 'servers'  },
                  { label: 'Pricing',  id: 'pricing'  },
                  { label: 'Download', id: 'download' },
                ].map(({ label, id }) => (
                  <li key={id}>
                    <button
                      onClick={() => document.getElementById(id)?.scrollIntoView({ behavior: 'smooth' })}
                      className="text-sm text-white/70 hover:text-cyan transition-colors"
                    >
                      {label}
                    </button>
                  </li>
                ))}
              </ul>
            </div>

            <div>
              <h3 className="font-mono text-xs uppercase tracking-[0.18em] text-white/50 mb-4">Support</h3>
              <ul className="space-y-2">
                {[
                  { label: 'Help Center', msg: 'Help Center coming soon!'             },
                  { label: 'Contact',     msg: 'Email: support@geminivpn.access.ly'  },
                  { label: 'Status',      msg: 'Status page coming soon!'             },
                ].map(({ label, msg }) => (
                  <li key={label}>
                    <button
                      onClick={() => toast.info(msg)}
                      className="text-sm text-white/70 hover:text-cyan transition-colors"
                    >
                      {label}
                    </button>
                  </li>
                ))}
              </ul>
            </div>

            <div>
              <h3 className="font-mono text-xs uppercase tracking-[0.18em] text-white/50 mb-4">Legal</h3>
              <ul className="space-y-2">
                {[
                  { label: 'Privacy',      msg: 'Privacy Policy coming soon!'      },
                  { label: 'Terms',        msg: 'Terms of Service coming soon!'    },
                  { label: 'Transparency', msg: 'Transparency Report coming soon!' },
                ].map(({ label, msg }) => (
                  <li key={label}>
                    <button
                      onClick={() => toast.info(msg)}
                      className="text-sm text-white/70 hover:text-cyan transition-colors"
                    >
                      {label}
                    </button>
                  </li>
                ))}
              </ul>
            </div>
          </div>

          <div className="text-center pt-8 border-t border-white/5">
            <p className="text-sm text-white/40">
              © 2026 GeminiVPN · geminivpn.access.ly · All rights reserved.
            </p>
          </div>
        </div>
      </footer>

      {/* ── Modals & overlays ── */}
      <AuthDialog
        isOpen={showLogin}
        onClose={() => setShowLogin(false)}
        type="login"
        onSuccess={setUser}
      />
      <AuthDialog
        isOpen={showRegister}
        onClose={() => setShowRegister(false)}
        type="register"
        onSuccess={setUser}
      />

      {/* Scroll-to-top (our own button — not Kimi) */}
      <ScrollToTopButton isVisible={showScrollTop} />

      {/* PWA install prompt */}
      <InstallPrompt isVisible={showInstallPrompt} onClose={() => setShowInstallPrompt(false)} />
    </div>
  );
}

export default App;
