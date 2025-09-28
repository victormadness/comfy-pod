#!/usr/bin/env bash
set -Eeuo pipefail

# Логирование причины падения (если вдруг)
trap 'code=$?; echo "[FATAL] line ${LINENO}: ${BASH_COMMAND} (exit $code)"; exit $code' ERR

PV="/workspace"
CUI="${PV}/ComfyUI"
VENV="${PV}/venv"

# --- CACHE: PV (default) or /tmp (ephemeral) ---
CACHE_MODE="${CACHE_MODE:-pv}"   # pv | tmp
if [ "$CACHE_MODE" = "tmp" ]; then base="/tmp/.cache"; else base="${PV}/.cache"; fi
export PIP_CACHE_DIR="${PIP_CACHE_DIR:-$base/pip}"
export HF_HOME="${HF_HOME:-$base/huggingface}"
export TORCH_HOME="${TORCH_HOME:-$base/torch}"
export TORCHINDUCTOR_CACHE_DIR="${TORCHINDUCTOR_CACHE_DIR:-$base/torchinductor}"
export TRITON_CACHE_DIR="${TRITON_CACHE_DIR:-$base/triton}"
mkdir -p "$PIP_CACHE_DIR" "$HF_HOME" "$TORCH_HOME" "$TORCHINDUCTOR_CACHE_DIR" "$TRITON_CACHE_DIR"

# --- Ensure base structure ---
mkdir -p "${CUI}/models" "${CUI}/custom_nodes" "${CUI}/user" \
         "${PV}/inputs" "${PV}/outputs" "${PV}/temp"

# --- Install/repair ComfyUI code on PV ---
need_repair=0
[ ! -f "${CUI}/main.py" ] && need_repair=1
[ ! -d "${CUI}/comfy/ldm/models" ] && need_repair=1
if [ "${FORCE_REPAIR:-0}" = "1" ]; then need_repair=1; fi

if [ "$need_repair" -eq 1 ]; then
  echo "[setup] (re)installing ComfyUI code into ${CUI}"
  tmp="${PV}/.comfy_src.$$"
  rm -rf "$tmp"
  git clone https://github.com/comfyanonymous/ComfyUI.git "$tmp"

  # preserve user data
  keep="${PV}/.keep.$$"; rm -rf "$keep"; mkdir -p "$keep"
  [ -d "${CUI}/models" ]       && mv "${CUI}/models"       "${keep}/models"
  [ -d "${CUI}/custom_nodes" ] && mv "${CUI}/custom_nodes" "${keep}/custom_nodes"
  [ -d "${CUI}/user" ]         && mv "${CUI}/user"         "${keep}/user"

  rm -rf "${CUI}"; mkdir -p "${CUI}"

  if command -v rsync >/dev/null 2>&1; then
    rsync -a "${tmp}/" "${CUI}/"
  else
    (cd "${tmp}" && tar -cf - .) | (cd "${CUI}" && tar -xf -)
  fi

  # restore user data
  [ -d "${keep}/models" ]       && mv "${keep}/models"       "${CUI}/models"
  [ -d "${keep}/custom_nodes" ] && mv "${keep}/custom_nodes" "${CUI}/custom_nodes"
  [ -d "${keep}/user" ]         && mv "${keep}/user"         "${CUI}/user"
  rm -rf "${keep}" "${tmp}"
else
  echo "[setup] ComfyUI code OK at ${CUI}"
fi

# --- venv on PV ---
if [ ! -d "${VENV}" ]; then
  echo "[setup] Creating venv at ${VENV}"
  python3 -m venv --system-site-packages "${VENV}"
fi
# shellcheck disable=SC1090
source "${VENV}/bin/activate"
python -m pip install --upgrade pip

# --- One-time deps ---
DEPS_SENTINEL="${PV}/.deps_ok"
if [ ! -f "$DEPS_SENTINEL" ]; then
  echo "[setup] Installing runtime deps (first run)"

  # PyTorch 2.8 (CUDA 12.x wheels)
  pip install --extra-index-url https://download.pytorch.org/whl/cu124 torch==2.8.0 torchaudio==2.8.0 || true
  # torchvision под torch 2.8
  pip install --extra-index-url https://download.pytorch.org/whl/cu124 "torchvision==0.23.*" \
    || pip install --extra-index-url https://download.pytorch.org/whl/cu124 torchvision || true

  # SageAttention + видео-стек
  pip install -q sageattention einops accelerate safetensors transformers \
    opencv-python av decord imageio[ffmpeg] moviepy tqdm requests httpx || true

  # requirements ядра и кастом-нод
  if [ -f "${CUI}/requirements.txt" ]; then
    pip install -r "${CUI}/requirements.txt" || true
  fi
  if [ -d "${CUI}/custom_nodes" ]; then
    while IFS= read -r -d '' req; do
      echo "[bootstrap] pip install -r ${req}"
      pip install -r "${req}" || true
    done < <(find "${CUI}/custom_nodes" -maxdepth 2 -type f -name requirements.txt -print0)
  fi

  touch "$DEPS_SENTINEL"
else
  echo "[setup] Runtime deps already installed (skipping)"
fi

# --- Start ComfyUI ---
cd "${CUI}"
exec python main.py \
  --listen 0.0.0.0 --port "${PORT:-8188}" \
  --user-directory "${CUI}/user" \
  --input-directory  "${PV}/inputs" \
  --output-directory "${PV}/outputs" \
  --temp-directory   "${PV}/temp" \
  --preview-method auto
