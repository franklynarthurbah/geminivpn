/**
 * GeminiVPN — Privacy Policy
 */
import React from 'react';
import { ArrowLeft, Shield } from 'lucide-react';

interface PrivacyPolicyProps { onBack: () => void; }

const Section = ({ id, title, children }: { id: string; title: string; children: React.ReactNode }) => (
  <div id={id} className="mb-10">
    <h2 className="font-orbitron font-bold text-xl sm:text-2xl mb-4 text-white">{title}</h2>
    <div className="space-y-3 text-white/65 leading-relaxed text-[15px]">{children}</div>
  </div>
);

const toc = [
  ['data-collection',    'Information We Collect'],
  ['data-use',           'How We Use Your Data'],
  ['no-logs',            'No-Logs Policy'],
  ['data-sharing',       'Data Sharing'],
  ['security',           'Security'],
  ['data-retention',     'Data Retention'],
  ['your-rights',        'Your Rights'],
  ['cookies',            'Cookies'],
  ['children',           "Children's Privacy"],
  ['changes',            'Policy Changes'],
  ['contact',            'Contact'],
];

export default function PrivacyPolicy({ onBack }: PrivacyPolicyProps) {
  return (
    <div className="min-h-screen bg-navy-primary text-white">
      {/* Header */}
      <div className="sticky top-0 z-50 bg-navy-primary/90 backdrop-blur-md border-b border-white/5">
        <div className="max-w-4xl mx-auto px-4 sm:px-6 h-16 flex items-center gap-4">
          <button onClick={onBack} className="p-2 hover:bg-white/5 rounded-lg transition-colors" aria-label="Go back">
            <ArrowLeft size={20} className="text-white/70" />
          </button>
          <div className="flex items-center gap-3">
            <Shield size={20} className="text-cyan" />
            <h1 className="font-orbitron font-bold tracking-wider text-sm sm:text-base">PRIVACY POLICY</h1>
          </div>
          <span className="ml-auto font-mono text-xs text-white/30">Effective: 1 January 2026</span>
        </div>
      </div>

      <div className="max-w-4xl mx-auto px-4 sm:px-6 py-10">
        {/* Lead */}
        <div className="mb-10 p-6 bg-cyan/5 border border-cyan/20 rounded-2xl">
          <p className="text-sm leading-relaxed text-white/70">
            GeminiVPN ("we", "us", "our") is committed to protecting your privacy. This Privacy Policy explains
            what personal data we collect, why we collect it, and how we handle it. By using our services, you
            accept this policy. If you do not agree, please discontinue use.
          </p>
        </div>

        {/* Table of Contents */}
        <div className="mb-10 p-5 bg-navy-secondary rounded-xl border border-white/10">
          <p className="font-mono text-xs uppercase tracking-[0.18em] text-white/40 mb-3">Table of Contents</p>
          <ol className="grid grid-cols-1 sm:grid-cols-2 gap-y-1.5 gap-x-4">
            {toc.map(([id, label], i) => (
              <li key={id}>
                <a href={`#${id}`} className="text-sm text-white/60 hover:text-cyan transition-colors">
                  <span className="font-mono text-white/20 mr-2">{String(i + 1).padStart(2, '0')}.</span>{label}
                </a>
              </li>
            ))}
          </ol>
        </div>

        {/* Sections */}
        <Section id="data-collection" title="1. Information We Collect">
          <p><strong className="text-white">Account Data:</strong> When you register, we collect your email address, encrypted password (bcrypt, 12 rounds), and optionally your name. This data is stored exclusively in our SQLite database hosted on our private server (167.172.96.225). We do not use external databases or data brokers.</p>
          <p><strong className="text-white">Subscription & Payment Records:</strong> We store a tokenised reference to your payment (e.g. a Stripe charge ID, Square payment ID, or Paddle transaction ID). We never store full card numbers, CVVs, or bank account details. Actual payment processing is handled by our PCI-DSS-certified partners.</p>
          <p><strong className="text-white">VPN Configuration Data:</strong> WireGuard® public keys and assigned virtual IP addresses for your devices. These are required to route your encrypted tunnel. Private keys are generated on-device and never transmitted to our servers.</p>
          <p><strong className="text-white">Session Tokens:</strong> JWT access and refresh tokens stored in your browser's localStorage. These are short-lived (access: 15 min; refresh: 7 days) and invalidated on logout.</p>
          <p><strong className="text-white">We do NOT collect:</strong> Your IP address during a VPN session, DNS queries, browsing history, connection timestamps, bandwidth consumption, or any content you transmit through the tunnel.</p>
        </Section>

        <Section id="data-use" title="2. How We Use Your Data">
          <p>We use your data solely for the following legitimate purposes:</p>
          <p>• <strong className="text-white">Account management:</strong> Creating and authenticating your account, issuing subscription access.</p>
          <p>• <strong className="text-white">Service delivery:</strong> Provisioning WireGuard® tunnels, assigning server IPs, enabling device connections.</p>
          <p>• <strong className="text-white">Billing:</strong> Processing payments, issuing receipts, handling refund requests.</p>
          <p>• <strong className="text-white">Support:</strong> Responding to your inquiries. We only access your account data when you report an issue.</p>
          <p>• <strong className="text-white">Legal compliance:</strong> Retaining financial transaction records as required by applicable tax and financial regulations.</p>
          <p>We do not use your data for advertising, profiling, machine learning training, or any purpose not stated above.</p>
        </Section>

        <Section id="no-logs" title="3. No-Logs Policy">
          <p>GeminiVPN operates under a strict <strong className="text-white">zero-logs policy</strong> with respect to VPN activity. Specifically:</p>
          <p>• We do not log originating IP addresses during VPN sessions.</p>
          <p>• We do not log outbound IP addresses (exit IPs) associated with a user.</p>
          <p>• We do not log DNS queries made through our resolvers.</p>
          <p>• We do not log connection timestamps, session durations, or bandwidth transferred per user.</p>
          <p>• We do not log application or website usage.</p>
          <p>This policy is enforced at the infrastructure level. Our WireGuard® server configurations are explicitly designed to prevent any per-user connection logging. We cannot produce VPN activity logs for any user because we do not create or retain them.</p>
        </Section>

        <Section id="data-sharing" title="4. Data Sharing">
          <p>We do not sell, rent, or trade your personal data to any third party.</p>
          <p><strong className="text-white">Payment processors:</strong> We share only the minimum necessary data with Stripe, Square, Paddle, or Coinbase Commerce to process your transaction. These processors have their own privacy policies and are independently PCI-DSS compliant.</p>
          <p><strong className="text-white">Legal requirements:</strong> We may disclose information if compelled by a valid, lawful court order under the jurisdiction in which we operate. Because we retain no VPN activity logs, any such order would yield only account registration data and payment records — not browsing history or connection activity.</p>
          <p><strong className="text-white">Business transfers:</strong> If GeminiVPN is acquired or merged, user data may be transferred as part of that transaction. We will notify affected users 30 days in advance and offer account deletion prior to transfer.</p>
        </Section>

        <Section id="security" title="5. Security">
          <p>We implement industry-standard security measures to protect your data:</p>
          <p>• All data in transit is encrypted via TLS 1.2/1.3 (HTTPS enforced by nginx with HSTS).</p>
          <p>• Passwords are hashed using bcrypt with a cost factor of 12 — never stored in plaintext.</p>
          <p>• The SQLite database is isolated within a private Docker network and is not exposed to the public internet.</p>
          <p>• Server hardening includes UFW firewall rules, fail2ban brute-force protection, and automatic security updates.</p>
          <p>• JWT secrets are auto-generated 256-bit random values unique to each deployment.</p>
          <p>Despite these measures, no system is 100% immune to breaches. If a breach affecting your personal data occurs, we will notify you within 72 hours of discovery.</p>
        </Section>

        <Section id="data-retention" title="6. Data Retention">
          <p>• <strong className="text-white">Active accounts:</strong> Data retained for the duration of your account.</p>
          <p>• <strong className="text-white">Deleted accounts:</strong> Personal data (name, email, VPN keys) purged within 30 days. Payment transaction references retained for up to 7 years per financial regulations.</p>
          <p>• <strong className="text-white">Session tokens:</strong> Automatically expired and invalidated (access tokens: 15 minutes; refresh tokens: 7 days).</p>
          <p>• <strong className="text-white">VPN activity logs:</strong> None retained — not generated at all.</p>
        </Section>

        <Section id="your-rights" title="7. Your Rights">
          <p>Depending on your jurisdiction, you may have the following rights:</p>
          <p>• <strong className="text-white">Access:</strong> Request a copy of all personal data we hold about you.</p>
          <p>• <strong className="text-white">Rectification:</strong> Correct inaccurate data in your account settings or by contacting support.</p>
          <p>• <strong className="text-white">Erasure:</strong> Request deletion of your account and associated data (subject to legal retention requirements).</p>
          <p>• <strong className="text-white">Portability:</strong> Receive your data in a structured, machine-readable format.</p>
          <p>• <strong className="text-white">Objection:</strong> Object to processing under legitimate interest grounds.</p>
          <p>To exercise any of these rights, contact us at <strong className="text-cyan">support@geminivpn.zapto.org</strong> with your registered email address. We will respond within 30 days.</p>
        </Section>

        <Section id="cookies" title="8. Cookies">
          <p>The GeminiVPN web interface uses <strong className="text-white">no third-party cookies</strong>. We do not use advertising trackers, analytics platforms (Google Analytics, Hotjar, etc.), or social media pixels.</p>
          <p>Authentication tokens are stored in your browser's <code className="text-cyan font-mono text-xs px-1 py-0.5 bg-white/5 rounded">localStorage</code> — not cookies — and are cleared on logout. These do not persist across browsers or devices.</p>
        </Section>

        <Section id="children" title="9. Children's Privacy">
          <p>GeminiVPN services are not directed at persons under the age of 16. We do not knowingly collect personal data from children. If you believe we have inadvertently collected data from a minor, please contact us immediately and we will delete it promptly.</p>
        </Section>

        <Section id="changes" title="10. Policy Changes">
          <p>We may update this Privacy Policy to reflect changes in our practices or legal requirements. Material changes will be communicated via email to registered users at least 14 days before they take effect. Continued use of the service after changes constitutes acceptance of the updated policy.</p>
          <p>The current version of this policy is always available at <strong className="text-cyan">geminivpn.zapto.org</strong>. Previous versions are retained in our transparency archive.</p>
        </Section>

        <Section id="contact" title="11. Contact">
          <p>For privacy-related inquiries, data requests, or to report a security concern:</p>
          <p>• <strong className="text-white">Email:</strong> <a href="mailto:support@geminivpn.zapto.org" className="text-cyan hover:underline">support@geminivpn.zapto.org</a></p>
          <p>• <strong className="text-white">WhatsApp:</strong> <a href="https://wa.me/905368895622" target="_blank" rel="noopener noreferrer" className="text-cyan hover:underline">+90 536 889 5622</a></p>
          <p>• <strong className="text-white">Website:</strong> <a href="https://geminivpn.zapto.org" className="text-cyan hover:underline">geminivpn.zapto.org</a></p>
        </Section>

        <div className="mt-12 pt-6 border-t border-white/5 text-center">
          <p className="font-mono text-xs text-white/20">© 2026 GeminiVPN · Last revised 1 January 2026 · Version 1.0</p>
        </div>
      </div>
    </div>
  );
}
