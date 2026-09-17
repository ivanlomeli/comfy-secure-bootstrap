# Threat model

Documentar honestamente contra qué protege este stack y contra qué NO. Sin humo.

## Actores considerados

1. **Script kiddies / botnets** (Mirai, Kinsing, perfctl, RedTail, XorDDoS): scanners masivos, brute-force SSH, exploit de servicios expuestos con credenciales default.
2. **Atacantes oportunistas con exploit público reciente** (regreSSHion-tipo, sudo LPE, kernel LPE post-parche).
3. **Insider malicioso con acceso temporal** (contratista con la llave SSH, dispositivo comprometido).
4. **Supply-chain attackers** (paquete PyPI comprometido, custom node de ComfyUI malicioso, modelo `.pt` con pickle malicioso, xz-utils-tipo backdoor).
5. **Atacante avanzado con recursos limitados** (adversary con 0-day parcheado en 30 días).

## Actores NO considerados (fuera de alcance)

- **Nation-state con 0-days del kernel Linux o del hipervisor de AWS.**
- **Acceso físico al servidor** (cold-boot attacks, DMA, TEMPEST).
- **Compromiso del proveedor cloud** (rogue employee de AWS con acceso al hipervisor).
- **Ataques a la cadena de suministro del CPU/GPU** (microcode maliciosa de fábrica).
- **Compromise de la Mac / cliente WireGuard** (si tu Mac está infectada, todo el modelo cae).
- **Compromise de tu cuenta GitHub o del repo `comfy-secure-bootstrap`** (el bootstrap se descarga desde ahí; si lo comprometen, tienes RCE en cada nueva instancia).

## Vectores cubiertos (Fase 1 + Fase 2)

| Vector | Cubierto por | Nivel de protección |
|---|---|---|
| SSH brute-force en puerto 22 público | UFW deny + puerto 2222 temporal + fail2ban + lock-down al túnel WG | Alto |
| Explotación de sshd vulnerable | Algoritmos modernos, keys-only, `LoginGraceTime 20`, unattended-upgrades | Medio-alto |
| Enumeración de la red interna post-compromiso | Egress filter con allowlist | Alto (en modo enforce) |
| Descarga de segunda etapa (C2 pull) | Egress filter + DNS filtering | Alto (en modo enforce) |
| Persistencia vía cron/systemd | auditd watches en `/etc/cron.*`, `/etc/systemd/` | Detección, no prevención |
| Persistencia vía LKM (rootkit kernel) | `modules_disabled=1` post-boot + blacklist + `lockdown=confidentiality` | Alto |
| LPE via sudo LPE (CVE-2025-32463) | `apt --only-upgrade sudo` en 60-cve-mitigations.sh | Alto (parcheado) |
| LPE via glibc/kernel bug | unattended-upgrades + parches diarios | Alto pero con ventana |
| RCE desde ComfyUI (modelo pickle malicioso) | systemd sandbox strict + AppArmor + usuario dedicado sin sudo | Medio-alto |
| RCE desde custom node comprometido | Igual + allowlist de nodos + pip-audit | Medio (depende de disciplina) |
| SSRF → robo credenciales IMDS | `HttpTokens=required` + iptables DROP a 169.254.169.254 no-root | Alto |
| Exfiltración de logs (borrado tras compromiso) | Log forwarding a CloudWatch/Loki/syslog remoto | Alto (si se configura) |
| Ransomware / cifrado destructivo | Backups diarios cifrados a S3 + snapshots EBS + AIDE alerta al inicio | Medio-alto (si se configura) |
| Modificación de binarios del sistema | AIDE FIM diario + auditd | Detección diaria |
| Ataque físico al disco | EBS encryption at rest (habilitar en AWS) | Alto |
| Kernel LPE con 0-day activo | `kernel.unprivileged_bpf_disabled=1`, `kptr_restrict=2`, `lockdown=confidentiality` | Reduce superficie |
| Fileless / exec desde /tmp | Remontaje con `noexec,nosuid,nodev` + auditd | Alto |
| Docker bypass de UFW | Egress filter con iptables raw (fase 2) | Medio (si se instala Docker mal, se rompe) |

