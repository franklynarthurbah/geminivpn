#!/usr/bin/env bash
# GeminiVPN Host Kernel Tuning — Run ONCE on the server before docker compose up
# These settings dramatically reduce VPN + web latency

set -euo pipefail

echo "🔧 Applying kernel network optimizations..."

# FIX: TCP Fast Open — eliminates one round-trip on reconnect
sysctl -w net.ipv4.tcp_fastopen=3

# FIX: Increase connection backlog — prevent dropped connections under load
sysctl -w net.core.somaxconn=65535
sysctl -w net.ipv4.tcp_max_syn_backlog=65535

# FIX: BBR congestion control — dramatically improves throughput on lossy links
# BBR is designed for high-bandwidth, moderate-latency paths (VPN servers)
modprobe tcp_bbr 2>/dev/null || true
sysctl -w net.core.default_qdisc=fq
sysctl -w net.ipv4.tcp_congestion_control=bbr

# FIX: Receive/send buffer sizes — reduces latency under high throughput
sysctl -w net.core.rmem_max=134217728
sysctl -w net.core.wmem_max=134217728
sysctl -w net.ipv4.tcp_rmem="4096 87380 134217728"
sysctl -w net.ipv4.tcp_wmem="4096 65536 134217728"

# FIX: Reduce TIME_WAIT — faster port recycling after connections close
sysctl -w net.ipv4.tcp_tw_reuse=1
sysctl -w net.ipv4.tcp_fin_timeout=15

# FIX: Disable slow start after idle — maintains high throughput on VPN streams
sysctl -w net.ipv4.tcp_slow_start_after_idle=0

# Persist across reboots
cat >> /etc/sysctl.conf << 'EOF'
# GeminiVPN tuning
net.ipv4.tcp_fastopen=3
net.core.somaxconn=65535
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.core.rmem_max=134217728
net.core.wmem_max=134217728
net.ipv4.tcp_tw_reuse=1
net.ipv4.tcp_fin_timeout=15
net.ipv4.tcp_slow_start_after_idle=0
EOF

echo "✅ Kernel tuning applied! Re-run 'sysctl -p' after reboot."
