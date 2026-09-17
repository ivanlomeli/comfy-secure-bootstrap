#!/usr/bin/env bash
# Fase 2 — File Integrity Monitoring con AIDE.
#
# Detecta rootkits que modifiquen /bin, /sbin, /usr, /etc, /boot post-arranque.
# Base de datos se genera POST-BOOTSTRAP y se aloja fuera del host cuando sea posible.
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
apt-get install -y aide aide-common

# Config específica: monitor de rutas críticas, ignorar logs y directorios volátiles
cat >/etc/aide/aide.conf.d/99-hardening <<'EOF'
# Perfiles
Norm = p+i+n+u+g+s+b+m+c+md5+sha256

# Rutas críticas — cualquier cambio es sospechoso
/boot           Norm
/bin            Norm
/sbin           Norm
/usr/bin        Norm
/usr/sbin       Norm
/usr/lib        Norm
/usr/lib32      Norm
/usr/lib64      Norm
/lib            Norm
/etc            Norm
/root           Norm

# Kernel modules — un rootkit se instala aquí
/lib/modules    Norm

# systemd units — persistencia común
/etc/systemd    Norm
/lib/systemd    Norm

# SSH y sudo
/etc/ssh        Norm
/etc/sudoers    Norm
/etc/sudoers.d  Norm
/etc/pam.d      Norm

# WireGuard
/etc/wireguard  Norm

# Ignorar directorios que cambian constantemente
!/var/log
!/var/lib
!/var/cache
!/var/tmp
!/tmp
!/proc
!/sys
!/run
!/dev
!/home
!/opt/comfyui/output
!/opt/comfyui/models
!/opt/comfyui/temp
EOF

# Generar baseline
echo "[aide] generando base de datos inicial (puede tardar 3-5 min)..."
aideinit --force --yes >/dev/null 2>&1 || aide --config /etc/aide/aide.conf --init
if [ -f /var/lib/aide/aide.db.new ]; then
  mv -f /var/lib/aide/aide.db.new /var/lib/aide/aide.db
fi

# Hash de la db propia (para detectar tampering de la db)
sha256sum /var/lib/aide/aide.db > /var/lib/aide/aide.db.sha256
chmod 600 /var/lib/aide/aide.db /var/lib/aide/aide.db.sha256

# Cron diario a las 04:00 con alertas por journal (mail opcional)
cat >/etc/cron.daily/aide-check <<'EOF'
#!/bin/bash
# Check diario AIDE
set -e
LOG=/var/log/aide/check-$(date +%Y%m%d).log
mkdir -p /var/log/aide

# Verificar que la db no fue modificada
if ! sha256sum -c /var/lib/aide/aide.db.sha256 >/dev/null 2>&1; then
  logger -t aide -p auth.crit "AIDE database HASH MISMATCH — possible tampering"
  exit 2
fi

/usr/bin/aide --check --config /etc/aide/aide.conf > "$LOG" 2>&1 || true

if grep -qE "^(Added|Removed|Changed) entries:\s*[1-9]" "$LOG"; then
  logger -t aide -p auth.warning "AIDE detected filesystem changes — see $LOG"
  # Si hay AWS SNS configurado y aws cli disponible, alertar
  if [ -n "${AIDE_SNS_TOPIC:-}" ] && command -v aws >/dev/null; then
    aws sns publish --topic-arn "$AIDE_SNS_TOPIC" \
      --subject "AIDE alert on $(hostname)" \
      --message "$(head -100 "$LOG")" >/dev/null 2>&1 || true
  fi
fi
EOF
chmod +x /etc/cron.daily/aide-check

echo "[72-aide] baseline generada en /var/lib/aide/aide.db"
echo "[72-aide] cron diario 04:00; logs en /var/log/aide/"
echo "[72-aide] Para test manual: sudo aide --check"
