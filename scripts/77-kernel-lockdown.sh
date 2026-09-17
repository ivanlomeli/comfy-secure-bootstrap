#!/usr/bin/env bash
# Fase 2 — Kernel lockdown.
#
# 1. Bloquear carga de nuevos LKMs 15 min después del boot (para que nvidia_uvm
#    y otros módulos legítimos alcancen a cargarse primero).
# 2. GRUB cmdline con lockdown=confidentiality (bloquea /dev/mem, kexec, etc.
#    incluso para root).
# 3. Blacklist de módulos exóticos raramente necesarios (rootkits los aman).
set -euo pipefail

# 1. Blacklist de módulos exóticos
cat >/etc/modprobe.d/99-blacklist-hardening.conf <<'EOF'
# Filesystems raros usados por rootkits para persistencia
install cramfs /bin/true
install freevxfs /bin/true
install jffs2 /bin/true
install hfs /bin/true
install hfsplus /bin/true
install squashfs /bin/true   # comentar si usas snap (no aplica: purgado)
install udf /bin/true

# Protocolos de red raros — usados por malware
install dccp /bin/true
install sctp /bin/true
install rds /bin/true
install tipc /bin/true
install n-hdlc /bin/true
install ax25 /bin/true
install netrom /bin/true
install x25 /bin/true
install rose /bin/true
install decnet /bin/true
install econet /bin/true
install af_802154 /bin/true
install ipx /bin/true
install appletalk /bin/true
install psnap /bin/true
install p8023 /bin/true
install p8022 /bin/true
install can /bin/true
install atm /bin/true

# USB storage — para servidores cloud no aplica; comentar si necesitas
# install usb-storage /bin/true

# Firewire (DMA attacks locales)
install firewire-core /bin/true
install firewire-ohci /bin/true
install firewire-sbp2 /bin/true

# Bluetooth (no aplica en servidor cloud)
install bluetooth /bin/true
install btusb /bin/true
EOF

# 2. GRUB cmdline con hardening
if [ -f /etc/default/grub ]; then
  # Preservar y añadir flags de hardening
  CMDLINE_HARD="lockdown=confidentiality slab_nomerge init_on_alloc=1 init_on_free=1 page_alloc.shuffle=1 pti=on vsyscall=none debugfs=off oops=panic module.sig_enforce=1 spectre_v2=on spec_store_bypass_disable=on tsx=off tsx_async_abort=full,nosmt mds=full,nosmt l1tf=full,force nosmt=force kvm.nx_huge_pages=force randomize_kstack_offset=on lsm=landlock,lockdown,yama,integrity,apparmor,bpf"
  # Insertar si no está
  if ! grep -q "lockdown=confidentiality" /etc/default/grub; then
    sed -i "s|^GRUB_CMDLINE_LINUX=\"|GRUB_CMDLINE_LINUX=\"${CMDLINE_HARD} |" /etc/default/grub
    update-grub 2>/dev/null || true
    echo "[77-lockdown] GRUB actualizado — REINICIO REQUERIDO para aplicar cmdline"
  fi
fi

# 3. modules_disabled=1 diferido 15 min post-boot
cat >/etc/systemd/system/kernel-modules-lockdown.service <<'EOF'
[Unit]
Description=Lock down kernel modules after boot
After=multi-user.target
[Service]
Type=oneshot
ExecStart=/bin/bash -c 'echo 1 > /proc/sys/kernel/modules_disabled'
[Install]
WantedBy=multi-user.target
EOF

cat >/etc/systemd/system/kernel-modules-lockdown.timer <<'EOF'
[Unit]
Description=Delay module lockdown 15 min after boot
[Timer]
OnBootSec=15min
[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable kernel-modules-lockdown.timer

echo "[77-lockdown] blacklist de módulos raros aplicado"
echo "[77-lockdown] modules_disabled=1 se activará 15 min después de cada boot"
echo "[77-lockdown] GRUB cmdline actualizado — REINICIA para aplicar lockdown=confidentiality"
