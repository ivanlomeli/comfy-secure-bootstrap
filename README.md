# comfy-secure-bootstrap

Paquete de configuración inmediata para servidores **Ubuntu 24.04 LTS** nuevos, con foco en:

1. **Seguridad primero.** Endurece la máquina antes de exponer nada.
2. **Acceso solo por WireGuard.** Puerto 22 cerrado por defecto; puerto 2222 abierto temporalmente hasta validar el túnel, luego se cierra también.
3. **GPU + ComfyUI listos para trabajar.** Detecta L40S / A10G / H100 e instala driver, CUDA-ready PyTorch y ComfyUI con custom nodes canónicos.
4. **Mitigación de CVEs recientes.** Parchea sudo, glibc, kernel, snapd, NVIDIA driver, picklescan y bloquea SSRF a IMDS.

Pensado para EC2 (AMI Deep Learning Base OSS Ubuntu 24.04 o Ubuntu Server 24.04) pero portable a Hetzner, Contabo, GCP, Azure y VPS genéricos.

## Uso rápido

### En EC2, vía user-data al lanzar

```bash
#!/bin/bash
export ADMIN_USER=ubuntu
export ADMIN_SSH_PUBKEY="ssh-ed25519 AAAA... tu@llave.pub"
curl -fsSL https://raw.githubusercontent.com/ivanlomeli/comfy-secure-bootstrap/main/bootstrap.sh | sudo -E bash
```

### Manual en una máquina ya arrancada

```bash
git clone https://github.com/ivanlomeli/comfy-secure-bootstrap /opt/bootstrap
cd /opt/bootstrap
export ADMIN_USER=ubuntu
sudo -E ./bootstrap.sh
```

## Flujo de operación

```
┌────────────────────────────────────────────────────────────────┐
│  1. Lanza instancia con SG: 2222/tcp (tu IP) + 51820/udp       │
│  2. Bootstrap arranca automáticamente                          │
│     ├── UFW deny in / SSH en 2222 / fail2ban                   │
│     ├── sysctl + AppArmor + auditd                             │
│     ├── WireGuard servidor en 10.7.0.1/24                      │
│     ├── Driver NVIDIA + PyTorch cu128 + ComfyUI + Manager      │
│     └── CVE mitigations (sudo, glibc, snapd, IMDS, etc.)       │
│  3. Da de alta tu cliente:                                     │
│       sudo /opt/bootstrap/add-peer.sh mi-mac                   │
│  4. Conéctate al túnel desde tu Mac/iOS/Android                │
│  5. Verifica: ssh ubuntu@10.7.0.1                              │
│  6. Cierra el puerto 2222:                                     │
│       sudo /opt/bootstrap/scripts/90-lock-down.sh              │
│  7. En AWS: revoca la regla 2222/tcp del SG                    │
│  8. A partir de aquí SSH SOLO por el túnel WG                  │
└────────────────────────────────────────────────────────────────┘
```

## ¿Qué instala exactamente?

### Fase 1 — Baseline (siempre corre)

| Script | Qué hace |
|---|---|
| `00-baseline.sh` | UFW, sshd hardening (puerto 2222 temporal, algoritmos modernos, keys-only), fail2ban, unattended-upgrades, purga servicios innecesarios |
| `10-sysctl.sh` | Kernel hardening: rp_filter, syncookies, ptrace_scope=2, kptr_restrict=2, unprivileged_bpf_disabled, IPv6 off, filesystem protections |
| `20-apparmor-audit.sh` | AppArmor enforce, auditd con reglas CIS/STIG mínimas |
| `30-wireguard.sh` | Servidor WireGuard en `wg0` (10.7.0.1/24, UDP 51820) con NAT masquerade + helper `add-peer.sh` |
| `40-gpu-nvidia.sh` | Driver NVIDIA (`ubuntu-drivers --gpgpu`) — skip si ya está |
| `50-comfyui.sh` | Python 3.12 venv, PyTorch cu128, xformers, sage-attention, flash-attn, ComfyUI + ComfyUI-Manager, systemd unit |
| `60-cve-mitigations.sh` | Parches puntuales sudo/glibc/kernel/openssh/snapd, bloquea SSRF a IMDS 169.254.169.254, purga snapd si no se usa, protege Redis local |
| `90-lock-down.sh` | Cierra 2222, sshd solo en 10.7.0.1:22 dentro del túnel |
| `99-verify.sh` | ss, ufw status, wg show, servicios, lynis, SUID audit |