## Vectores parcialmente cubiertos

- **Custom nodes maliciosos post-instalación**: la allowlist es manual, no forzada. Un usuario que agregue nodos sin revisar sigue expuesto.
- **Compromise del bootstrap.sh en tránsito**: `curl | bash` desde raw.githubusercontent.com. Si hay MITM (poco probable con HTTPS) o el repo se compromete, RCE inmediato en el boot. Mitigación futura: publicar hash firmado GPG del bootstrap y verificarlo antes de ejecutar.
- **Robo de credenciales AWS via un shell interactivo del usuario admin**: si el atacante llega al usuario `ubuntu`, `aws sts get-caller-identity` funciona (rol IAM). Mitigación: usar IAM roles con mínimo privilegio (solo SSM y CloudWatch, nada de S3 o EC2 permissions).
- **Ataque a nginx**: perfil AppArmor default de Ubuntu está en enforce, pero no hemos escrito uno custom para ComfyUI-Manager que expone `/api/manager`. Recomendación: no exponer ComfyUI a la Internet abierta bajo ninguna circunstancia. Solo por SSH tunnel local.

## Vectores NO cubiertos

- **0-day en el kernel Linux** con exploit público antes de que Ubuntu emita parche: `unattended-upgrades` no ayuda si el USN aún no existe. Mitigación defensa-en-profundidad (AppArmor, sandbox systemd, egress) pero no elimina el riesgo.
- **Ataques al hipervisor AWS Nitro**: fuera de nuestro control.
- **Malicious insider con physical access + write al disco**: no aplica en cloud.
- **Compromise del cliente WireGuard (tu Mac)**: si tu Mac está infectada, el atacante entra por el túnel como si fueras tú. Mitigación: hardening del cliente, MFA en llave SSH (hardware key), verificar `ssh-keygen -l` regularmente.
- **Zero-day en OpenSSH sin parche**: Fase 1 + lock-down reducen exposición a solo la subred WG, pero un exploit desde un peer WG comprometido igual conecta.

## Métricas de éxito

Después del bootstrap y lock-down:

- `nmap` externo debería mostrar SOLO `51820/udp` abierto (nada más).
- `ss -tlnp` en el servidor debería mostrar SSH SOLO en `10.7.0.1:22`, ComfyUI en `127.0.0.1:8188`.
- Un modelo `.pt` malicioso ejecutando `os.system('rm -rf /')` desde ComfyUI debería fallar por AppArmor (deny fuera de `/opt/comfyui`).
- Un intento de cargar un LKM 15 min post-boot debería fallar con `modules_disabled`.
- `journalctl -k | grep EGRESS-BLOCK` (modo enforce) debería mostrar cualquier intento de C2.
- `aide --check` diario debería reportar 0 cambios (excepto los esperados).
- `lynis audit system --pentest` debería dar hardening index > 85.

Si alguna de estas no se cumple, algo está mal configurado.

## Escalada de defensa (más allá de este repo)

Si el servidor es de alto valor:

1. **Confidential Computing** en AWS Nitro Enclaves para procesos sensibles.
2. **HSM / KMS** para llaves privadas de WireGuard (AWS KMS con custom key store).
3. **Immutable infrastructure**: reconstruir la instancia cada semana desde AMI baseline verificada.
4. **Runtime security con Falco o Tetragon** — detección de syscalls sospechosos en tiempo real.
5. **Network segmentation** en VPC: subnet privada solo para ComfyUI, NAT gateway con inspección.
6. **Certificate pinning** para las conexiones a HuggingFace/GitHub (mitiga MITM en actualización de modelos).
7. **Red team ejercicio periódico** con pentesters.
