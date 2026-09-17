# Cliente WireGuard

## Generar la configuración del cliente en el servidor

Desde el servidor, después del bootstrap:

```
sudo /opt/bootstrap/add-peer.sh mi-mac
```

Esto:
1. Genera un par de claves nuevo.
2. Registra el peer en `wg0`.
3. Imprime la config en pantalla como QR (ANSI) y guarda `/etc/wireguard/mi-mac.conf`.

## Cliente Mac

**Opción A — app oficial**: descarga *WireGuard* desde la Mac App Store, add tunnel → escanea el QR, activa.

**Opción B — CLI (Homebrew)**:
```
brew install wireguard-tools
sudo scp -P 2222 admin@server:/etc/wireguard/mi-mac.conf /etc/wireguard/wg0.conf
sudo wg-quick up wg0
```

Verifica:
```
sudo wg show
ping 10.7.0.1
ssh admin@10.7.0.1
```

## Cliente iOS / Android

- Descarga *WireGuard* del App Store / Play Store.
- Add tunnel → *Create from QR code* → apunta al QR ANSI en la terminal del servidor (o usa `qrencode -o mi-mac.png` para generar PNG).

## Cliente Linux

```
sudo apt install wireguard
sudo cp mi-mac.conf /etc/wireguard/wg0.conf
sudo chmod 600 /etc/wireguard/wg0.conf
sudo systemctl enable --now wg-quick@wg0
```

## Anatomía del `.conf` del cliente

```ini
[Interface]
PrivateKey = <cliente-priv>
Address = 10.7.0.2/32
DNS = 1.1.1.1

[Peer]
PublicKey = <server-pub>
Endpoint = <ip-publica-server>:51820
AllowedIPs = 10.7.0.0/24
PersistentKeepalive = 25
```

- `AllowedIPs = 10.7.0.0/24` → solo el tráfico al túnel va por WG; el resto de tu Internet sale normal.
- Si quieres **routear todo tu tráfico** por el servidor, cambia a `AllowedIPs = 0.0.0.0/0`.

## Rotar clave del cliente

Si pierdes el dispositivo o se compromete la llave:

```
# En el servidor
sudo wg set wg0 peer <PUBKEY_VIEJA> remove
sudo wg-quick save wg0
sudo rm /etc/wireguard/mi-mac.*
sudo /opt/bootstrap/add-peer.sh mi-mac  # genera nueva
```

## Troubleshooting

**No conecta:**
- Verifica que el puerto 51820/udp esté abierto en el firewall cloud.
- `sudo wg show` en servidor → busca `latest handshake`. Si es "0 seconds ago" ok; si nunca aparece, el paquete no llega.
- Ejecuta `tcpdump -i eth0 udp port 51820` en el servidor mientras intentas conectar.

**Conecta pero no puedes SSH:**
- Verifica que `ssh admin@10.7.0.1` funcione en el estado 1 (antes de lock-down). Si no funciona, sshd no está escuchando en la IP del túnel — chequea `ss -tlnp | grep :22`.
- Después de lock-down, `sshd` solo escucha en `10.7.0.1:22`. Si no estás en la subred `10.7.0.0/24`, no conectas.
