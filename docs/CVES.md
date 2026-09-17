# CVEs monitoreados y sus mitigaciones

Este documento lista las vulnerabilidades relevantes que afectan a Ubuntu 24.04 LTS y a los componentes del stack (2025-2026), junto con lo que el bootstrap hace para mitigarlas. Actualizado sept-2026.

## Kernel / user-space

| CVE | Sev | Componente | Estado 24.04 | Mitigación en este repo |
|---|---|---|---|---|
| **CVE-2025-32463** | 9.3 | sudo `--chroot` (1.9.14-1.9.17) | Parcheado (`1.9.16p2-1ubuntu1.1`) | `60-cve-mitigations.sh` fuerza `apt --only-upgrade sudo` |
| **CVE-2025-32462** | 2.8 | sudo host bypass | Parcheado junto al anterior | Mismo update |
| **CVE-2025-4802** | Alto | glibc LD_LIBRARY_PATH en setuid estáticos | Parcheado | `apt upgrade libc6` en `60-cve-mitigations.sh` |
| **CVE-2026-0861** | 8.4 | glibc `memalign` int overflow (2.30-2.42) | Ver USN activos | `apt upgrade libc6` |
| **CVE-2026-5450** | Alto | glibc `scanf %mc` heap overflow (2.7-2.43) | Ver USN activos | `apt upgrade libc6` + no exponer parsers scanf a red |
| **CVE-2026-3888** | 7.8 | snap-confine + systemd-tmpfiles LPE | Parcheado USN-8102-1 | Purga snapd (`apt purge snapd`) — hecho en `00-baseline.sh` |
| **CVE-2026-8933** | Alto | snap-confine LPE | Parche activo | Igual — snapd fuera |
| **CVE-2026-31431** | 7.8 | kernel LPE | USN-8277-2 | `apt upgrade linux-generic && reboot` |
| **CVE-2026-64531** | Crítico | linux-hwe-7.0 (24.04) | USN-8659-2 | Actualizar kernel HWE + reboot |
| **CVE-2026-23112** | Alto | kernel | USN-8254-1 | Idem |
| **CVE-2024-6387** *regreSSHion* | Crítico | OpenSSH < 9.8p1 | Parcheado 2024 | Confirmar `ssh -V ≥ 9.8`; `LoginGraceTime 20` en `00-baseline.sh` como defensa en profundidad |

## Stack GPU / ML

| CVE | Sev | Componente | Mitigación |
|---|---|---|---|
| **CVE-2026-24187** | 8.8 | NVIDIA display driver Linux (UAF local) | Driver desde el boletín May-2026 (`40-gpu-nvidia.sh` toma la última rama estable) |
| **CVE-2025-23280** | 7.0 | NVIDIA driver Linux (UAF) | Actualizar driver |
| **CVE-2025-23244** | Alto | NVIDIA GPU driver Linux (LPE) | Actualizar driver |
| **CVE-2025-33219** | Alto | NVIDIA kernel module (int overflow) | Actualizar driver |
| **CVE-2025-10155/10156** | 9.3 | PickleScan bypass | `pip install picklescan>=0.0.31` en `60-cve-mitigations.sh` — usar **safetensors** sobre .pt/.pth/.bin |

## Cadena de suministro

- **CVE-2024-3094** *xz-utils backdoor*: verificar `xz --version ≥ 5.6.2`. Aún hay ~35 imágenes Docker Hub con la versión vulnerable (agosto 2025). El bootstrap no usa imágenes Docker por defecto; para pipelines que sí, escanear con `trivy image <img>`.
- **GhostAction (sept-2025)**: 817 repos GitHub, 3,325 secretos exfiltrados vía workflows maliciosos. Recomendación: bloquear `pull_request_target`, exigir `permissions:` mínimos, firmar releases con OIDC.
- **LiteLLM PyPI (mar-2026)**: paquete comprometido, ~500k credenciales expuestas. Pinear hashes en `requirements.txt` de custom nodes; correr `pip-audit` en CI.

