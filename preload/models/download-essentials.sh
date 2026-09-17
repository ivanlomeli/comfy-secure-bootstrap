#!/usr/bin/env bash
# Descarga modelos esenciales para ComfyUI. Corre en el servidor DESPUÉS del bootstrap.
#
# Requiere: HF_TOKEN (token de HuggingFace con lectura). Sin token, algunos modelos gated (FLUX.1 dev) fallarán.
#
# Uso:
#   export HF_TOKEN=hf_xxx
#   bash download-essentials.sh [profile]
#
# Profiles: image | video | full
set -euo pipefail

PROFILE="${1:-full}"
MODELS_DIR="${MODELS_DIR:-/opt/comfyui/models}"

if [ -z "${HF_TOKEN:-}" ]; then
  echo "⚠️  HF_TOKEN no set. Modelos gated (FLUX.1 dev) fallarán."
  echo "   Obtén uno en: https://huggingface.co/settings/tokens"
fi

pip install --quiet --user 'huggingface_hub[cli,hf_transfer]'
export HF_HUB_ENABLE_HF_TRANSFER=1
if [ -n "${HF_TOKEN:-}" ]; then
  export HUGGING_FACE_HUB_TOKEN="$HF_TOKEN"
fi

hf() { python3 -m huggingface_hub "$@"; }

download() {
  local repo="$1" file="$2" dst="$3"
  local target="$MODELS_DIR/$dst/$(basename "$file")"
  if [ -f "$target" ]; then
    echo "  ✓ ya existe: $target"
    return 0
  fi
  echo "  ⇣ $repo → $target"
  hf download "$repo" "$file" --local-dir "$MODELS_DIR/$dst" --local-dir-use-symlinks False
}

# ============================================================
# IMAGE (SDXL + FLUX)
# ============================================================
if [ "$PROFILE" = "image" ] || [ "$PROFILE" = "full" ]; then
  echo "=== IMAGE MODELS ==="

  # SDXL 1.0 base
  download "stabilityai/stable-diffusion-xl-base-1.0" \
    "sd_xl_base_1.0.safetensors" "checkpoints"

  # SDXL Refiner (opcional)
  download "stabilityai/stable-diffusion-xl-refiner-1.0" \
    "sd_xl_refiner_1.0.safetensors" "checkpoints"

  # FLUX.1 dev (gated — requiere HF_TOKEN con aprobación de licencia)
  download "black-forest-labs/FLUX.1-dev" \
    "flux1-dev.safetensors" "checkpoints"

  # FLUX text encoders
  download "comfyanonymous/flux_text_encoders" \
    "clip_l.safetensors" "clip"
  download "comfyanonymous/flux_text_encoders" \
    "t5xxl_fp16.safetensors" "clip"

  # FLUX VAE
  download "black-forest-labs/FLUX.1-dev" \
    "ae.safetensors" "vae"

  # SDXL VAE (fp16 fix)
  download "madebyollin/sdxl-vae-fp16-fix" \
    "sdxl_vae.safetensors" "vae"

  # ControlNet Union SDXL (todos-en-uno)
  download "xinsir/controlnet-union-sdxl-1.0" \
    "diffusion_pytorch_model_promax.safetensors" "controlnet"

  # Upscaler
  download "Kim2091/UltraSharp" \
    "4x-UltraSharp.pth" "upscale_models"
fi

# ============================================================
# VIDEO (Wan 2.2 + HunyuanVideo)
# ============================================================
if [ "$PROFILE" = "video" ] || [ "$PROFILE" = "full" ]; then
  echo "=== VIDEO MODELS ==="

  # Wan 2.2 TI2V 5B — el más ligero (16 GB VRAM ok)
  # Repo oficial: Wan-AI/Wan2.2-TI2V-5B
  # Formato safetensors para ComfyUI
  download "Wan-AI/Wan2.2-TI2V-5B" \
    "high_noise_model/diffusion_pytorch_model-00001-of-00006.safetensors" \
    "diffusion_models/wan2.2-ti2v-5b" || echo "  ⚠ Wan 2.2 5B falló (multi-file, use huggingface-cli download completo)"

  # Wan 2.2 requiere descarga completa del repo con snapshot_download
  # Comentado: descomentar si tienes >100 GB libres
  # hf snapshot-download Wan-AI/Wan2.2-TI2V-5B --local-dir $MODELS_DIR/diffusion_models/wan2.2-ti2v-5b

  # LTX-Video (alternativa más ligera)
  download "Lightricks/LTX-Video" \
    "ltx-video-2b-v0.9.5.safetensors" "checkpoints" || true

  # AnimateDiff v3
  download "guoyww/animatediff-motion-adapter-v1-5-3" \
    "diffusion_pytorch_model.safetensors" "animatediff_models" || true
fi

# ============================================================
# PORTRAIT / AUDIO-DRIVEN
# ============================================================
if [ "$PROFILE" = "video" ] || [ "$PROFILE" = "full" ]; then
  echo "=== PORTRAIT ANIMATION ==="
  # Sonic weights (usa el custom node ComfyUI-Sonic)
  # Nota: Sonic descarga sus pesos en el primer run
  echo "  Sonic: se descargará automáticamente en el primer run del nodo"
fi

echo
echo "== Estado ==================="
du -sh "$MODELS_DIR"/*/ 2>/dev/null | sort -h
echo "=============================="
