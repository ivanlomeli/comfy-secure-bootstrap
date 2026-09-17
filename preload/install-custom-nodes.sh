#!/usr/bin/env bash
# Instala el set canónico de custom nodes verificados.
# Corre COMO el usuario `comfyui` (o `ubuntu` si aún no hay sandbox).
set -euo pipefail

COMFY_DIR="${COMFY_DIR:-/opt/comfyui}"
CN="$COMFY_DIR/custom_nodes"
VENV_PIP="$COMFY_DIR/venv/bin/pip"

if [ ! -d "$COMFY_DIR" ]; then
  echo "$COMFY_DIR no existe. Corre primero el bootstrap." >&2
  exit 1
fi

mkdir -p "$CN"
cd "$CN"

# Lista de custom nodes: <owner>/<repo> [branch]
NODES=(
  # Gestor
  "ltdrdata/ComfyUI-Manager"
  # Video helpers
  "Kosinkadink/ComfyUI-VideoHelperSuite"
  # Utilidades esenciales
  "rgthree/rgthree-comfy"
  "kijai/ComfyUI-KJNodes"
  "ltdrdata/ComfyUI-Impact-Pack"
  "ltdrdata/ComfyUI-Impact-Subpack"
  "WASasquatch/was-node-suite-comfyui"
  # ControlNet avanzado
  "Kosinkadink/ComfyUI-Advanced-ControlNet"
  # AnimateDiff
  "Kosinkadink/ComfyUI-AnimateDiff-Evolved"
  # Wan 2.2
  "kijai/ComfyUI-WanVideoWrapper"
  # Sonic (audio → face animation)
  "smthemex/ComfyUI-Sonic"
  # Frame interpolation (para output video suave)
  "Fannovel16/ComfyUI-Frame-Interpolation"
  # IPAdapter (style transfer)
  "cubiq/ComfyUI_IPAdapter_plus"
  # SAM 2 (segmentación)
  "kijai/ComfyUI-segment-anything-2"
  # Florence2 (image → text)
  "kijai/ComfyUI-Florence2"
  # Background removal
  "1038lab/ComfyUI-BRIA_AI-RMBG"
  # HunyuanVideo wrapper
  "kijai/ComfyUI-HunyuanVideoWrapper"
  # LTX-Video wrapper
  "logtd/ComfyUI-LTXTricks"
  # LoRA loaders extra
  "chrisgoringe/cg-use-everywhere"
  # Preview / debug
  "chrisgoringe/cg-image-picker"
)

for entry in "${NODES[@]}"; do
  slug=$(echo "$entry" | cut -d' ' -f1)
  name=$(basename "$slug")
  if [ -d "$name" ]; then
    echo "[$name] update"
    (cd "$name" && git pull --ff-only 2>&1 | tail -1) || true
  else
    echo "[$name] clone"
    git clone --depth 1 "https://github.com/$slug" "$name" 2>&1 | tail -2
  fi

  # Instalar requirements si existen
  if [ -f "$name/requirements.txt" ]; then
    "$VENV_PIP" install --quiet -r "$name/requirements.txt" 2>&1 | tail -3 || true
  fi
  # install.py (Impact Pack, etc)
  if [ -f "$name/install.py" ]; then
    "$COMFY_DIR/venv/bin/python" "$name/install.py" 2>&1 | tail -3 || true
  fi
done

echo
echo "== custom_nodes instalados =="
ls -1 "$CN" | sort
echo
echo "Reinicia ComfyUI para cargarlos: sudo systemctl restart comfyui"
