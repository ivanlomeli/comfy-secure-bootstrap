# Usar ComfyUI

Después del bootstrap, ComfyUI corre como servicio systemd escuchando en `127.0.0.1:8188` — **no expuesto al exterior**. Se accede vía SSH tunnel local.

## Abrir el túnel local

Desde tu Mac (ya conectado al túnel WireGuard):

```
ssh -N -L 8188:127.0.0.1:8188 admin@10.7.0.1
```

Y abre en tu navegador: **http://localhost:8188**

Si quieres persistir el túnel:

```
# ~/.ssh/config
Host comfy
    HostName 10.7.0.1
    User admin
    LocalForward 8188 127.0.0.1:8188
```

Luego solo `ssh -N comfy`.

## Estado del servicio

```
sudo systemctl status comfyui
sudo journalctl -u comfyui -f
```

Reinicio manual:
```
sudo systemctl restart comfyui
```

## Instalar modelos

Los modelos van en `/opt/comfyui/models/<tipo>/<archivo>`. Ejemplos:

```
# Checkpoint SDXL o SD1.5
/opt/comfyui/models/checkpoints/

# LoRA
/opt/comfyui/models/loras/

# VAE
/opt/comfyui/models/vae/

# CLIP encoders
/opt/comfyui/models/clip/

# Wan 2.2 (video)
/opt/comfyui/models/checkpoints/wan2.2/

# Sonic (motion)
/opt/comfyui/models/sonic/

# Fun-Control
/opt/comfyui/models/fun_control/
```

Descarga desde Hugging Face con `wget` o `huggingface-cli`. Ejemplo Wan 2.2:

```
cd /opt/comfyui/models/checkpoints
huggingface-cli login  # con tu token
huggingface-cli download Wan-AI/Wan2.2-A14B --local-dir ./wan2.2 --local-dir-use-symlinks False
```

## Custom nodes

`ComfyUI-Manager` ya está preinstalado. Desde la UI web (Manager → Install Custom Nodes) puedes añadir:

- **ComfyUI-VideoHelperSuite** — carga/exporta MP4/GIF.
- **ComfyUI-WanVideoWrapper** — nodos oficiales de Wan 2.x.
- **ComfyUI-KJNodes** — utilidades varias.
- **ComfyUI-Sonic** — audio-driven portrait animation.
- **ComfyUI-Fun-Control** — control preciso de video.

O manual:
```
cd /opt/comfyui/custom_nodes
git clone https://github.com/<autor>/<nodo>
cd <nodo>
/opt/comfyui/venv/bin/pip install -r requirements.txt
sudo systemctl restart comfyui
```

## Verificar GPU en uso

```
nvidia-smi
watch -n1 nvidia-smi   # monitor en tiempo real
```

Durante inferencia deberías ver ComfyUI consumiendo VRAM y compute.

## Benchmarks esperados (L40S 48 GB, sept-2026)

| Workflow | Resolución | Tiempo aprox |
|---|---|---|
| SDXL 1024×1024, 30 steps | | 8-12 s |
| Wan 2.2 A14B, 5 s @ 480p | | 3-6 min |
| Wan 2.2 A14B, 5 s @ 720p | | 10-15 min |
| Sonic (portrait animation) 5 s | | 2-4 min |

## Actualizar ComfyUI

```
cd /opt/comfyui
sudo -u ubuntu git pull
sudo -u ubuntu venv/bin/pip install -r requirements.txt
sudo systemctl restart comfyui
```

## Almacenamiento de outputs

Los renders se guardan en `/opt/comfyui/output/`. Para descargarlos:

```
rsync -avz admin@10.7.0.1:/opt/comfyui/output/ ./output/
```

O montar por SSHFS:
```
sshfs admin@10.7.0.1:/opt/comfyui/output ~/comfy-output
```
