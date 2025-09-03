# Phygrid CUDA - Common Base Image
# Contains shared system dependencies and tools for all inference engines
# Supports both Intel (x64) and ARM architectures

# Use multi-stage build with architecture-specific base images
ARG TARGETARCH
FROM python:3.11-slim AS base-amd64
FROM nvidia/cuda:12.8.1-devel-ubuntu22.04 AS base-arm64

# Select appropriate base based on target architecture  
FROM base-${TARGETARCH} AS base

# Set architecture-aware variables
ARG TARGETARCH
ARG TARGETPLATFORM

WORKDIR /app

# Install Python 3.10 on ARM64 CUDA base (Ubuntu 22.04 already has Python 3.10)
RUN if [ "$TARGETARCH" = "arm64" ]; then \
        apt-get update && apt-get install -y \
        python3 \
        python3-dev \
        python3-venv \
        python3-pip \
        && update-alternatives --install /usr/bin/python python /usr/bin/python3 1; \
    fi

# Install system dependencies common to all services
RUN apt-get update && apt-get install -y \
    # Build tools
    build-essential \
    cmake \
    git \
    wget \
    curl \
    unzip \
    # Audio processing
    libasound2-dev \
    portaudio19-dev \
    libsndfile1 \
    ffmpeg \
    # Image processing
    libgl1 \
    libglib2.0-0 \
    libsm6 \
    libxext6 \
    libxrender-dev \
    libgomp1 \
    # Networking and utilities
    ca-certificates \
    # Fix for executable stack issues
    patchelf \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

# Upgrade pip and install common Python packages
RUN python3 -m pip install --no-cache-dir --upgrade pip setuptools wheel

# Install common web framework packages (lightweight versions)
RUN python3 -m pip install --no-cache-dir \
    fastapi==0.104.1 \
    uvicorn[standard]==0.24.0 \
    python-multipart==0.0.6 \
    pydantic==2.5.0 \
    starlette==0.27.0 \
    typing-extensions>=4.8.0

# Install common utility packages with ARM64-compatible versions
RUN python3 -m pip install --no-cache-dir \
    numpy==1.24.4 \
    pillow==10.1.0 \
    requests==2.31.0 \
    aiofiles==23.2.1 \
    python-dotenv==1.0.0

# Set up common environment variables
ENV PYTHONUNBUFFERED=1
ENV PYTHONDONTWRITEBYTECODE=1
ENV PIP_NO_CACHE_DIR=1
ENV PIP_DISABLE_PIP_VERSION_CHECK=1

# Set CUDA-specific environment variables for ARM64 Jetson
RUN if [ "$TARGETARCH" = "arm64" ]; then \
        echo 'export PATH=/usr/local/cuda/bin:$PATH' >> /etc/environment && \
        echo 'export LD_LIBRARY_PATH=/usr/local/cuda/lib64:$LD_LIBRARY_PATH' >> /etc/environment && \
        echo 'export CUDA_HOME=/usr/local/cuda' >> /etc/environment; \
    fi

ENV PATH="/usr/local/cuda/bin:${PATH}"
ENV LD_LIBRARY_PATH="/usr/local/cuda/lib64:${LD_LIBRARY_PATH}"
ENV CUDA_HOME="/usr/local/cuda"

# Create common directories
RUN mkdir -p /app/cache /app/models /app/data /app/logs

# Create non-root user for security
RUN groupadd -r appuser && useradd -r -g appuser appuser
RUN chown -R appuser:appuser /app

# Health check endpoint (services can override)
COPY --chown=appuser:appuser <<EOF /app/health_check.py
#!/usr/bin/env python3
import sys
print("Base image health check: OK")
sys.exit(0)
EOF

RUN chmod +x /app/health_check.py

# Default user
USER appuser

# Expose common port (services can override)
EXPOSE 8000

# Default command
CMD ["python", "/app/health_check.py"]

# Labels for image management
LABEL maintainer="Phygrid"
LABEL version="v1.0.9"
LABEL description="Common CUDA base image for AI inference services"
LABEL architecture="multi-arch"
