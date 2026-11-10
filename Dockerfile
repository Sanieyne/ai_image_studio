# Base image: Official PyTorch with CUDA 12.8 & cuDNN 9 (supports sm_75 to sm_120: RTX 20xx up to RTX 50xx / CMP 170HX)
FROM pytorch/pytorch:2.11.0-cuda12.8-cudnn9-runtime

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_BREAK_SYSTEM_PACKAGES=1 \
    AI_STUDIO_MODE=cloud \
    HF_HUB_OFFLINE=1 \
    AI_STUDIO_MODELS_DIR=/workspace/models \
    AI_STUDIO_HOST=0.0.0.0 \
    AI_STUDIO_PORT=8000

LABEL org.opencontainers.image.source="https://github.com/Sanieyne/ai_image_studio" \
      org.opencontainers.image.description="AI Image Studio Cloud GPU Engine"

WORKDIR /workspace

# 1. Install OS-level dependencies (media, headless GL, ffmpeg, OpenSSH for Vast.ai)
RUN apt-get update -qq && \
    apt-get install -y -qq --no-install-recommends \
        curl \
        wget \
        git \
        ca-certificates \
        libgl1 \
        libglib2.0-0 \
        libsm6 \
        libxext6 \
        libxrender1 \
        ffmpeg \
        openssh-server \
        tar \
        gzip && \
    rm -rf /var/lib/apt/lists/*

# 2. Copy dependency manifests
COPY python_engine/requirements-cloud.lock /workspace/python_engine/
COPY python_engine/constraints-cloud.txt /workspace/python_engine/

# 3. Install pre-tested & locked Python packages
RUN python3 -m pip install -r /workspace/python_engine/requirements-cloud.lock \
        -c /workspace/python_engine/constraints-cloud.txt \
        --extra-index-url https://download.pytorch.org/whl/cu128 && \
    python3 -m pip install torchao && \
    python3 -m pip install --no-deps chatterbox-tts==0.1.7 && \
    python3 -m pip install opencv-python-headless onnxruntime-gpu scikit-image ftfy av boto3 && \
    python3 -m pip install --no-deps insightface

# 4. Configure dynamic linker so ONNX Runtime GPU finds cuDNN / CUDA 12
RUN python3 -c 'import glob; print("\n".join(glob.glob("/usr/local/lib/python*/dist-packages/nvidia/*/lib")))' > /etc/ld.so.conf.d/nvidia_pip.conf && \
    ldconfig

# 5. Copy the full python_engine source code
COPY python_engine /workspace/python_engine

# 6. Run self-test inside container build to guarantee zero broken imports
WORKDIR /workspace/python_engine
RUN AI_STUDIO_MOCK=1 python3 self_test.py

EXPOSE 8000

CMD ["python3", "app.py"]