## Malware Linux activo (2025-2026)

| Familia | Vector típico | Detección |
|---|---|---|
| **perfctl** | Docker/Redis expuestos, ~20k misconfigs | UFW deny + Redis bind loopback (hecho) |
| **Kinsing** | Docker API 2375, Redis sin auth, Confluence, Looney Tunables | UFW deny + no bindear Docker en TCP público |
| **RedTail** | Docker API 2375, Tor + minero | Igual |
| **Hadooken** | WebLogic → cryptominer + Tsunami | No exponer JEE apps sin auth |
| **Mirai / XorDDoS** | SSH brute-force | fail2ban (hecho) + SSH keys-only (hecho) + lock-down a WG |

## AWS / IMDS

- **F5 Labs marzo-2025**: oleada de SSRF activo hacia `http://169.254.169.254` para robar credenciales IAM.
- Mitigación: `HttpTokens=required` al lanzar (IMDSv2 obligatorio), `HttpPutResponseHopLimit=1`, y regla iptables `OUTPUT -d 169.254.169.254 -m owner ! --uid-owner root -j DROP` en `60-cve-mitigations.sh`.

## Detección y auditoría continua

- **Wazuh** (agente único): SCA, FIM, rootcheck, integra osquery, reglas contra perfctl/Kinsing. Se recomienda instalarlo tras el bootstrap si la máquina será permanente.
- **debsums** (ya instalado en `60-cve-mitigations.sh`): verifica integridad de paquetes.
- **lynis** (ya instalado): audit post-arranque en `99-verify.sh`.
- **pip-audit** para el venv de ComfyUI:
  ```
  /opt/comfyui/venv/bin/pip install pip-audit
  /opt/comfyui/venv/bin/pip-audit
  ```

## Qué NO cubre este bootstrap

- **Firma de kernel y Secure Boot** (requiere configuración por hardware).
- **Full disk encryption at rest** — en cloud usa EBS encryption at rest (habilitar por default en la cuenta).
- **Monitoreo continuo tipo SIEM** — requiere Wazuh/ELK/Loki externo.
- **Backups off-site** — responsabilidad del usuario.

## Fuentes

- [Ubuntu Security Notices](https://ubuntu.com/security/notices)
- [CIS Ubuntu 24.04 Benchmark v1.0.0](https://www.cisecurity.org/benchmark/ubuntu_linux)
- [Ubuntu Server Guide 24.04](https://documentation.ubuntu.com/server/)
- [WireGuard quickstart](https://www.wireguard.com/quickstart/)
- [NVIDIA Driver Installation Guide (Ubuntu)](https://docs.nvidia.com/datacenter/tesla/driver-installation-guide/ubuntu.html)
- [CVE-2025-32463 sudo — TheHackerNews](https://thehackernews.com/2025/07/critical-sudo-vulnerabilities-let-local.html)
- [CVE-2026-3888 snapd LPE — Qualys](https://blog.qualys.com/vulnerabilities-threat-research/2026/03/17/cve-2026-3888-important-snap-flaw-enables-local-privilege-escalation-to-root)
- [regreSSHion — Qualys](https://www.qualys.com/regresshion-cve-2024-6387)
- [PickleScan zero-days — JFrog](https://jfrog.com/blog/unveiling-3-zero-day-vulnerabilities-in-picklescan/)
- [perfctl campaign — BleepingComputer](https://www.bleepingcomputer.com/news/security/linux-malware-perfctl-behind-years-long-cryptomining-campaign/)
- [Kinsing container attacks — Aqua](https://www.aquasec.com/blog/threat-alert-kinsing-malware-container-vulnerability/)
- [SSRF a IMDS — CSO Online (F5 marzo 2025)](https://www.csoonline.com/article/3959148/hackers-attempted-to-steal-aws-credentials-using-ssrf-flaws-within-hosted-sites.html)
