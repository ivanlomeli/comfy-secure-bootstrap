# Acceso gráfico al servidor

**TL;DR:** ComfyUI no es un programa de escritorio — es una **app web** que corre en `127.0.0.1:8188`. No necesitas escritorio remoto (VNC, xrdp, X11). Solo un **SSH tunnel** desde tu Mac y abres `http://localhost:8188` en tu navegador local.

## Opción A — SSH LocalForward (recomendada)

Después de conectarte al túnel WireGuard:

```
ssh -N -L 8188:127.0.0.1:8188 ubuntu@10.7.0.1
```

Deja esa terminal abierta. En otro tab de tu Mac abre:

```
http://localhost:8188
```

**Eso es todo.** Vas a ver la UI de ComfyUI corriendo en la L40S, pero desde tu Mac como si fuera local. Todo el tráfico va cifrado: WireGuard (Mac → servidor) + SSH tunnel (encapsula el HTTP).

### Config permanente

Añade a `~/.ssh/config` en tu Mac:

```
Host comfy
    HostName 10.7.0.1
    User ubuntu
    LocalForward 8188 127.0.0.1:8188
    ServerAliveInterval 30
    ServerAliveCountMax 3
```

Luego solo `ssh -N comfy` y abres el navegador.

### Pros de esta vía

- **Cero configuración adicional** en el servidor — ComfyUI ya escucha en localhost.
- Rendimiento máximo (la UI corre en tu Mac, solo se transfieren las imágenes generadas).
- Solo un puerto expuesto (SSH), y solo dentro del túnel WG. Cero superficie extra.
- Funciona idéntico en Mac, Linux, Windows (con `ssh` o PuTTY).
- **Los outputs se descargan al navegador** cuando terminan; puedes guardarlos con drag&drop o `Save Image`.

### Cons

- Necesitas tener SSH abierto en background para que el túnel viva.
- No hay Finder-like browser de archivos remotos (usa `rsync` o `sshfs` — ver abajo).

## Opción B — nginx reverse proxy dentro del túnel

Si tienes múltiples cosas web corriendo (ComfyUI + JupyterLab + Grafana), pon nginx que las route:

```
# /etc/nginx/sites-available/apps
server {
    listen 10.7.0.1:80;

    location /comfy/  { proxy_pass http://127.0.0.1:8188/; }
    location /jupyter/ { proxy_pass http://127.0.0.1:8888/; }
}
```

Luego desde tu Mac (con WG conectado): `http://10.7.0.1/comfy/`. **Sin SSH tunnel.** Todo viaja por WireGuard directamente.

Pros: no necesitas SSH tunnel. Cons: nginx expone las apps dentro de la subred WG a cualquier peer.

## Opción C — Escritorio remoto real (xrdp / VNC)

**No lo necesitas para ComfyUI.** Pero si insistes en tener un escritorio Ubuntu completo (para editar archivos con nautilus, correr Firefox en el servidor, etc.), instala xrdp:

```
sudo apt install -y xrdp xfce4 xfce4-goodies
sudo systemctl enable --now xrdp
sudo adduser xrdp ssl-cert
# Solo escucha en localhost por seguridad:
sudo sed -i 's/^port=.*/port=127.0.0.1:3389/' /etc/xrdp/xrdp.ini
sudo systemctl restart xrdp
```

Y desde tu Mac, con WG conectado, cliente RDP (Microsoft Remote Desktop de la App Store) apunta a `10.7.0.1:3389`.

**Contras importantes:**
- xrdp + xfce = ~500 MB RAM extra siempre corriendo.
- Latencia y ancho de banda: mueve pixels en vez de datos. Sobre WG por internet residencial va lento.
- **Superficie de ataque grande**: cada app gráfica que corras es más código expuesto.
- Xfce/GNOME en servidor cloud es un antipatrón para 99% de casos.

Recomendación: NO instales xrdp a menos que tengas una razón muy específica.

## Opción D — Explorador de archivos remoto (SSHFS)

Si quieres arrastrar archivos entre tu Mac y el servidor como si fuera un disco local:

```
brew install --cask macfuse
brew install gromgit/fuse/sshfs-mac

mkdir ~/comfy-server
sshfs ubuntu@10.7.0.1:/opt/comfyui ~/comfy-server \
  -o reconnect,volname=comfy-server,default_permissions,follow_symlinks

# Ahora ~/comfy-server aparece en Finder como un disco montado
```

Para desmontar: `umount ~/comfy-server`.

## Comparativa

| Método | Setup | Rendimiento | Seguridad | Cuándo usar |
|---|---|---|---|---|
| **SSH tunnel** ⭐ | 1 comando | Excelente | Máxima | ComfyUI (siempre) |
| nginx en WG | Config nginx | Excelente | Alta | Múltiples apps web |
| xrdp / VNC | ~30 min setup | Regular | Media | Necesitas escritorio real (raro) |
| SSHFS | 5 min setup | Regular para archivos | Alta | Editar archivos con apps locales |

## Descargar outputs a tu Mac

Si generaste imágenes/videos en el servidor y los quieres traer:

```
# Descargar carpeta completa
rsync -avz ubuntu@10.7.0.1:/opt/comfyui/output/ ~/Desktop/comfy-output/

# Solo lo nuevo desde hace 1 hora
rsync -avz --files-from=<(ssh comfy 'find /opt/comfyui/output -mmin -60 -type f -printf "%P\n"') \
  ubuntu@10.7.0.1:/opt/comfyui/output/ ~/Desktop/comfy-output/
```

O directo desde la UI de ComfyUI — click derecho sobre la imagen en el canvas → *Save Image*.

## Streaming de video en tiempo real (para workflows Wan/Hunyuan)

ComfyUI muestra previews durante la generación en el mismo puerto 8188. Ya lo ves en tu navegador local sin nada extra.

Si quieres RTMP streaming del output finalizado a OBS o servicio similar, se resuelve con `ffmpeg` en el servidor, no con escritorio remoto.
