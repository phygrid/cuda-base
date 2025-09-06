# Phygrid CUDA - Common Base Image
# Contains shared system dependencies and tools for all inference engines  
# Uses NVIDIA's official CUDA 13.0 with TensorRT runtime for minimal size
# Supports both Intel (x64) and ARM architectures

# Multi-stage build args for proper cross-platform support
ARG TARGETPLATFORM
ARG TARGETOS  
ARG TARGETARCH
ARG TARGETVARIANT

# Use NVIDIA CUDA 13.0 TensorRT runtime for minimal edge deployment
FROM --platform=$TARGETPLATFORM nvidia/cuda:13.0.0-tensorrt-runtime-ubuntu24.04

WORKDIR /app

# Install minimal Python 3.12 setup (Ubuntu 24.04 default)
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y \
    python3-minimal \
    python3-pip \
    python3-dev \
    && ln -sf /usr/bin/python3 /usr/bin/python \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

# Install only essential system dependencies for AI services
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y \
    # Essential build tools (minimal)
    build-essential \
    cmake \
    git \
    wget \
    curl \
    # Essential libraries for AI/ML
    libgl1-mesa-glx \
    libglib2.0-0 \
    libgomp1 \
    # Networking essentials
    ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

# Install minimal common Python packages (no caching for smaller image)
RUN python -m pip install --no-cache-dir --break-system-packages \
    fastapi \
    uvicorn[standard] \
    pydantic \
    numpy \
    pillow \
    requests

# Set up optimized environment variables
ENV PYTHONUNBUFFERED=1
ENV PYTHONDONTWRITEBYTECODE=1  
ENV PIP_NO_CACHE_DIR=1
ENV PIP_DISABLE_PIP_VERSION_CHECK=1

# CUDA environment (inherits from base image)
ENV CUDA_HOME="/usr/local/cuda"
ENV PATH="/usr/local/cuda/bin:${PATH}"

# Create essential directories only
RUN mkdir -p /app/cache

# Create non-root user for security
RUN groupadd -r appuser && useradd -r -g appuser -m appuser
RUN chown -R appuser:appuser /app

# Minimal health check
COPY --chown=appuser:appuser <<'PY' /app/health_check.py
#!/usr/bin/env python3
import sys
import os

def check_health():
    print("=== Phygrid CUDA Base Health Check ===")
    
    # Check Python
    print(f"✓ Python version: {sys.version.split()[0]}")
    
    # Check CUDA
    cuda_version = os.environ.get('CUDA_VERSION', 'unknown')
    print(f"✓ CUDA version: {cuda_version}")
    
    # Check TensorRT (from base image)
    try:
        import ctypes
        # Try to load TensorRT library
        ctypes.CDLL('/usr/lib/x86_64-linux-gnu/libnvinfer.so.8', mode=ctypes.RTLD_GLOBAL)
        print("✓ TensorRT runtime available")
    except:
        print("⚠ TensorRT runtime not found")
    
    # Check essential Python packages
    try:
        import numpy, requests, fastapi, uvicorn, pydantic, PIL
        print("✓ Essential Python packages installed")
    except ImportError as e:
        print(f"❌ Missing package: {e}")
        return 1
    
    print("✅ Base image health check passed")
    return 0

if __name__ == "__main__":
    sys.exit(check_health())
PY

RUN chmod +x /app/health_check.py

# Switch to non-root user
USER appuser

# Expose common port
EXPOSE 8000

# Default command
CMD ["python", "/app/health_check.py"]

# Optimized labels
LABEL maintainer="Phygrid"
LABEL base="nvidia/cuda:13.0.0-tensorrt-runtime-ubuntu24.04"
LABEL description="Minimal CUDA base image with TensorRT runtime for AI inference"
LABEL architecture="multi-arch"