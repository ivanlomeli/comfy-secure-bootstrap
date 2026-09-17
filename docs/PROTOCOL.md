# Protocolo de arranque seguro

Este documento explica el orden **exacto** en que el bootstrap deja segura una máquina nueva y cómo pasar del acceso temporal (puerto 2222) al acceso definitivo (solo WireGuard).

## Estados de la máquina

```
   [Estado 0] Instancia recién lanzada (nada corriendo)
        │
        ▼  user-data ejecuta bootstrap.sh
   [Estado 1] SSH temporal 2222 abierto + WireGuard corriendo
        │
        ▼  humano configura cliente WG y valida
   [Estado 2] SSH accesible por WG (10.7.0.1:22) Y por 2222
        │
        ▼  humano corre 90-lock-down.sh
   [Estado 3] SSH SOLO por WG + Security Group cerrado
```

## Estado 1 — SSH temporal + WG corriendo

Después de `bootstrap.sh`, la máquina tiene:

- **Puerto 2222/tcp abierto** en UFW y en el Security Group (o firewall cloud) — SSH temporal, keys-only, sin root, sin passwords.
- **Puerto 51820/udp abierto** — WireGuard escuchando.
- **Puerto 22/tcp cerrado**.
- Firewall en modo **deny incoming** para todo lo demás.

En este estado puedes:
- Entrar con `ssh -p 2222 admin@<ip-pública>` (temporal).
- Conectarte al túnel WG desde tu cliente.
- Correr `sudo /opt/bootstrap/add-peer.sh <nombre>` para dar de alta clientes.

## Estado 2 — validando el túnel

1. En el servidor:
   ```
   sudo /opt/bootstrap/add-peer.sh mi-mac
   ```
   Esto imprime el config del cliente (con QR ANSI en la terminal).

2. En tu Mac / iOS / Android instala WireGuard, escanea el QR (o pega el `.conf`), conéctate al túnel.

3. Verifica desde tu Mac:
   ```
   ping 10.7.0.1
   ssh admin@10.7.0.1
   ```
   Si el ssh entra, estás validado.

## Estado 3 — lock-down

Ya validado el túnel, corre:

```
sudo /opt/bootstrap/scripts/90-lock-down.sh
```

Esto:
- Mueve sshd a `Port 22` con `ListenAddress 10.7.0.1` (**solo escucha dentro del túnel**).
- Elimina la regla `2222/tcp` de UFW.
- Reconfigura fail2ban para vigilar el puerto 22.

Después de esto, en el firewall cloud (AWS SG, Hetzner Cloud Firewall, etc.) **borra la regla 2222/tcp**. Ejemplo AWS:

```
aws ec2 revoke-security-group-ingress \
  --group-id sg-XXXXXXXX \
  --protocol tcp --port 2222 --cidr 0.0.0.0/0
```

**El único ingress abierto es 51820/udp para WireGuard**. Todo lo demás va por el túnel.

## Fail-safe: ¿y si me quedo fuera?

Si pierdes acceso al túnel (llave WG borrada, cliente reinstalado), tienes dos vías:

1. **AWS SSM Session Manager** — si la instancia tiene el IAM role `AmazonSSMManagedInstanceCore` y el agente instalado, entras con:
   ```
   aws ssm start-session --target i-XXXXXXXXXXXXXX
   ```
   sin necesidad de red entrante. Recomendado para todas las instancias EC2.

2. **Reabrir 2222 temporalmente vía consola** — AWS Console → EC2 → Security Groups → agregar regla 2222/tcp desde tu IP; luego SSH en 2222 y regenerar la config WG.

## Rotación de credenciales WG

- Peer comprometido: en el servidor `wg set wg0 peer <PUBKEY> remove; wg-quick save wg0`.
- Servidor comprometido: regenerar `server.key/server.pub` y todos los peers desde cero (destruir el archivo `wg0.conf` y volver a correr `30-wireguard.sh` + `add-peer.sh`).

## Auditoría continua

`99-verify.sh` sirve como checklist post-arranque. Recomendado correrlo:
- Justo después del bootstrap (asegurar que el estado 1 quedó bien).
- Después de `lock-down.sh` (asegurar que 22 solo está en 10.7.0.1).
- Semanalmente vía cron o systemd-timer.
