# Preload — modelos + custom nodes

Scripts que se corren **después** del bootstrap para dejar el servidor listo para trabajar.

## Orden recomendado

```bash
# 1. Instalar custom nodes verificados
sudo -u comfyui bash /opt/bootstrap/preload/install-custom-nodes.sh

# 2. Descargar modelos (~30-100 GB según profile)
export HF_TOKEN=hf_xxx   # token con acceso a FLUX.1 dev (ir a huggingface.co/settings/tokens)
sudo -u comfyui HF_TOKEN=$HF_TOKEN bash /opt/bootstrap/preload/models/download-essentials.sh full

# 3. Reiniciar ComfyUI
sudo systemctl restart comfyui
```

## Profiles

- `image` — solo modelos de imagen (SDXL + FLUX + upscaler + ControlNet Union) ~40 GB
- `video` — modelos de video (Wan 2.2, HunyuanVideo, LTX, AnimateDiff) ~80 GB
- `full` — todo ~120 GB

## Espacio en disco

El bootstrap crea la instancia con **500 GB EBS gp3**. Distribución típica:

```
/opt/comfyui/models          # 40-120 GB (según profile)
/opt/comfyui/output          # crece con cada render
/opt/comfyui/custom_nodes    # ~2 GB (deps de nodos + weights de Sonic, etc)
/var/lib/*                   # ~5 GB
/                            # 5-8 GB Ubuntu + kernel + drivers
Libre para outputs           # 250-350 GB
```

Los renders de video Wan 2.2 720p ocupan 20-80 MB c/u. Con 300 GB libres caben ~5000 videos.

## Genera manifest de integridad post-download

Después de la descarga, genera el MANIFEST para que `79-integrity-verify.sh` alerte si algún modelo cambia:

```bash
cd /opt/comfyui/models
find . -type f \( -name '*.safetensors' -o -name '*.ckpt' -o -name '*.pt' -o -name '*.pth' \) \
  | xargs sha256sum > MANIFEST.sha256

# Copia MANIFEST fuera de la máquina (a S3 con MFA-delete idealmente)
aws s3 cp MANIFEST.sha256 s3://mi-bucket-manifests/comfyui-$(hostname)-$(date +%F).sha256
```
