#!/usr/bin/env bash
# Verifica driver NVIDIA + CUDA. Solo si detecta GPU NVIDIA presente.
# En una AMI DLAMI Ubuntu 24.04 (jun-2026+) el driver 595.71.05 + CUDA 12.8/12.9/13.x ya viene instalado.
# En Ubuntu vanilla: instala el driver desde el repo oficial NVIDIA.
set -euo pipefail

if ! lspci | grep -qi nvidia; then
  echo "[gpu] sin NVIDIA detectada — skip"
  exit 0
fi

if command -v nvidia-smi >/dev/null && nvidia-smi >/dev/null 2>&1; then
  echo "[gpu] driver ya instalado: $(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -1)"
  exit 0
fi

echo "[gpu] instalando driver desde repo NVIDIA…"
export DEBIAN_FRONTEND=noninteractive
apt-get update

# Ubuntu-provided (más simple; para L40S SM 8.9 basta driver >=570)
apt-get -y install ubuntu-drivers-common
ubuntu-drivers install --gpgpu

echo "[gpu] driver instalado. REINICIAR requerido: sudo reboot"
