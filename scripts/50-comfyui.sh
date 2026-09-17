#!/usr/bin/env bash
# Instala ComfyUI + venv Python 3.12 + PyTorch cu128 + xformers + sage/flash-attn + ComfyUI-Manager.
# Corre COMO usuario admin (no root). Requiere driver NVIDIA ya funcional (nvidia-smi ok).
set -euo pipefail

if ! command -v nvidia-smi >/dev/null || ! nvidia-smi >/dev/null 2>&1; then
  echo "[comfyui] nvidia-smi no responde. Instala driver primero (40-gpu-nvidia.sh)." >&2
  exit 1
fi

sudo apt-get update
sudo apt-get install -y git python3.12 python3.12-venv python3-pip build-essential nginx

sudo install -d -o "${USER}" -g "${USER}" /opt/comfyui
[ -d /opt/comfyui/.git ] || git clone https://github.com/comfyanonymous/ComfyUI /opt/comfyui

cd /opt/comfyui
[ -d venv ] || python3.12 -m venv venv
# shellcheck disable=SC1091
source venv/bin/activate
pip install --upgrade pip wheel

# PyTorch cu128 (más wheels de sage/flash para SM 8.9 que cu130)
pip install --index-url https://download.pytorch.org/whl/cu128 torch torchvision torchaudio

pip install -r requirements.txt

# Aceleradores para Wan 2.2 / Sonic
pip install --index-url https://download.pytorch.org/whl/cu128 xformers || true
pip install sageattention || true
pip install flash-attn --no-build-isolation || true

# ComfyUI-Manager
mkdir -p custom_nodes
[ -d custom_nodes/ComfyUI-Manager ] || git clone \
  https://github.com/ltdrdata/ComfyUI-Manager custom_nodes/ComfyUI-Manager

# Systemd service
sudo tee /etc/systemd/system/comfyui.service >/dev/null <<EOF
[Unit]
Description=ComfyUI
After=network.target

[Service]
Type=simple
User=${USER}
WorkingDirectory=/opt/comfyui
Environment=PATH=/opt/comfyui/venv/bin:/usr/bin:/usr/local/cuda/bin
ExecStart=/opt/comfyui/venv/bin/python main.py --listen 127.0.0.1 --port 8188
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now comfyui

echo "[comfyui] escuchando en 127.0.0.1:8188"
echo "[comfyui] acceso: ssh -L 8188:127.0.0.1:8188 <server> y abre http://localhost:8188"
