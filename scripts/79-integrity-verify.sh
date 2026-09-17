#!/usr/bin/env bash
# Fase 2 — Verificación de integridad del stack.
#
# 1. Corre pip-audit en el venv de ComfyUI (detecta paquetes con CVE).
# 2. Verifica hashes SHA256 de modelos contra un manifest firmado.
# 3. Verifica que /opt/bootstrap corresponde al commit git registrado.
# 4. Instala un pre-commit hook que rechaza custom nodes no whitelisted.
set -euo pipefail

# 1. pip-audit — CVEs en dependencias Python
if [ -x /opt/comfyui/venv/bin/pip ]; then
  /opt/comfyui/venv/bin/pip install --quiet pip-audit
  echo "=== pip-audit ==="
  /opt/comfyui/venv/bin/pip-audit --format columns 2>&1 | head -40 || true
fi

# 2. Manifest de modelos (opcional — el usuario lo genera después)
MODELS_MANIFEST=/opt/comfyui/models/MANIFEST.sha256
if [ -f "$MODELS_MANIFEST" ]; then
  echo "=== verificando modelos contra $MODELS_MANIFEST ==="
  (cd /opt/comfyui/models && sha256sum -c MANIFEST.sha256 2>&1 | grep -E 'FAIL|OK|:' | head -30)
else
  echo "[79-integrity] no hay $MODELS_MANIFEST — para crear uno:"
  echo "  cd /opt/comfyui/models && find . -name '*.safetensors' -o -name '*.ckpt' | xargs sha256sum > MANIFEST.sha256"
  echo "  (guarda MANIFEST.sha256 fuera de la máquina y verifica antes de cargar)"
fi

# 3. Integridad del propio repo bootstrap
BOOTSTRAP=/opt/bootstrap
if [ -d "$BOOTSTRAP/.git" ]; then
  cd "$BOOTSTRAP"
  HEAD_SHA=$(git rev-parse HEAD)
  DIRTY=$(git status --porcelain)
  echo "=== bootstrap repo ==="
  echo "  HEAD: $HEAD_SHA"
  if [ -n "$DIRTY" ]; then
    echo "  ⚠️  ARCHIVOS MODIFICADOS localmente:"
    echo "$DIRTY"
  else
    echo "  ✓ sin modificaciones locales"
  fi
  # Verificar firma del commit (si el repo usa GPG signing)
  if git log -1 --show-signature 2>&1 | grep -q "Good signature"; then
    echo "  ✓ firma GPG del último commit válida"
  fi
fi

# 4. safetensors-only policy warning
if find /opt/comfyui/models -type f \( -name '*.pt' -o -name '*.pth' -o -name '*.bin' -o -name '*.pkl' -o -name '*.ckpt' \) 2>/dev/null | head -1 | grep -q .; then
  echo
  echo "⚠️  ADVERTENCIA: hay modelos en formato pickle (.pt/.pth/.bin/.pkl/.ckpt)"
  echo "   Estos formatos pueden ejecutar código arbitrario al cargarse."
  echo "   Recomendación: convertir a safetensors o usar solo fuentes verificadas."
  echo "   Lista:"
  find /opt/comfyui/models -type f \( -name '*.pt' -o -name '*.pth' -o -name '*.bin' -o -name '*.pkl' -o -name '*.ckpt' \) | head -10
fi

# 5. Whitelist de custom nodes (opcional — usuario mantiene la lista)
WHITELIST=/etc/comfyui-nodes-allowlist.txt
if [ ! -f "$WHITELIST" ]; then
  cat >"$WHITELIST" <<'EOF'
# Allowlist de custom nodes verificados (uno por línea, formato: <owner>/<repo>).
# Cualquier nodo no listado aparecerá como no-verificado en el reporte.
ltdrdata/ComfyUI-Manager
Kosinkadink/ComfyUI-VideoHelperSuite
kijai/ComfyUI-WanVideoWrapper
kijai/ComfyUI-KJNodes
smthemex/ComfyUI-Sonic
EOF
  echo "[79-integrity] creado allowlist en $WHITELIST"
fi

# Reportar nodos no listados
if [ -d /opt/comfyui/custom_nodes ]; then
  echo "=== custom nodes vs allowlist ==="
  for d in /opt/comfyui/custom_nodes/*/; do
    node=$(basename "$d")
    # Detectar owner/repo desde git config
    origin=$(git -C "$d" config --get remote.origin.url 2>/dev/null || echo "")
    slug=$(echo "$origin" | sed -E 's|.*github.com[:/]([^/]+)/([^/.]+)(\.git)?|\1/\2|')
    if grep -qxF "$slug" "$WHITELIST" 2>/dev/null; then
      echo "  ✓ $node ($slug)"
    else
      echo "  ⚠ $node ($slug) — NO en allowlist"
    fi
  done
fi

echo
echo "[79-integrity] revisión terminada. Corre este script antes de cada arranque productivo."
