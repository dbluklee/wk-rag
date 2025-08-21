# CHEESEADE RAG Server Dockerfile - Flexible CPU/GPU Support
FROM nvidia/cuda:12.1.1-cudnn8-runtime-ubuntu22.04 AS base

# 빌드 인자로 CUDA/CPU 선택
ARG USE_CUDA=true
ARG CUDA_VERSION=cu121

# 환경변수
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONPATH=/app \
    DEBIAN_FRONTEND=noninteractive \
    LANG=C.UTF-8

# 시스템 패키지 설치
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3.11 \
    python3.11-dev \
    python3-pip \
    python3.11-venv \
    build-essential \
    cmake \
    curl \
    wget \
    git \
    && ln -s /usr/bin/python3.11 /usr/bin/python \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# CUDA 관련 패키지 (CUDA 사용시만)
RUN if [ "$USE_CUDA" = "true" ]; then \
    apt-get update && apt-get install -y --no-install-recommends \
        nvidia-cuda-toolkit \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*; \
    fi

# PyTorch 설치 스테이지
FROM base AS pytorch

WORKDIR /app
COPY requirements.txt .

# PyTorch 설치 (CUDA/CPU 분기)
RUN pip install --upgrade pip && \
    if [ "$USE_CUDA" = "true" ]; then \
        echo "Installing CUDA version of PyTorch..." && \
        pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/${CUDA_VERSION}; \
    else \
        echo "Installing CPU version of PyTorch..." && \
        pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cpu; \
    fi

# 나머지 패키지 설치 (PyTorch 제외된 requirements.txt)
RUN pip install --no-cache-dir -r requirements.txt

# 애플리케이션 스테이지
FROM pytorch AS app

# 사용자 생성 및 홈 디렉토리 권한 설정
RUN groupadd -r appuser && useradd -r -g appuser -m -d /home/appuser appuser

# HuggingFace 캐시 디렉토리 미리 생성 및 권한 설정
RUN mkdir -p /home/appuser/.cache/huggingface \
    && chown -R appuser:appuser /home/appuser \
    && chmod -R 755 /home/appuser

# 애플리케이션 복사
COPY --chown=appuser:appuser . .

# 권한 설정
RUN mkdir -p docs logs \
    && chown -R appuser:appuser /app \
    && chmod +x startup.sh

USER appuser
EXPOSE 8000
VOLUME ["/app/docs", "/app/logs"]

# 헬스체크
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:8000/health || exit 1

CMD ["./startup.sh"]