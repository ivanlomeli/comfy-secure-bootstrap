#!/usr/bin/env bash
# Fase 2 — PAM hardening.
#
# 1. pam_pwquality: si algún día se activa passwords, exige complejidad.
# 2. pam_faillock: bloquea usuario tras N intentos fallidos.
# 3. TOTP opcional para sudo (setear ENABLE_SUDO_TOTP=1).
#
# NO habilita passwords SSH — sigue keys-only.
set -euo pipefail

apt-get install -y libpam-pwquality

# pwquality
cat >/etc/security/pwquality.conf <<'EOF'
minlen = 14
minclass = 4
maxrepeat = 2
maxclassrepeat = 2
dcredit = -1
ucredit = -1
lcredit = -1
ocredit = -1
difok = 5
reject_username
enforce_for_root
retry = 3
EOF

# faillock — bloquear tras 5 intentos, 15 min de castigo
cat >/etc/security/faillock.conf <<'EOF'
deny = 5
unlock_time = 900
even_deny_root
root_unlock_time = 300
fail_interval = 900
EOF

# Habilitar faillock en PAM (Ubuntu 24.04 usa pam_faillock)
if ! grep -q pam_faillock /etc/pam.d/common-auth; then
  sed -i '1i auth required pam_faillock.so preauth' /etc/pam.d/common-auth
  echo 'auth [default=die] pam_faillock.so authfail' >> /etc/pam.d/common-auth
  echo 'auth sufficient pam_faillock.so authsucc' >> /etc/pam.d/common-auth
fi

# Límites de recursos por usuario
cat >/etc/security/limits.d/99-hardening.conf <<'EOF'
*     hard   core        0
*     hard   nproc       4096
*     hard   nofile      65536
*     soft   nofile      32768
root  hard   nofile      131072
EOF

# TOTP en sudo (opcional)
if [ "${ENABLE_SUDO_TOTP:-}" = "1" ]; then
  apt-get install -y libpam-google-authenticator
  if ! grep -q pam_google_authenticator /etc/pam.d/sudo; then
    sed -i '1i auth required pam_google_authenticator.so nullok' /etc/pam.d/sudo
  fi
  echo "[76-pam] TOTP habilitado en sudo. Cada usuario debe correr:"
  echo "    google-authenticator -t -d -f -r 3 -R 30 -w 3"
  echo "  y guardar el QR/secret en su app de autenticación (Aegis, 1Password, Bitwarden)."
else
  echo "[76-pam] TOTP en sudo NO habilitado. Para activar:"
  echo "    sudo ENABLE_SUDO_TOTP=1 ./76-pam-hardening.sh"
fi

# Últimas líneas de login mostradas
sed -i 's|^#\?PrintMotd .*|PrintMotd yes|' /etc/ssh/sshd_config || true
sed -i 's|^#\?PrintLastLog .*|PrintLastLog yes|' /etc/ssh/sshd_config || true

echo "[76-pam] password quality, faillock y limits aplicados"
