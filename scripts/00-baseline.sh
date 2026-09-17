#!/usr/bin/env bash
# Baseline security para Ubuntu 24.04 recién creada.
# Requiere: export ADMIN_USER=<usuario>
set -euo pipefail

: "${ADMIN_USER:?export ADMIN_USER=<usuario>}"
export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get -y upgrade
apt-get -y install \
  unattended-upgrades apt-listchanges \
  fail2ban ufw \
  qrencode wireguard wireguard-tools \
  auditd audispd-plugins apparmor-utils \
  lynis needrestart curl jq

# unattended-upgrades: solo security, reboot 03:30 si hace falta
cat >/etc/apt/apt.conf.d/50unattended-upgrades <<'EOF'
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}-security";
    "${distro_id}ESMApps:${distro_codename}-apps-security";
    "${distro_id}ESM:${distro_codename}-infra-security";
};
Unattended-Upgrade::Automatic-Reboot "true";
Unattended-Upgrade::Automatic-Reboot-Time "03:30";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
EOF

cat >/etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF
systemctl enable --now unattended-upgrades

# UFW: deny in por default, salidas libres, loopback, SSH temporal 2222, WG 51820
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw allow in on lo
ufw allow 2222/tcp comment 'SSH temporal - cerrar tras validar WG'
ufw allow 51820/udp comment 'WireGuard'
ufw --force enable

# SSH drop-in hardening
install -d -m 0755 /etc/ssh/sshd_config.d
cat >/etc/ssh/sshd_config.d/99-hardening.conf <<EOF
Port 2222
AddressFamily inet
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
AuthenticationMethods publickey
AllowUsers ${ADMIN_USER}
MaxAuthTries 3
MaxSessions 4
LoginGraceTime 20
ClientAliveInterval 300
ClientAliveCountMax 2
AllowTcpForwarding no
X11Forwarding no
PermitUserEnvironment no
Banner none
KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org,sntrup761x25519-sha512@openssh.com
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com
HostKeyAlgorithms ssh-ed25519,rsa-sha2-512,rsa-sha2-256
EOF
rm -f /etc/ssh/ssh_host_dsa_key* /etc/ssh/ssh_host_ecdsa_key*
sshd -t && systemctl restart ssh

# fail2ban jail para sshd en 2222
cat >/etc/fail2ban/jail.d/sshd.local <<'EOF'
[sshd]
enabled  = true
port     = 2222
backend  = systemd
maxretry = 3
findtime = 10m
bantime  = 1h
EOF
systemctl enable --now fail2ban

# Deshabilitar servicios innecesarios en cloud
for s in avahi-daemon cups snapd ModemManager; do
  systemctl disable --now "$s" 2>/dev/null || true
done
apt-get -y purge snapd || true

echo "[baseline] OK — SSH temporal en 2222, UFW activo, unattended-upgrades corriendo."
