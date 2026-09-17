#!/usr/bin/env bash
# Fase 2 — auditd con reglas STIG completas.
#
# Extiende las reglas mínimas de 20-apparmor-audit.sh con cobertura amplia:
# execve completo, ptrace, mount, kexec, cambios en red, ejecuciones desde /tmp.
set -euo pipefail

cat >/etc/audit/rules.d/50-stig-full.rules <<'EOF'
# Todo execve — genera muchos eventos, filtra en post
-a always,exit -F arch=b64 -S execve -k exec
-a always,exit -F arch=b32 -S execve -k exec

# Elevación de privilegios
-a always,exit -F arch=b64 -S setuid,setgid,setreuid,setregid,setresuid,setresgid -F auid>=1000 -F auid!=-1 -k priv_escalation
-a always,exit -F path=/usr/bin/sudo -F perm=x -F auid>=1000 -F auid!=-1 -k sudo_used
-a always,exit -F path=/usr/bin/su   -F perm=x -F auid>=1000 -F auid!=-1 -k su_used

# ptrace — clave para debuggers maliciosos
-a always,exit -F arch=b64 -S ptrace -k ptrace
-a always,exit -F arch=b64 -S ptrace -F a0=0x4 -k code_injection
-a always,exit -F arch=b64 -S ptrace -F a0=0x5 -k data_injection
-a always,exit -F arch=b64 -S ptrace -F a0=0x6 -k register_injection

# Kernel modules — rootkits LKM
-a always,exit -F arch=b64 -S init_module,finit_module,delete_module -k module_ops

# Mount y kexec — bypass del kernel
-a always,exit -F arch=b64 -S mount -F auid>=1000 -F auid!=-1 -k mount
-a always,exit -F arch=b64 -S umount2 -F auid>=1000 -F auid!=-1 -k mount
-a always,exit -F arch=b64 -S kexec_load,kexec_file_load -k kexec

# Cambios en interfaces de red
-w /etc/hosts        -p wa -k network
-w /etc/hostname     -p wa -k network
-w /etc/networks     -p wa -k network
-w /etc/nsswitch.conf -p wa -k network
-w /etc/resolv.conf  -p wa -k network
-w /etc/systemd/network/ -p wa -k network
-w /etc/netplan/     -p wa -k network
-w /etc/iproute2/    -p wa -k network

# Firewall
-w /etc/ufw/         -p wa -k firewall
-w /etc/iptables/    -p wa -k firewall
-w /etc/sysconfig/iptables -p wa -k firewall

# cron / systemd timers — persistencia
-w /etc/cron.allow   -p wa -k cron
-w /etc/cron.deny    -p wa -k cron
-w /etc/cron.d/      -p wa -k cron
-w /etc/cron.hourly/  -p wa -k cron
-w /etc/cron.daily/   -p wa -k cron
-w /etc/cron.weekly/  -p wa -k cron
-w /etc/cron.monthly/ -p wa -k cron
-w /var/spool/cron/  -p wa -k cron
-w /etc/systemd/system/ -p wa -k systemd
-w /lib/systemd/system/ -p wa -k systemd

# PAM
-w /etc/pam.d/       -p wa -k pam
-w /etc/security/    -p wa -k pam
-w /etc/nsswitch.conf -p wa -k pam

# Ejecutables desde ubicaciones sospechosas — fileless attacks
-a always,exit -F arch=b64 -S execve -F path=/tmp -k exec_tmp
-a always,exit -F arch=b64 -S execve -F path=/var/tmp -k exec_tmp
-a always,exit -F arch=b64 -S execve -F path=/dev/shm -k exec_shm

# Cambios de permisos y ownership
-a always,exit -F arch=b64 -S chmod,fchmod,fchmodat -F auid>=1000 -F auid!=-1 -k perm_mod
-a always,exit -F arch=b64 -S chown,fchown,fchownat,lchown -F auid>=1000 -F auid!=-1 -k perm_mod

# Borrado de archivos por usuarios normales
-a always,exit -F arch=b64 -S unlink,unlinkat,rename,renameat -F auid>=1000 -F auid!=-1 -k delete

# Uso de comandos "vivan de la tierra"
-w /usr/bin/wget    -p x -k download
-w /usr/bin/curl    -p x -k download
-w /usr/bin/nc      -p x -k netcat
-w /usr/bin/ncat    -p x -k netcat
-w /usr/bin/socat   -p x -k netcat
-w /usr/bin/ssh     -p x -k ssh_used
-w /usr/bin/scp     -p x -k ssh_used
-w /usr/bin/base64  -p x -k obfuscation

# Rutas críticas
-w /boot            -p wa -k boot
-w /etc/ld.so.conf  -p wa -k libs
-w /etc/ld.so.conf.d/ -p wa -k libs
-w /etc/modprobe.d/ -p wa -k modules
-w /etc/modules-load.d/ -p wa -k modules

# Rate limits: no explotar RAM ante flood
-b 8192
--backlog_wait_time 60000

# NO permitir cambios a las reglas (excepto vía reboot)
-e 2
EOF

augenrules --load
systemctl restart auditd

echo "[75-auditd] reglas STIG completas cargadas ($(auditctl -l | wc -l) reglas activas)"
echo "[75-auditd] Consulta eventos con: sudo ausearch -k <key> --start today"
echo "[75-auditd] Reportes: sudo aureport --summary"
