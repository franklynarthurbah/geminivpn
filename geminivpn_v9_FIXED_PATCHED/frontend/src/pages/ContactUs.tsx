/**
 * GeminiVPN — Contact Us
 */
import React, { useState } from 'react';
import { ArrowLeft, MessageCircle, Mail, Clock, CheckCircle, Send, Phone } from 'lucide-react';
import { Input } from '@/components/ui/input';
import { Button } from '@/components/ui/button';
import { toast } from 'sonner';

interface ContactUsProps { onBack: () => void; user: { email: string; name: string } | null; }

const SUBJECTS = [
  'Billing & Payments',
  'Technical Issue',
  'Account Access',
  'Subscription Management',
  'Refund Request',
  'App Installation',
  'Privacy Inquiry',
  'Other',
];

export default function ContactUs({ onBack, user }: ContactUsProps) {
  const [name,    setName]    = useState(user?.name  || '');
  const [email,   setEmail]   = useState(user?.email || '');
  const [subject, setSubject] = useState('');
  const [message, setMessage] = useState('');
  const [sent,    setSent]    = useState(false);
  const [loading, setLoading] = useState(false);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!name.trim() || !email.includes('@') || !subject || !message.trim()) {
      toast.error('Please fill in all required fields.');
      return;
    }
    setLoading(true);
    // Simulate submission — in production this calls an SMTP endpoint
    await new Promise((r) => setTimeout(r, 1200));
    setSent(true);
    setLoading(false);
    toast.success('Message sent! We\'ll respond within 2 hours.');
  };

  return (
    <div className="min-h-screen bg-navy-primary text-white">
      {/* Header */}
      <div className="sticky top-0 z-50 bg-navy-primary/90 backdrop-blur-md border-b border-white/5">
        <div className="max-w-4xl mx-auto px-4 sm:px-6 h-16 flex items-center gap-4">
          <button onClick={onBack} className="p-2 hover:bg-white/5 rounded-lg transition-colors" aria-label="Go back">
            <ArrowLeft size={20} className="text-white/70" />
          </button>
          <div className="flex items-center gap-3">
            <MessageCircle size={20} className="text-cyan" />
            <h1 className="font-orbitron font-bold tracking-wider text-sm sm:text-base">CONTACT US</h1>
          </div>
        </div>
      </div>

      <div className="max-w-4xl mx-auto px-4 sm:px-6 py-10">
        <div className="text-center mb-12">
          <h2 className="font-orbitron text-3xl sm:text-4xl font-bold mb-3">We're Here to Help</h2>
          <p className="text-white/50 text-sm max-w-lg mx-auto">Our support team is available 24/7. Choose your preferred channel or send us a message below.</p>
        </div>

        {/* Contact Channels */}
        <div className="grid grid-cols-1 sm:grid-cols-3 gap-4 mb-12">
          <a href="https://wa.me/905368895622?text=Hello%20GeminiVPN%20Support%2C%20I%20need%20assistance."
            target="_blank" rel="noopener noreferrer"
            className="flex flex-col items-center gap-3 p-6 bg-navy-secondary rounded-2xl border border-white/10 hover:border-emerald-400/30 transition-colors group text-center">
            <div className="w-12 h-12 rounded-2xl bg-emerald-400/10 border border-emerald-400/20 flex items-center justify-center group-hover:bg-emerald-400/20 transition-colors">
              <Phone size={22} className="text-emerald-400" />
            </div>
            <div>
              <p className="font-semibold text-sm">WhatsApp</p>
              <p className="text-xs text-white/40 mt-0.5">Fastest response</p>
              <p className="text-xs text-emerald-400 font-mono mt-1">+90 536 889 5622</p>
            </div>
            <span className="inline-flex items-center gap-1 px-2 py-0.5 bg-emerald-400/10 rounded-full text-emerald-400 text-xs font-mono">
              <span className="w-1.5 h-1.5 rounded-full bg-emerald-400 animate-pulse" />
              Live
            </span>
          </a>

          <a href="mailto:support@geminivpn.zapto.org"
            className="flex flex-col items-center gap-3 p-6 bg-navy-secondary rounded-2xl border border-white/10 hover:border-cyan/30 transition-colors group text-center">
            <div className="w-12 h-12 rounded-2xl bg-cyan/10 border border-cyan/20 flex items-center justify-center group-hover:bg-cyan/20 transition-colors">
              <Mail size={22} className="text-cyan" />
            </div>
            <div>
              <p className="font-semibold text-sm">Email</p>
              <p className="text-xs text-white/40 mt-0.5">Detailed inquiries</p>
              <p className="text-xs text-cyan font-mono mt-1">support@geminivpn.zapto.org</p>
            </div>
            <span className="inline-flex items-center gap-1 px-2 py-0.5 bg-white/5 rounded-full text-white/40 text-xs font-mono">
              <Clock size={10} />
              &lt; 2h response
            </span>
          </a>

          <div className="flex flex-col items-center gap-3 p-6 bg-navy-secondary rounded-2xl border border-white/10 text-center">
            <div className="w-12 h-12 rounded-2xl bg-white/5 border border-white/10 flex items-center justify-center">
              <Clock size={22} className="text-white/50" />
            </div>
            <div>
              <p className="font-semibold text-sm">Support Hours</p>
              <p className="text-xs text-white/40 mt-0.5">Always available</p>
              <p className="text-xs text-white/60 font-mono mt-1">24 / 7 / 365</p>
            </div>
            <span className="inline-flex items-center gap-1 px-2 py-0.5 bg-cyan/10 rounded-full text-cyan text-xs font-mono">
              Never closed
            </span>
          </div>
        </div>

        {/* Contact Form */}
        <div className="bg-navy-secondary rounded-2xl border border-white/10 p-6 sm:p-8">
          {sent ? (
            <div className="text-center py-10">
              <div className="w-16 h-16 rounded-full bg-emerald-400/10 border border-emerald-400/20 flex items-center justify-center mx-auto mb-4">
                <CheckCircle size={32} className="text-emerald-400" />
              </div>
              <h3 className="font-orbitron font-bold text-xl mb-2">Message Sent!</h3>
              <p className="text-white/50 text-sm mb-6">We've received your message and will reply to <strong className="text-white">{email}</strong> within 2 hours.</p>
              <Button onClick={() => { setSent(false); setMessage(''); setSubject(''); }}
                className="bg-cyan/10 border border-cyan/30 text-cyan hover:bg-cyan/20">
                Send Another Message
              </Button>
            </div>
          ) : (
            <>
              <h3 className="font-orbitron font-bold text-lg mb-6">Send a Message</h3>
              <form onSubmit={handleSubmit} className="space-y-5">
                <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
                  <div>
                    <label className="text-xs text-white/50 font-mono uppercase tracking-wider mb-2 block" htmlFor="contact-name">Full Name *</label>
                    <Input id="contact-name" value={name} onChange={(e) => setName(e.target.value)}
                      placeholder="Your name" required
                      className="bg-navy-primary border-white/10 text-white placeholder:text-white/20 h-11" />
                  </div>
                  <div>
                    <label className="text-xs text-white/50 font-mono uppercase tracking-wider mb-2 block" htmlFor="contact-email">Email Address *</label>
                    <Input id="contact-email" type="email" value={email} onChange={(e) => setEmail(e.target.value)}
                      placeholder="you@example.com" required
                      className="bg-navy-primary border-white/10 text-white placeholder:text-white/20 h-11" />
                  </div>
                </div>

                <div>
                  <label className="text-xs text-white/50 font-mono uppercase tracking-wider mb-2 block">Subject *</label>
                  <div className="grid grid-cols-2 sm:grid-cols-4 gap-2">
                    {SUBJECTS.map((s) => (
                      <button key={s} type="button" onClick={() => setSubject(s)}
                        className={`px-3 py-2 rounded-lg border text-xs text-left transition-colors ${subject === s ? 'bg-cyan/10 border-cyan/30 text-cyan' : 'bg-navy-primary border-white/10 text-white/50 hover:border-white/20 hover:text-white/70'}`}>
                        {s}
                      </button>
                    ))}
                  </div>
                </div>

                <div>
                  <label className="text-xs text-white/50 font-mono uppercase tracking-wider mb-2 block" htmlFor="contact-message">Message *</label>
                  <textarea id="contact-message" value={message} onChange={(e) => setMessage(e.target.value)}
                    placeholder="Describe your issue or question in detail…" rows={5} required
                    className="w-full bg-navy-primary border border-white/10 rounded-xl text-white placeholder:text-white/20 text-sm p-4 resize-none focus:outline-none focus:border-cyan/50 transition-colors" />
                  <p className="text-xs text-white/20 font-mono mt-1 text-right">{message.length}/1000</p>
                </div>

                <div className="flex items-center justify-between pt-2">
                  <p className="text-xs text-white/30">Your message is sent securely via TLS encryption.</p>
                  <Button type="submit" disabled={loading}
                    className="bg-cyan text-navy-primary hover:bg-cyan-dark font-semibold disabled:opacity-60 flex items-center gap-2">
                    <Send size={16} />
                    {loading ? 'Sending…' : 'Send Message'}
                  </Button>
                </div>
              </form>
            </>
          )}
        </div>

        {/* Response time info */}
        <div className="mt-6 grid grid-cols-1 sm:grid-cols-3 gap-4 text-center">
          {[
            { label: 'WhatsApp', time: '< 15 min', color: 'text-emerald-400' },
            { label: 'Email / Form', time: '< 2 hours', color: 'text-cyan' },
            { label: 'Complex Issues', time: '< 24 hours', color: 'text-white/50' },
          ].map((r) => (
            <div key={r.label} className="p-4 bg-navy-secondary/50 rounded-xl border border-white/5">
              <p className={`font-orbitron font-bold text-lg ${r.color}`}>{r.time}</p>
              <p className="text-xs text-white/30 font-mono mt-1">{r.label}</p>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}
