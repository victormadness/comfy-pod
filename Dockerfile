# CUDA 12.8 + cuDNN (Ubuntu 22.04)
FROM nvidia/cuda:12.8.0-cudnn-runtime-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive \
    PIP_NO_CACHE_DIR=1 PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PYTHONUNBUFFERED=1

# База: Python, git, ffmpeg, нужные системные либы
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 python3-venv python3-pip git ffmpeg \
    libgl1 libglib2.0-0 build-essential pkg-config \
    ca-certificates rsync \
    && rm -rf /var/lib/apt/lists/*

# PyTorch 2.8 (CUDA 12.x)
RUN python3 -m pip install --upgrade pip wheel setuptools && \
    python3 -m pip install --extra-index-url https://download.pytorch.org/whl/cu124 \
      torch==2.8.0 torchaudio==2.8.0 && \
    python3 -m pip install --extra-index-url https://download.pytorch.org/whl/cu124 \
      'torchvision==0.23.*'

# SageAttention + стек для WAN/WanVideoWrapper
RUN python3 -m pip install \
      sageattention einops accelerate safetensors transformers \
      opencv-python av decord imageio[ffmpeg] moviepy tqdm requests httpx

WORKDIR /runner
COPY bootstrap.sh /runner/bootstrap.sh
RUN chmod +x /runner/bootstrap.sh
ENTRYPOINT ["/runner/bootstrap.sh"]


