#!/usr/bin/env bash
# Kernel hardening via sysctl.
set -euo pipefail

cat >/etc/sysctl.d/99-hardening.conf <<'EOF'
# Forwarding necesario para NAT del túnel WireGuard
net.ipv4.ip_forward=1

# Anti-spoofing / anti-redirect
net.ipv4.conf.all.rp_filter=1
net.ipv4.conf.default.rp_filter=1
net.ipv4.conf.all.log_martians=1
net.ipv4.tcp_syncookies=1
net.ipv4.conf.all.accept_redirects=0
net.ipv4.conf.default.accept_redirects=0
net.ipv4.conf.all.send_redirects=0
net.ipv4.conf.default.send_redirects=0
net.ipv4.conf.all.accept_source_route=0
net.ipv4.conf.default.accept_source_route=0
net.ipv6.conf.all.accept_redirects=0
net.ipv6.conf.default.accept_redirects=0
net.ipv6.conf.all.accept_source_route=0
net.ipv6.conf.default.accept_source_route=0
net.ipv6.conf.all.disable_ipv6=1
net.ipv6.conf.default.disable_ipv6=1

# Kernel info leaks
kernel.dmesg_restrict=1
kernel.kptr_restrict=2
kernel.yama.ptrace_scope=2
kernel.randomize_va_space=2
kernel.unprivileged_bpf_disabled=1
kernel.perf_event_paranoid=3

# Filesystem
fs.protected_hardlinks=1
fs.protected_symlinks=1
fs.protected_fifos=2
fs.protected_regular=2
fs.suid_dumpable=0
EOF

sysctl --system
echo "[sysctl] OK"
