#!/usr/bin/env bash
set -euo pipefail

PV="/workspace"                # постоянный диск RunPod
CUI="${PV}/ComfyUI"            # здесь живёт ВСЁ (код, models, custom_nodes, user)
VENV="${PV}/venv"

# 0) гарантируем структуру
mkdir -p "${CUI}/models" "${CUI}/custom_nodes" "${CUI}/user" \
         "${PV}/inputs" "${PV}/outputs" "${PV}/temp"

# 0.1) кэши на PV (ускоряет pip/HF/torch и исключает повторные скачивания)
export PIP_CACHE_DIR="${PV}/.cache/pip"
export HF_HOME="${PV}/.cache/huggingface"
export TORCH_HOME="${PV}/.cache/torch"
mkdir -p "$PIP_CACHE_DIR" "$HF_HOME" "$TORCH_HOME"

# 1) если кода ComfyUI нет — аккуратно «дольём», не трогая models/custom_nodes/user
if [ ! -f "${CUI}/main.py" ]; then
  echo "[setup] Installing ComfyUI code into ${CUI}"
  tmp="${PV}/.comfy_src.$$"
  git clone https://github.com/comfyanonymous/ComfyUI.git "${tmp}"

  if command -v rsync >/dev/null 2>&1; then
    rsync -a --delete --exclude 'models' --exclude 'custom_nodes' --exclude 'user' "${tmp}/" "${CUI}/"
  else
    (cd "${tmp}" && tar c --exclude=models --exclude=custom_nodes --exclude=user .) | (cd "${CUI}" && tar x)
  fi

  # перенесём .git, чтобы потом можно было обновляться из Manager
  [ -d "${CUI}/.git" ] || mv "${tmp}/.git" "${CUI}/.git" || true
  rm -rf "${tmp}"
else
  echo "[setup] ComfyUI code already present at ${CUI}"
fi

# 2) venv на PV (разовая установка зависимостей)
if [ ! -d "${VENV}" ]; then
  echo "[setup] Creating venv at ${VENV}"
  python3 -m venv --system-site-packages "${VENV}"
fi
# shellcheck disable=SC1090
source "${VENV}/bin/activate"
python -m pip install --upgrade pip

# 3) PyTorch 2.8 под CUDA 12.x (cu124), Triton подтянется автоматически
if ! python -c "import torch; import torchaudio; print(torch.__version__)" 2>/dev/null | grep -q '^2\.8\.'; then
  echo "[setup] Installing PyTorch 2.8.x (CUDA 12.x wheels)"
  pip install --extra-index-url https://download.pytorch.org/whl/cu124 \
    torch==2.8.0 torchaudio==2.8.0
  # torchvision для torch 2.8 — ветка 0.23.*
  pip install --extra-index-url https://download.pytorch.org/whl/cu124 \
    'torchvision==0.23.*' || \
  pip install --extra-index-url https://download.pytorch.org/whl/cu124 torchvision
fi

# 4) Wan/SageAttention и видео-стек (один раз)
pip install -q \
  sageattention einops accelerate safetensors transformers \
  opencv-python av decord imageio[ffmpeg] moviepy tqdm requests httpx

# 5) зависимости самого ComfyUI (если есть)
[ -f "${CUI}/requirements.txt" ] && pip install -r "${CUI}/requirements.txt" || true

# 6) зависимости кастом-нод (requirements.txt внутри них, если присутствуют)
if [ -d "${CUI}/custom_nodes" ]; then
  find "${CUI}/custom_nodes" -maxdepth 2 -type f -name requirements.txt -print0 \
  | while IFS= read -r -d '' req; do
      echo "[setup] pip install -r ${req}"
      pip install -r "${req}" || true
    done
fi

# 7) старт ComfyUI
cd "${CUI}"
exec python main.py \
  --listen 0.0.0.0 --port "${PORT:-8188}" \
  --user-directory "${CUI}/user" \
  --input-directory  "${PV}/inputs" \
  --output-directory "${PV}/outputs" \
  --temp-directory   "${PV}/temp" \
  --preview-method auto
