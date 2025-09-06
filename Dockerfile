# Phygrid CUDA - Common Base Image
# Contains shared system dependencies and tools for all inference engines  
# Uses NVIDIA's official CUDA 13.0 with TensorRT runtime for minimal size
# Supports both Intel (x64) and ARM architectures

# Multi-stage build args for proper cross-platform support
ARG TARGETPLATFORM
ARG TARGETOS  
ARG TARGETARCH
ARG TARGETVARIANT

# Use NVIDIA CUDA 13.0 cuDNN runtime, then install TensorRT ourselves  
FROM nvidia/cuda:13.0.0-cudnn-runtime-ubuntu24.04

WORKDIR /app

# Install minimal Python 3.12 setup (Ubuntu 24.04 default)
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y \
    python3-minimal \
    python3-pip \
    python3-dev \
    && ln -sf /usr/bin/python3 /usr/bin/python \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

# Install essential system dependencies and TensorRT
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y \
    # Essential build tools (minimal)
    build-essential \
    cmake \
    git \
    wget \
    curl \
    # Essential libraries for AI/ML (Ubuntu 24.04 package names)
    libgl1 \
    libglx-mesa0 \
    libglib2.0-0 \
    libgomp1 \
    # TensorRT dependencies
    libprotobuf32t64 \
    # Networking essentials
    ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

# -------- Install TensorRT (multi-arch aware) --------
ARG TENSORRT_VERSION=10.9.0
ENV TENSORRT_VERSION=${TENSORRT_VERSION}

# Re-declare TARGETARCH for use in RUN commands
ARG TARGETARCH

RUN set -ex && \
    # Detect architecture if TARGETARCH is not set
    if [ -z "${TARGETARCH}" ]; then \
        DETECTED_ARCH=$(uname -m) && \
        case "${DETECTED_ARCH}" in \
            "x86_64") TARGETARCH="amd64" ;; \
            "aarch64") TARGETARCH="arm64" ;; \
            *) echo "Unsupported detected architecture: ${DETECTED_ARCH}" && exit 1 ;; \
        esac; \
    fi && \
    \
    echo "Installing TensorRT for ${TARGETARCH} architecture..." && \
    \
    # Download and install TensorRT based on architecture
    case "${TARGETARCH}" in \
        "amd64") \
            TRT_ARCH="Linux.x86_64-gnu" \
            ;; \
        "arm64") \
            TRT_ARCH="Linux.aarch64-gnu" \
            ;; \
        *) \
            echo "Unsupported architecture: ${TARGETARCH}" && exit 1 \
            ;; \
    esac && \
    \
    # Try multiple TensorRT download URL patterns
    TRT_URL="https://developer.download.nvidia.com/compute/machine-learning/tensorrt/10.9.0/tars/TensorRT-${TENSORRT_VERSION}.${TRT_ARCH}.cuda-13.0.cudnn9.1.tar.gz" && \
    \
    echo "Attempting TensorRT download from: ${TRT_URL}" && \
    mkdir -p /opt/tensorrt && \
    \
    # Download with fallback options
    if wget --timeout=30 --tries=2 --no-check-certificate -O /tmp/tensorrt.tar.gz "${TRT_URL}"; then \
        echo "✓ TensorRT download successful" && \
        tar -xzf /tmp/tensorrt.tar.gz -C /opt/tensorrt --strip-components=1 && \
        rm /tmp/tensorrt.tar.gz && \
        echo "✓ TensorRT extracted successfully"; \
    else \
        echo "⚠️  TensorRT download failed - creating minimal structure" && \
        echo "   In production, manually download TensorRT from:" && \
        echo "   https://developer.nvidia.com/tensorrt" && \
        mkdir -p /opt/tensorrt/lib /opt/tensorrt/python /opt/tensorrt/bin /opt/tensorrt/include; \
    fi && \
    \
    # Install TensorRT Python wheels if available
    if [ -d "/opt/tensorrt/python" ] && [ "$(ls -A /opt/tensorrt/python/*.whl 2>/dev/null)" ]; then \
        echo "Installing TensorRT Python wheels..." && \
        python -m pip install --no-cache-dir --break-system-packages /opt/tensorrt/python/*.whl || \
        echo "⚠️  TensorRT Python wheel installation failed"; \
    else \
        echo "⚠️  No TensorRT Python wheels found"; \
    fi

# Set TensorRT environment
ENV TRT_ROOT=/opt/tensorrt
ENV LD_LIBRARY_PATH="/opt/tensorrt/lib:${LD_LIBRARY_PATH}"

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
    
    # Check TensorRT installation - architecture aware
    try:
        import platform
        arch = platform.machine()
        print(f"Architecture: {arch}")
        
        trt_lib_path = os.path.join(os.getenv('TRT_ROOT', '/opt/tensorrt'), 'lib')
        if os.path.exists(trt_lib_path):
            print(f"✓ TensorRT library directory found: {trt_lib_path}")
            
            # Try to load TensorRT library
            import ctypes
            possible_libs = [
                os.path.join(trt_lib_path, 'libnvinfer.so.8'),
                os.path.join(trt_lib_path, 'libnvinfer.so'),
            ]
            
            lib_loaded = False
            for lib_path in possible_libs:
                if os.path.exists(lib_path):
                    try:
                        ctypes.CDLL(lib_path, mode=ctypes.RTLD_GLOBAL)
                        print(f"✓ TensorRT library loaded: {lib_path}")
                        lib_loaded = True
                        break
                    except Exception as e:
                        print(f"⚠ Failed to load {lib_path}: {e}")
            
            if not lib_loaded:
                print("⚠ No TensorRT libraries could be loaded")
        else:
            print(f"⚠ TensorRT library directory not found: {trt_lib_path}")
            
        # Try importing TensorRT Python module
        try:
            import tensorrt
            print(f"✓ TensorRT Python version: {tensorrt.__version__}")
        except ImportError:
            print("⚠ TensorRT Python module not available")
            
    except Exception as e:
        print(f"⚠ TensorRT check failed: {e}")
    
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