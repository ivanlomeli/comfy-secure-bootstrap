#!/usr/bin/env bash
# Fase 2 — Instalar agente Wazuh (SIEM/EDR completo).
#
# OPCIONAL: solo corre si hay un Wazuh manager accesible.
# Setea:
#   export WAZUH_MANAGER=1.2.3.4         # IP/hostname del manager
#   export WAZUH_AGENT_NAME=$(hostname)  # opcional
#
# Sin WAZUH_MANAGER seteado, el script sale sin cambios.
set -euo pipefail

if [ -z "${WAZUH_MANAGER:-}" ]; then
  echo "[73-wazuh] SKIP: no hay WAZUH_MANAGER en env. Para habilitar:"
  echo "  export WAZUH_MANAGER=<ip-manager>"
  echo "  sudo -E ./73-wazuh-agent.sh"
  exit 0
fi

export DEBIAN_FRONTEND=noninteractive
apt-get install -y curl gnupg lsb-release

# Repo oficial Wazuh
curl -sS https://packages.wazuh.com/key/GPG-KEY-WAZUH | gpg --no-default-keyring --keyring gnupg-ring:/usr/share/keyrings/wazuh.gpg --import
chmod 644 /usr/share/keyrings/wazuh.gpg
echo "deb [signed-by=/usr/share/keyrings/wazuh.gpg] https://packages.wazuh.com/4.x/apt/ stable main" > /etc/apt/sources.list.d/wazuh.list

apt-get update
WAZUH_AGENT_NAME="${WAZUH_AGENT_NAME:-$(hostname)}"
WAZUH_MANAGER="$WAZUH_MANAGER" WAZUH_AGENT_NAME="$WAZUH_AGENT_NAME" \
  apt-get install -y wazuh-agent

systemctl daemon-reload
systemctl enable wazuh-agent
systemctl start wazuh-agent

# Habilitar módulos extra en config
sed -i 's|<disabled>yes</disabled>|<disabled>no</disabled>|g' /var/ossec/etc/ossec.conf

# Agregar FIM extra en rutas ComfyUI
if ! grep -q "/opt/comfyui/custom_nodes" /var/ossec/etc/ossec.conf; then
  # Insertar antes del cierre de </syscheck>
  sed -i '/<\/syscheck>/i \    <directories check_all="yes" report_changes="yes">/opt/comfyui/custom_nodes</directories>\n    <directories check_all="yes" realtime="yes">/etc/wireguard</directories>' /var/ossec/etc/ossec.conf
fi

systemctl restart wazuh-agent

echo "[73-wazuh] agente conectado a $WAZUH_MANAGER como $WAZUH_AGENT_NAME"
echo "[73-wazuh] estado: $(systemctl is-active wazuh-agent)"
