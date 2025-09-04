# Phygrid CUDA - Common Base Image
# Contains shared system dependencies and tools for all inference engines
# Supports both Intel (x64) and ARM architectures

# Use NVIDIA CUDA Ubuntu 24.04 runtime for minimal edge deployment
ARG TARGETARCH
FROM nvidia/cuda:12.8.1-runtime-ubuntu24.04

# Set architecture-aware variables
ARG TARGETARCH
ARG TARGETPLATFORM

WORKDIR /app

# Install Python 3.12 and pip (Ubuntu 24.04 default)
RUN apt-get update && apt-get install -y \
    python3-full \
    python3-dev \
    python3-venv \
    python3-pip \
    && update-alternatives --install /usr/bin/python python /usr/bin/python3 1 \
    && rm -rf /var/lib/apt/lists/*

# Install system dependencies common to all services
RUN apt-get update && apt-get install -y \
    # Build tools
    build-essential \
    cmake \
    git \
    wget \
    curl \
    unzip \
    cuda-compat-12-8 \
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

# Skip pip upgrade - Ubuntu 24.04 comes with recent pip version

# Install common web framework packages (latest compatible versions)
RUN python3 -m pip install --no-cache-dir --break-system-packages \
    fastapi \
    uvicorn[standard] \
    python-multipart \
    pydantic \
    typing-extensions

# Install common utility packages (use latest compatible versions for Python 3.12)
RUN python3 -m pip install --no-cache-dir --break-system-packages \
    numpy \
    pillow \
    requests \
    aiofiles \
    python-dotenv

# Set up common environment variables
ENV PYTHONUNBUFFERED=1
ENV PYTHONDONTWRITEBYTECODE=1
ENV PIP_NO_CACHE_DIR=1
ENV PIP_DISABLE_PIP_VERSION_CHECK=1

# Set CUDA environment variables for both architectures
ENV PATH="/usr/local/cuda/bin:${PATH}"
ENV LD_LIBRARY_PATH="/usr/local/cuda/lib64:/usr/local/cuda-12.8/compat:${LD_LIBRARY_PATH}"
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
LABEL version="v1.0.10"
LABEL description="Common CUDA base image for AI inference services"
LABEL architecture="multi-arch"
