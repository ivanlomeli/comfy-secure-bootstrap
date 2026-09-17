#!/usr/bin/env bash
# Fase 2 — Perfil AppArmor custom para ComfyUI (python venv).
#
# Restringe qué puede tocar el proceso python de ComfyUI incluso si un
# custom node malicioso obtiene RCE dentro del proceso.
set -euo pipefail

apt-get install -y apparmor-utils apparmor-profiles

# Perfil para el intérprete del venv de ComfyUI
cat >/etc/apparmor.d/opt.comfyui.venv.bin.python <<'EOF'
#include <tunables/global>

/opt/comfyui/venv/bin/python* flags=(complain) {
  #include <abstractions/base>
  #include <abstractions/python>
  #include <abstractions/nameservice>

  # Ejecutables permitidos
  /opt/comfyui/venv/bin/** ix,
  /usr/bin/git ix,
  /usr/bin/env ix,
  /usr/bin/curl ix,

  # Filesystem
  /opt/comfyui/**            rw,
  /opt/comfyui/**            k,
  /home/comfyui/**           rw,
  /tmp/**                    rw,
  /var/tmp/**                rw,

  # GPU
  /dev/nvidia*               rw,
  /dev/nvidia-uvm*           rw,
  /dev/nvidiactl             rw,
  /dev/nvidia-caps/**        rw,
  /sys/module/nvidia*/**     r,
  /proc/driver/nvidia/**     r,

  # Sistema
  /etc/ld.so.cache           r,
  /etc/ssl/certs/**          r,
  /etc/resolv.conf           r,
  /etc/hosts                 r,
  /etc/nsswitch.conf         r,
  /proc/**/status            r,
  /proc/**/stat              r,
  /proc/meminfo              r,
  /proc/cpuinfo              r,
  /proc/sys/**               r,
  /sys/devices/**            r,
  /sys/class/**              r,
  /sys/bus/**                r,
  /sys/fs/cgroup/**          r,
  /usr/lib/**                mr,
  /usr/share/**              r,
  /usr/local/cuda*/**        r,

  # Red
  network inet stream,
  network inet6 stream,
  network inet dgram,
  network inet6 dgram,
  network netlink raw,
  network unix stream,
  network unix dgram,

  # Denegaciones explícitas
  deny /root/**              rwx,
  deny /home/*/.ssh/**       rwx,
  deny /etc/shadow           rwx,
  deny /etc/sudoers          rwx,
  deny /etc/sudoers.d/**     rwx,
  deny /etc/ssh/**           rwx,
  deny /etc/wireguard/**     rwx,
  deny /var/lib/aide/**      rwx,
  deny /var/log/audit/**     rwx,
  deny mount,
  deny ptrace,
  deny capability sys_admin,
  deny capability sys_module,
  deny capability sys_ptrace,
  deny capability net_admin,
}
EOF

# Cargar en modo complain primero (logea pero no bloquea) para que descubras
# rutas legítimas que faltan. Después: aa-enforce.
apparmor_parser -r /etc/apparmor.d/opt.comfyui.venv.bin.python
aa-complain /etc/apparmor.d/opt.comfyui.venv.bin.python

echo "[74-apparmor] perfil cargado en modo COMPLAIN (loguea denials, no bloquea)"
echo "[74-apparmor] revisa: journalctl -k | grep 'apparmor'"
echo "[74-apparmor] cuando esté estable, corre: sudo aa-enforce /etc/apparmor.d/opt.comfyui.venv.bin.python"
echo "[74-apparmor] estado actual:"
aa-status 2>/dev/null | head -20 || true

# Perfil restrictivo para nginx (bloquea escritura fuera de /var/log y /var/lib/nginx)
if [ -f /etc/apparmor.d/usr.sbin.nginx ]; then
  aa-enforce /etc/apparmor.d/usr.sbin.nginx 2>/dev/null || true
fi
