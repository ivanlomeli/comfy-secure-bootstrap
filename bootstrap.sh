#!/usr/bin/env bash
# Entrypoint del bootstrap. Corre TODOS los scripts en orden.
# Uso desde EC2 user-data:
#   #!/bin/bash
#   export ADMIN_USER=ubuntu
#   export ADMIN_SSH_PUBKEY="ssh-ed25519 AAAA..."
#   curl -fsSL https://raw.githubusercontent.com/<user>/comfy-secure-bootstrap/main/bootstrap.sh | sudo -E bash
set -euo pipefail

: "${ADMIN_USER:?export ADMIN_USER=<usuario>}"

if [ "$(id -u)" -ne 0 ]; then
  echo "Este script debe correrse como root (o con sudo -E)." >&2
  exit 1
fi

# Directorio local del checkout (si se ejecuta como git clone) o descargar
if [ -d "$(dirname "$0")/scripts" ]; then
  ROOT="$(cd "$(dirname "$0")" && pwd)"
else
  ROOT=/opt/bootstrap
  install -d "$ROOT"
  REPO="${BOOTSTRAP_REPO:-https://github.com/ivanlomeli/comfy-secure-bootstrap.git}"
  git clone "$REPO" "$ROOT" 2>/dev/null || (cd "$ROOT" && git pull)
fi

# Asegura llave pública del admin en authorized_keys
if [ -n "${ADMIN_SSH_PUBKEY:-}" ]; then
  install -d -m 0700 -o "$ADMIN_USER" -g "$ADMIN_USER" "/home/$ADMIN_USER/.ssh"
  echo "$ADMIN_SSH_PUBKEY" > "/home/$ADMIN_USER/.ssh/authorized_keys"
  chown "$ADMIN_USER:$ADMIN_USER" "/home/$ADMIN_USER/.ssh/authorized_keys"
  chmod 600 "/home/$ADMIN_USER/.ssh/authorized_keys"
fi

cd "$ROOT/scripts"
chmod +x ./*.sh

# Orden importa
./00-baseline.sh
./10-sysctl.sh
./20-apparmor-audit.sh
./30-wireguard.sh
./40-gpu-nvidia.sh
./60-cve-mitigations.sh

# ComfyUI se instala como el usuario admin (no root)
if [ -n "${SKIP_COMFYUI:-}" ]; then
  echo "[bootstrap] SKIP_COMFYUI set, se omite instalación de ComfyUI"
else
  sudo -u "$ADMIN_USER" -H bash "$ROOT/scripts/50-comfyui.sh"
fi

echo
echo "=========================================="
echo "[bootstrap] Fase 1 completa."
echo "=========================================="
echo "SIGUIENTES PASOS MANUALES:"
echo "  1. Da de alta tu cliente WireGuard:"
echo "       sudo /opt/bootstrap/add-peer.sh mi-mac"
echo "     Escanea el QR con la app de WireGuard, conéctate al túnel."
echo "  2. Verifica que puedas hacer:  ssh $ADMIN_USER@10.7.0.1"
echo "  3. Cuando funcione, corre:     sudo $ROOT/scripts/90-lock-down.sh"
echo "     (esto cierra el puerto 2222 y deja SSH SOLO por el túnel)"
echo "  4. Audita el estado:           sudo $ROOT/scripts/99-verify.sh"
echo
echo "  Reinicia si 40-gpu-nvidia.sh instaló driver nuevo."
