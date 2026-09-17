#!/usr/bin/env bash
# Audita el estado de seguridad post-bootstrap.
set -euo pipefail

echo "=== Puertos escuchando ==="
ss -tlnp 2>/dev/null | awk 'NR==1 || /:22 |:2222 |:80 |:443 |:51820/'
echo
echo "=== UFW ==="
ufw status verbose
echo
echo "=== WireGuard ==="
wg show
echo
echo "=== Servicios críticos ==="
for s in ssh fail2ban auditd apparmor wg-quick@wg0 unattended-upgrades; do
  printf "  %-24s %s\n" "$s" "$(systemctl is-active "$s" 2>/dev/null || echo missing)"
done
echo
echo "=== Kernel ==="
uname -r
echo
echo "=== Paquetes con CVEs activos por parchar ==="
apt list --upgradable 2>/dev/null | grep -iE 'security|-security' | head -10 || echo "  ninguno"
echo
echo "=== Lynis quick audit (score objetivo > 75) ==="
if command -v lynis >/dev/null; then
  lynis audit system --pentest --quick 2>/dev/null | grep -E "Hardening index|Warnings|Suggestions" | head -5
fi
echo
echo "=== Ficheros SUID inusuales ==="
find / -perm -4000 -type f 2>/dev/null | grep -v -E '^/(usr/bin|usr/sbin|usr/lib|bin|sbin)/' | head -10 || echo "  ninguno raro"
