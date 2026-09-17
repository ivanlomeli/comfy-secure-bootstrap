#!/usr/bin/env bash
# Configura WireGuard como servidor en wg0 (10.7.0.1/24, UDP 51820).
set -euo pipefail

umask 077
install -d -m 0700 /etc/wireguard
cd /etc/wireguard

[ -f server.key ] || wg genkey | tee server.key | wg pubkey > server.pub

WAN_IF=$(ip -4 route show default | awk '{print $5; exit}')
: "${WAN_IF:?no default route}"

cat >/etc/wireguard/wg0.conf <<EOF
[Interface]
Address = 10.7.0.1/24
ListenPort = 51820
PrivateKey = $(cat server.key)
PostUp   = iptables -t nat -A POSTROUTING -o ${WAN_IF} -j MASQUERADE; iptables -A FORWARD -i wg0 -j ACCEPT; iptables -A FORWARD -o wg0 -j ACCEPT
PostDown = iptables -t nat -D POSTROUTING -o ${WAN_IF} -j MASQUERADE; iptables -D FORWARD -i wg0 -j ACCEPT; iptables -D FORWARD -o wg0 -j ACCEPT
EOF
chmod 600 /etc/wireguard/wg0.conf server.key
systemctl enable --now wg-quick@wg0

# Helper para agregar peers
install -d /opt/bootstrap
cat >/opt/bootstrap/add-peer.sh <<'PEER'
#!/usr/bin/env bash
# Uso: sudo /opt/bootstrap/add-peer.sh <nombre> [ip]
set -euo pipefail
NAME=${1:?nombre requerido}
IP=${2:-10.7.0.2}
cd /etc/wireguard
umask 077
wg genkey | tee "${NAME}.key" | wg pubkey > "${NAME}.pub"
PUB_SRV=$(cat server.pub)
ENDPOINT=$(curl -s https://api.ipify.org)
cat >"${NAME}.conf" <<EOF
[Interface]
PrivateKey = $(cat ${NAME}.key)
Address = ${IP}/32
DNS = 1.1.1.1

[Peer]
PublicKey = ${PUB_SRV}
Endpoint = ${ENDPOINT}:51820
AllowedIPs = 10.7.0.0/24
PersistentKeepalive = 25
EOF
wg set wg0 peer "$(cat ${NAME}.pub)" allowed-ips "${IP}/32"
wg-quick save wg0
echo
echo "=== Config del cliente (escanéalo con la app de WireGuard) ==="
qrencode -t ansiutf8 < "${NAME}.conf"
echo
echo "Archivo: /etc/wireguard/${NAME}.conf"
PEER
chmod +x /opt/bootstrap/add-peer.sh

echo "[wireguard] OK — server pub: $(cat /etc/wireguard/server.pub)"
echo "[wireguard] Para dar de alta un cliente: sudo /opt/bootstrap/add-peer.sh <nombre>"
