#!/usr/bin/env bash
set -euo pipefail

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
NEED_REPAIR=0
[ ! -f "${CUI}/main.py" ] && NEED_REPAIR=1
[ ! -d "${CUI}/comfy/ldm/models" ] && NEED_REPAIR=1
if [ "${FORCE_REPAIR:-0}" = "1" ]; then NEED_REPAIR=1; fi

if [ $NEED_REPAIR -eq 1 ]; then
  echo "[setup] (re)installing ComfyUI code into ${CUI}"
  tmp="${PV}/.comfy_src.$$"
  git clone https://github.com/comfyanonymous/ComfyUI.git "${tmp}"

  # preserve your data
  keep="${PV}/.keep.$$"; mkdir -p "${keep}"
  mv "${CUI}/models"        "${keep}/models"        2>/dev/null || true
  mv "${CUI}/custom_nodes"  "${keep}/custom_nodes"  2>/dev/null || true
  mv "${CUI}/user"          "${keep}/user"          2>/dev/null || true

  rm -rf "${CUI}"
  mkdir -p "${CUI}"

  # copy whole repo (no excludes to avoid breaking comfy/ldm/models)
  rsync -a "${tmp}/" "${CUI}/" || (cd "${tmp}" && tar cf - .) | (cd "${CUI}" && tar xf -)

  # restore your data
  mv "${keep}/models"        "${CUI}/models"        2>/dev/null || true
  mv "${keep}/custom_nodes"  "${CUI}/custom_nodes"  2>/dev/null || true
  mv "${keep}/user"          "${CUI}/user"          2>/dev/null || true
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
  pip install --extra-index-url https://download.pytorch.org/whl/cu124 \
    torch==2.8.0 torchaudio==2.8.0 || true
  pip install --extra-index-url https://download.pytorch.org/whl/cu124 \
    'torchvision==0.23.*' || pip install --extra-index-url https://download.pytorch.org/whl/cu124 torchvision || true

  # SageAttention + video stack
  pip install -q \
    sageattention einops accelerate safetensors transformers \
    opencv-python av decord imageio[ffmpeg] moviepy tqdm requests httpx || true

  # Repo & custom node requirements (if present)
  [ -f "${CUI}/requirements.txt" ] && pip install -r "${CUI}/requirements.txt" || true
  if [ -d "${CUI}/custom_nodes" ]; then
    find "${CUI}/custom_nodes" -maxdepth 2 -type f -name requirements.txt -print0 \
    | while IFS= read -r -d '' req; do
        echo "[b]()
