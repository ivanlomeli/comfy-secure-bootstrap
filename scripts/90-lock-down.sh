#!/usr/bin/env bash
# CORRE ESTO SOLO DESPUÉS DE VERIFICAR QUE `ssh <ADMIN>@10.7.0.1` FUNCIONA.
# Cierra el puerto 2222, mueve sshd a escuchar solo en la IP del túnel (10.7.0.1).
set -euo pipefail

CONF=/etc/ssh/sshd_config.d/99-hardening.conf

# Cambia Port 2222 → 22 y agrega ListenAddress 10.7.0.1
sed -i 's/^Port 2222/Port 22/' "$CONF"
if ! grep -q '^ListenAddress' "$CONF"; then
  echo 'ListenAddress 10.7.0.1' >> "$CONF"
fi
sshd -t
systemctl restart ssh

# UFW: cerrar 2222 (WireGuard 51820 sigue abierto)
ufw delete allow 2222/tcp || true

# fail2ban ahora vigila el puerto 22
sed -i 's/^port     = 2222/port     = 22/' /etc/fail2ban/jail.d/sshd.local
systemctl restart fail2ban

echo "[lock-down] SSH ahora solo en 10.7.0.1:22 (dentro del túnel WireGuard)."
echo "[lock-down] SIGUIENTE PASO: en AWS Security Group borra la regla 2222/tcp:"
echo "    aws ec2 revoke-security-group-ingress --group-id <SG_ID> \\"
echo "      --protocol tcp --port 2222 --cidr 0.0.0.0/0"
