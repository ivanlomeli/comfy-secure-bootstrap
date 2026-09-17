#!/usr/bin/env bash
# AppArmor enforce + auditd con reglas mínimas de CIS/STIG.
set -euo pipefail

aa-enforce /etc/apparmor.d/* 2>/dev/null || true
systemctl enable --now apparmor

cat >/etc/audit/rules.d/99-hardening.rules <<'EOF'
-w /etc/passwd  -p wa -k identity
-w /etc/shadow  -p wa -k identity
-w /etc/group   -p wa -k identity
-w /etc/gshadow -p wa -k identity
-w /etc/sudoers -p wa -k scope
-w /etc/sudoers.d/ -p wa -k scope
-w /var/log/audit/ -p wa -k auditlog
-w /var/log/faillog -p wa -k logins
-w /var/log/lastlog -p wa -k logins
-w /etc/ssh/sshd_config -p wa -k sshd
-w /etc/ssh/sshd_config.d/ -p wa -k sshd
-a always,exit -F arch=b64 -S execve -F euid=0 -F auid>=1000 -F auid!=-1 -k root_cmd
-a always,exit -F arch=b64 -S mount -F auid>=1000 -F auid!=-1 -k mounts
-a always,exit -F arch=b64 -S unlink,unlinkat,rename,renameat -F auid>=1000 -F auid!=-1 -k delete
-e 2
EOF

augenrules --load
systemctl enable --now auditd
echo "[apparmor+auditd] OK"
