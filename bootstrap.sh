#!/usr/bin/env bash
set -euo pipefail

PV="/workspace"
CUI="${PV}/ComfyUI"
VENV="${PV}/venv"

mkdir -p "${CUI}/models" "${CUI}/custom_nodes" "${CUI}/user" \
         "${PV}/inputs" "${PV}/outputs" "${PV}/temp"

# Кэши на PV (ускоряет pip/HF)
export PIP_CACHE_DIR="${PV}/.cache/pip"
export HF_HOME="${PV}/.cache/huggingface"
export TORCH_HOME="${PV}/.cache/torch"
mkdir -p "$PIP_CACHE_DIR" "$HF_HOME" "$TORCH_HOME"

if [ ! -f "${CUI}/main.py" ]; then
  echo "[setup] Installing ComfyUI code into ${CUI}"
  tmp="${PV}/.comfy_src.$$"
  git clone https://github.com/comfyanonymous/ComfyUI.git "${tmp}"

  if command -v rsync >/dev/null 2>&1; then
    rsync -a --delete --exclude 'models' --exclude 'custom_nodes' --exclude 'user' "${tmp}/" "${CUI}/"
  else
    # fallback без rsync
    (cd "${tmp}" && tar c --exclude=models --exclude=custom_nodes --exclude=user .) | (cd "${CUI}" && tar x)
  fi

  [ -d "${CUI}/.git" ] || mv "${tmp}/.git" "${CUI}/.git" || true
  rm -rf "${tmp}"
else
  echo "[setup] ComfyUI code already present at ${CUI}"
fi

if [ ! -d "${VENV}" ]; then
  echo "[setup] Creating venv at ${VENV}"
  python3 -m venv --system-site-packages "${VENV}"
fi
# shellcheck disable=SC1090
source "${VENV}/bin/activate"
python -m pip install --upgrade pip

[ -f "${CUI}/requirements.txt" ] && pip install -r "${CUI}/requirements.txt" || true

if [ -d "${CUI}/custom_nodes" ]; then
  find "${CUI}/custom_nodes" -maxdepth 2 -type f -name requirements.txt -print0 \
  | while IFS= read -r -d '' req; do
      echo "[setup] pip install -r ${req}"
      pip install -r "${req}" || true
    done
fi

cd "${CUI}"
exec python main.py \
  --listen 0.0.0.0 --port "${PORT:-8188}" \
  --user-directory "${CUI}/user" \
  --input-directory  "${PV}/inputs" \
  --output-directory "${PV}/outputs" \
  --temp-directory   "${PV}/temp" \
  --preview-method auto
