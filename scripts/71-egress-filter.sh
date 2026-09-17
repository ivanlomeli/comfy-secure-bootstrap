#!/usr/bin/env bash
# Fase 2 — Egress filtering.
#
# Contiene el daño post-compromiso: un miner o C2 backdoor no puede llamar a
# cualquier IP. Se permite solo: DNS, NTP, apt.ubuntu.com, PyPI, HuggingFace,
# GitHub, AWS APIs, y respuesta al túnel WireGuard.
#
# CUIDADO: si te equivocas con las reglas puedes cortar apt/pip y bloquear
# el propio parche del sistema. Se abre con un modo `warn` (solo LOG) durante
# 24 horas y después flipea a `enforce` — así puedes revisar journalctl.
set -euo pipefail

MODE="${EGRESS_MODE:-warn}"   # warn | enforce

apt-get install -y ipset

# Crear ipset con dominios permitidos (resueltos periódicamente vía cron)
cat >/usr/local/sbin/refresh-egress-allowlist.sh <<'ALLOW'
#!/usr/bin/env bash
set -euo pipefail
ipset create egress_allow hash:ip family inet timeout 3600 -exist
DOMAINS=(
  # Actualizaciones de sistema
  archive.ubuntu.com security.ubuntu.com esm.ubuntu.com
  ppa.launchpad.net keyserver.ubuntu.com
  # PyPI + wheels
  pypi.org files.pythonhosted.org
  # PyTorch wheels
  download.pytorch.org
  # HuggingFace
  huggingface.co cdn-lfs.huggingface.co cdn-lfs-us-1.hf.co
  # GitHub (para clonar custom nodes)
  github.com codeload.github.com objects.githubusercontent.com raw.githubusercontent.com
  # NVIDIA drivers
  developer.download.nvidia.com us.download.nvidia.com
  # AWS metadata + APIs (para SSM)
  ssm.us-west-2.amazonaws.com ec2messages.us-west-2.amazonaws.com ssmmessages.us-west-2.amazonaws.com
  s3.amazonaws.com s3.us-west-2.amazonaws.com
  # Time
  time.google.com time.cloudflare.com
)
for d in "${DOMAINS[@]}"; do
  for ip in $(getent ahostsv4 "$d" | awk '{print $1}' | sort -u); do
    ipset add egress_allow "$ip" -exist
  done
done
ALLOW
chmod +x /usr/local/sbin/refresh-egress-allowlist.sh
/usr/local/sbin/refresh-egress-allowlist.sh

# systemd timer para refrescar la lista cada 15 min (IPs de CDN cambian)
cat >/etc/systemd/system/egress-allowlist.service <<'EOF'
[Unit]
Description=Refresh egress allowlist ipset
[Service]
Type=oneshot
ExecStart=/usr/local/sbin/refresh-egress-allowlist.sh
EOF
cat >/etc/systemd/system/egress-allowlist.timer <<'EOF'
[Unit]
Description=Refresh egress allowlist every 15min
[Timer]
OnBootSec=1min
OnUnitActiveSec=15min
[Install]
WantedBy=timers.target
EOF
systemctl daemon-reload
systemctl enable --now egress-allowlist.timer

# Reglas iptables OUTPUT
# 1. Permitir loopback y established
iptables -F OUTPUT
iptables -A OUTPUT -o lo -j ACCEPT
iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
# 2. Permitir DNS local (systemd-resolved) y remoto a Cloudflare
iptables -A OUTPUT -p udp --dport 53 -d 127.0.0.53 -j ACCEPT
iptables -A OUTPUT -p udp --dport 53 -d 1.1.1.1 -j ACCEPT
iptables -A OUTPUT -p udp --dport 53 -d 1.1.1.2 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 53 -d 1.1.1.1 -j ACCEPT
# 3. NTP
iptables -A OUTPUT -p udp --dport 123 -j ACCEPT
# 4. WireGuard responde a peers
iptables -A OUTPUT -p udp --sport 51820 -j ACCEPT
# 5. IMDS SOLO root (mitiga SSRF)
iptables -A OUTPUT -d 169.254.169.254 -m owner --uid-owner 0 -j ACCEPT
iptables -A OUTPUT -d 169.254.169.254 -j DROP
# 6. Tráfico HTTPS/HTTP/SSH a IPs de la allowlist
iptables -A OUTPUT -m set --match-set egress_allow dst -p tcp -m multiport --dports 80,443,22 -j ACCEPT
# 7. Salida hacia peers WG por wg0
iptables -A OUTPUT -o wg0 -j ACCEPT

# Comportamiento del último salto
if [ "$MODE" = "enforce" ]; then
  iptables -A OUTPUT -j LOG --log-prefix "EGRESS-BLOCK: " --log-level 4
  iptables -A OUTPUT -j DROP
  echo "[71-egress] MODO ENFORCE: bloqueando egress no permitido."
else
  iptables -A OUTPUT -j LOG --log-prefix "EGRESS-WARN: " --log-level 4
  echo "[71-egress] MODO WARN: solo loguea, NO bloquea todavía."
  echo "[71-egress] Revisa: journalctl -k | grep EGRESS-WARN"
  echo "[71-egress] Cuando estés seguro, corre: sudo EGRESS_MODE=enforce ./71-egress-filter.sh"
fi

# Persistir con iptables-persistent
apt-get -y install iptables-persistent >/dev/null 2>&1 || true
netfilter-persistent save 2>/dev/null || true

echo "[71-egress] listo. Modo: $MODE"
