/**
 * GeminiVPN — Terms of Service
 */
import React from 'react';
import { ArrowLeft, FileText } from 'lucide-react';

interface TermsProps { onBack: () => void; }

const Section = ({ id, title, children }: { id: string; title: string; children: React.ReactNode }) => (
  <div id={id} className="mb-10">
    <h2 className="font-orbitron font-bold text-xl sm:text-2xl mb-4 text-white">{title}</h2>
    <div className="space-y-3 text-white/65 leading-relaxed text-[15px]">{children}</div>
  </div>
);

const toc = [
  ['acceptance',        'Acceptance of Terms'],
  ['eligibility',       'Eligibility'],
  ['account',          'Your Account'],
  ['acceptable-use',   'Acceptable Use'],
  ['prohibited',       'Prohibited Activities'],
  ['payments',         'Payments & Billing'],
  ['refunds',          'Refunds'],
  ['termination',      'Termination'],
  ['disclaimer',       'Disclaimer of Warranties'],
  ['liability',        'Limitation of Liability'],
  ['governing-law',    'Governing Law'],
  ['changes',          'Changes to Terms'],
  ['contact',          'Contact'],
];

export default function TermsOfService({ onBack }: TermsProps) {
  return (
    <div className="min-h-screen bg-navy-primary text-white">
      {/* Header */}
      <div className="sticky top-0 z-50 bg-navy-primary/90 backdrop-blur-md border-b border-white/5">
        <div className="max-w-4xl mx-auto px-4 sm:px-6 h-16 flex items-center gap-4">
          <button onClick={onBack} className="p-2 hover:bg-white/5 rounded-lg transition-colors" aria-label="Go back">
            <ArrowLeft size={20} className="text-white/70" />
          </button>
          <div className="flex items-center gap-3">
            <FileText size={20} className="text-cyan" />
            <h1 className="font-orbitron font-bold tracking-wider text-sm sm:text-base">TERMS OF SERVICE</h1>
          </div>
          <span className="ml-auto font-mono text-xs text-white/30">Effective: 1 January 2026</span>
        </div>
      </div>

      <div className="max-w-4xl mx-auto px-4 sm:px-6 py-10">
        {/* Lead */}
        <div className="mb-10 p-6 bg-cyan/5 border border-cyan/20 rounded-2xl">
          <p className="text-sm leading-relaxed text-white/70">
            These Terms of Service ("Terms") govern your use of GeminiVPN's website, applications, and VPN services
            ("Services"). Please read them carefully. By creating an account or using our Services, you agree to be
            bound by these Terms.
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

        <Section id="acceptance" title="1. Acceptance of Terms">
          <p>By accessing or using GeminiVPN ("Service"), you confirm that you have read, understood, and agree to be bound by these Terms. If you do not agree to any part of these Terms, you may not use the Service. These Terms constitute a legally binding agreement between you and GeminiVPN.</p>
          <p>These Terms apply to all visitors, registered users, and subscribers. Your continued use of the Service after any modification to these Terms constitutes your acceptance of the revised Terms.</p>
        </Section>

        <Section id="eligibility" title="2. Eligibility">
          <p>You must be at least 16 years of age to create an account and use the Service. By using GeminiVPN, you represent that you are of legal age in your jurisdiction to enter into a binding contract.</p>
          <p>Use of the Service is not permitted in jurisdictions where VPN services are prohibited by law. You are solely responsible for ensuring that your use of the Service complies with all applicable local, national, and international laws and regulations.</p>
        </Section>

        <Section id="account" title="3. Your Account">
          <p>You are responsible for maintaining the confidentiality of your account credentials. Do not share your password with anyone. You are responsible for all activity that occurs under your account.</p>
          <p>You agree to provide accurate, current, and complete information when registering, and to update such information as necessary. False, inaccurate, or misleading information may result in immediate account termination.</p>
          <p>If you suspect unauthorised access to your account, contact us immediately at <strong className="text-cyan">support@geminivpn.zapto.org</strong>. GeminiVPN will not be liable for losses resulting from unauthorised use of your credentials.</p>
          <p>Each subscription is for a single user. Account sharing with multiple individuals is not permitted.</p>
        </Section>

        <Section id="acceptable-use" title="4. Acceptable Use">
          <p>GeminiVPN grants you a limited, non-exclusive, non-transferable, revocable licence to use the Service for personal, lawful purposes. You may connect up to 10 devices simultaneously under one subscription.</p>
          <p>You agree to use the Service only for lawful purposes and in a manner that does not infringe the rights of, restrict, or inhibit anyone else's use and enjoyment of the Service.</p>
          <p>GeminiVPN is designed for legitimate privacy and security use cases including: securing communications on public Wi-Fi, bypassing geographic restrictions on content, protecting personal data from surveillance, and ensuring business communications remain private.</p>
        </Section>

        <Section id="prohibited" title="5. Prohibited Activities">
          <p>You expressly agree not to use the Service for any of the following:</p>
          <p>• Illegal activities of any kind, including but not limited to hacking, fraud, malware distribution, or trafficking in illegal goods.</p>
          <p>• Sending unsolicited bulk messages (spam), phishing, or any form of electronic harassment.</p>
          <p>• Hosting or transmitting content that is obscene, defamatory, or that violates any third party's intellectual property rights.</p>
          <p>• Engaging in distributed denial-of-service (DDoS) attacks or other forms of network abuse.</p>
          <p>• Mining cryptocurrencies or conducting computationally intensive tasks that abuse VPN bandwidth.</p>
          <p>• Circumventing sanctions, embargoes, or trade restrictions imposed by any government.</p>
          <p>• Reselling or redistributing VPN access derived from your subscription without written authorisation.</p>
          <p>Violation of this section may result in immediate account suspension without refund and, where required by law, reporting to relevant authorities.</p>
        </Section>

        <Section id="payments" title="6. Payments & Billing">
          <p>All prices are displayed in USD and are inclusive of applicable taxes where required by law (Paddle handles VAT/GST compliance automatically). Payment is due at the time of subscription.</p>
          <p>Subscriptions automatically renew at the end of each billing period (monthly, annual, or two-year) unless cancelled before the renewal date. You will receive a reminder email 7 days before renewal.</p>
          <p>We accept payments via Stripe (card), Square (card), Paddle (subscription billing), and Coinbase Commerce (cryptocurrency). Payment disputes should be raised with us before initiating a chargeback — unwarranted chargebacks may result in account suspension.</p>
          <p>In the event of a failed payment, we will attempt to retry the charge for up to 3 days. If the payment continues to fail, your subscription will be suspended and you will be notified by email.</p>
        </Section>

        <Section id="refunds" title="7. Refunds">
          <p>GeminiVPN offers a <strong className="text-white">30-day money-back guarantee</strong> for all new subscriptions. If you are unsatisfied for any reason, contact us within 30 days of your initial payment for a full refund.</p>
          <p>Refunds are not available for renewals (you may cancel before renewal to avoid future charges). Cryptocurrency payments are refunded as account credit rather than on-chain transactions. Refunds are processed within 3–7 business days.</p>
          <p>The money-back guarantee applies once per customer. Accounts found to be abusing the refund policy (repeatedly subscribing and requesting refunds) may be denied future refunds.</p>
        </Section>

        <Section id="termination" title="8. Termination">
          <p>You may terminate your account at any time by contacting support. Upon termination, your right to use the Service ceases immediately. Account data is deleted within 30 days (payment records are retained as required by law).</p>
          <p>We reserve the right to suspend or terminate your account, without notice, if we determine you have violated these Terms, engaged in fraudulent activity, or posed a legal risk to GeminiVPN or its users.</p>
          <p>Upon termination for cause, no refund will be issued. If we terminate your account without cause, you will receive a prorated refund for the unused portion of your subscription.</p>
        </Section>

        <Section id="disclaimer" title="9. Disclaimer of Warranties">
          <p>THE SERVICE IS PROVIDED "AS IS" AND "AS AVAILABLE" WITHOUT WARRANTIES OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, OR NON-INFRINGEMENT.</p>
          <p>GeminiVPN does not warrant that the Service will be uninterrupted, error-free, or free from harmful components. While we use industry-standard security measures, we cannot guarantee absolute security of data transmitted over the internet.</p>
          <p>GeminiVPN does not represent that using our Service makes your activities completely anonymous or immune to all forms of monitoring. Users in high-risk environments (journalists, activists) are encouraged to use additional privacy tools.</p>
        </Section>

        <Section id="liability" title="10. Limitation of Liability">
          <p>TO THE MAXIMUM EXTENT PERMITTED BY APPLICABLE LAW, GEMINIVPN SHALL NOT BE LIABLE FOR ANY INDIRECT, INCIDENTAL, SPECIAL, CONSEQUENTIAL, OR PUNITIVE DAMAGES, INCLUDING BUT NOT LIMITED TO LOSS OF PROFITS, DATA, OR GOODWILL, ARISING OUT OF YOUR USE OF THE SERVICE.</p>
          <p>IN NO EVENT SHALL GEMINIVPN'S TOTAL LIABILITY TO YOU EXCEED THE AMOUNT PAID BY YOU FOR THE SERVICE IN THE THREE (3) MONTHS IMMEDIATELY PRECEDING THE CLAIM.</p>
        </Section>

        <Section id="governing-law" title="11. Governing Law">
          <p>These Terms shall be governed by and construed in accordance with applicable international commercial law. Any disputes arising under these Terms shall first be attempted to be resolved through good-faith negotiation. If negotiation fails, disputes shall be resolved through binding arbitration.</p>
          <p>Nothing in these Terms prevents either party from seeking emergency injunctive relief from a court of competent jurisdiction.</p>
        </Section>

        <Section id="changes" title="12. Changes to Terms">
          <p>GeminiVPN reserves the right to modify these Terms at any time. We will notify registered users of material changes by email at least 14 days before the changes take effect. Minor, non-material changes (e.g. clarifications) may be made without notice.</p>
          <p>Your continued use of the Service after changes take effect constitutes acceptance of the updated Terms. If you do not agree to the new Terms, you must stop using the Service and contact us to close your account.</p>
        </Section>

        <Section id="contact" title="13. Contact">
          <p>For questions regarding these Terms:</p>
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
