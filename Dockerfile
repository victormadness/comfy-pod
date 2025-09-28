# CUDA 12.8 + cuDNN (Ubuntu 22.04)
FROM nvidia/cuda:12.8.0-cudnn-runtime-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PYTHONUNBUFFERED=1

# База: Python, git, ffmpeg, нужные системные либы
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 python3-venv python3-pip git ffmpeg \
    libgl1 libglib2.0-0 build-essential pkg-config \
    ca-certificates rsync \
    && rm -rf /var/lib/apt/lists/*

# Точка входа
WORKDIR /runner
COPY bootstrap.sh /runner/bootstrap.sh
# НОРМАЛИЗУЕМ ПЕРЕНОСЫ И ДАЁМ ПРАВА
RUN sed -i 's/\r$//' /runner/bootstrap.sh && chmod +x /runner/bootstrap.sh
ENTRYPOINT ["/runner/bootstrap.sh"]