### Fase 2 — Hardening profundo (opcional; `ENABLE_PHASE2=1`, default ON)

| Script | Qué hace |
|---|---|
| `70-comfyui-sandbox.sh` | Usuario `comfyui` dedicado sin sudo, systemd sandbox strict (ProtectSystem, NoNewPrivileges, RestrictAddressFamilies), remonta /tmp con nosuid/nodev/noexec |
| `71-egress-filter.sh` | UFW/iptables OUTPUT deny-all + allowlist a Ubuntu/PyPI/HF/GitHub/NVIDIA/AWS. Modo `warn` primero, luego `enforce` |
| `72-aide-fim.sh` | AIDE baseline post-install + cron diario con alertas SNS |
| `73-wazuh-agent.sh` | Agente Wazuh SIEM/EDR (solo si `WAZUH_MANAGER` set) |
| `74-apparmor-profiles.sh` | Perfil AppArmor custom para el python de ComfyUI (deny /root, /etc/shadow, /etc/ssh, /etc/wireguard) |
| `75-auditd-full.sh` | Reglas STIG completas: execve, ptrace, mount, kexec, cambios de red/PAM/cron/systemd, ejecución desde /tmp |
| `76-pam-hardening.sh` | pam_pwquality, pam_faillock (5 intentos → 15 min lock), TOTP opcional en sudo |
| `77-kernel-lockdown.sh` | GRUB `lockdown=confidentiality`, `modules_disabled=1` diferido 15 min, blacklist de LKMs raros (cramfs, dccp, sctp, firewire, bluetooth) |
| `78-log-forwarding.sh` | CloudWatch Logs / Loki / rsyslog remoto (condicional a env vars) |
| `79-integrity-verify.sh` | `pip-audit` en el venv, verificación SHA256 de modelos vs MANIFEST, allowlist de custom nodes, advertencia sobre pickle |
| `80-backups.sh` | AWS Backup diario (via consola) + restic → S3 cifrado (si `RESTIC_REPOSITORY` set) |

### Amenazas cubiertas y no cubiertas

Ver [`docs/THREAT-MODEL.md`](docs/THREAT-MODEL.md) para un desglose honesto.

## Documentación

- [`docs/PROTOCOL.md`](docs/PROTOCOL.md) — protocolo paso a paso del arranque seguro.
- [`docs/AWS-USER-DATA.md`](docs/AWS-USER-DATA.md) — cómo usar el bootstrap desde user-data + Security Group + IMDSv2.
- [`docs/WIREGUARD-CLIENT.md`](docs/WIREGUARD-CLIENT.md) — instalar el cliente en Mac, iOS, Android, Linux.
- [`docs/COMFYUI-USAGE.md`](docs/COMFYUI-USAGE.md) — cómo acceder a ComfyUI vía SSH tunnel local.
- [`docs/GRAPHICAL-ACCESS.md`](docs/GRAPHICAL-ACCESS.md) — acceso gráfico: SSH tunnel (recomendado) vs xrdp vs SSHFS.
- [`docs/CVES.md`](docs/CVES.md) — CVEs monitoreados y sus mitigaciones.
- [`docs/THREAT-MODEL.md`](docs/THREAT-MODEL.md) — qué cubre y qué NO cubre este stack.
- [`preload/`](preload/) — scripts para preinstalar custom nodes y descargar modelos populares tras el bootstrap.

## Contribuir

Idempotente por diseño. Cualquier script debe poder correrse dos veces sin romper el sistema. PRs bienvenidos.

## Licencia

MIT.
