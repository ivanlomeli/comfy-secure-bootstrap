#!/usr/bin/env bash
# Fase 2 — Sandboxing de ComfyUI.
#
# Corta el vector más grande: modelo .pt malicioso o custom node comprometido
# obtiene RCE con permisos del usuario `ubuntu`, que tiene sudo → root.
#
# Cambios:
#   1. Usuario dedicado `comfyui` sin sudo, sin shell interactiva.
#   2. Migra /opt/comfyui a ese usuario.
#   3. Reemplaza la unit systemd con hardening estricto.
#   4. Remonta /tmp, /var/tmp, /dev/shm con nosuid,nodev,noexec (donde aplique).
#
# Idempotente. Corre después de 50-comfyui.sh.
set -euo pipefail

COMFY_USER=comfyui
COMFY_HOME=/opt/comfyui

# 1. Crear usuario sin sudo, shell nologin
if ! id "$COMFY_USER" >/dev/null 2>&1; then
  useradd --system --home-dir "$COMFY_HOME" --shell /usr/sbin/nologin --comment "ComfyUI service" "$COMFY_USER"
fi

# Cambiar dueño del directorio
if [ -d "$COMFY_HOME" ]; then
  chown -R "$COMFY_USER:$COMFY_USER" "$COMFY_HOME"
fi

# 2. Reemplazar unit systemd con hardening estricto
cat >/etc/systemd/system/comfyui.service <<EOF
[Unit]
Description=ComfyUI (sandboxed)
After=network.target
StartLimitIntervalSec=60
StartLimitBurst=3

[Service]
Type=simple
User=${COMFY_USER}
Group=${COMFY_USER}
WorkingDirectory=${COMFY_HOME}
Environment=PATH=${COMFY_HOME}/venv/bin:/usr/bin:/usr/local/cuda/bin
Environment=HOME=${COMFY_HOME}
Environment=TMPDIR=${COMFY_HOME}/tmp

# Ejecución
ExecStartPre=/bin/mkdir -p ${COMFY_HOME}/tmp
ExecStart=${COMFY_HOME}/venv/bin/python main.py --listen 127.0.0.1 --port 8188
Restart=on-failure
RestartSec=5

# ===== systemd sandbox =====
# Filesystem read-only excepto ruta necesarias
ProtectSystem=strict
ReadWritePaths=${COMFY_HOME}
ProtectHome=yes
PrivateTmp=yes
PrivateDevices=no       # necesita /dev/nvidia*
DeviceAllow=/dev/nvidia0 rw
DeviceAllow=/dev/nvidiactl rw
DeviceAllow=/dev/nvidia-uvm rw
DeviceAllow=/dev/nvidia-uvm-tools rw
DeviceAllow=/dev/nvidia-caps rw
DeviceAllow=/dev/nvidia-modeset rw

# Kernel / capabilities
NoNewPrivileges=yes
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectKernelLogs=yes
ProtectControlGroups=yes
ProtectClock=yes
ProtectHostname=yes
LockPersonality=yes
MemoryDenyWriteExecute=no       # PyTorch/JIT necesita W+X
RestrictRealtime=yes
RestrictSUIDSGID=yes
RestrictNamespaces=yes
SystemCallArchitectures=native

# Red: solo AF_INET/AF_INET6/AF_UNIX
RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6 AF_NETLINK

# Sin nueva capability
CapabilityBoundingSet=
AmbientCapabilities=

# Límites de recursos
LimitNOFILE=65536
TasksMax=4096

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl restart comfyui

# 3. Remontar filesystems temporales con flags restrictivos
# En cloud VMs /tmp suele ser tmpfs si systemd está configurado así; si no lo está, lo forzamos.
if ! mount | grep -q "on /tmp type tmpfs"; then
  systemctl enable --now tmp.mount 2>/dev/null || true
fi

# fstab: agregar opciones si /tmp o /dev/shm no las tienen
if ! grep -qE '^tmpfs\s+/tmp' /etc/fstab; then
  echo 'tmpfs /tmp     tmpfs defaults,rw,nosuid,nodev,noexec,relatime,size=2G 0 0' >> /etc/fstab
fi
if ! grep -qE '^tmpfs\s+/var/tmp' /etc/fstab; then
  echo 'tmpfs /var/tmp tmpfs defaults,rw,nosuid,nodev,noexec,relatime,size=1G 0 0' >> /etc/fstab
fi

# /dev/shm ya es tmpfs; solo agregarle noexec vía remount
mount -o remount,nosuid,nodev,noexec /dev/shm 2>/dev/null || true

echo "[70-sandbox] ComfyUI corriendo como '${COMFY_USER}' (sin sudo, systemd sandbox strict)"
systemctl status comfyui --no-pager | head -15 || true
