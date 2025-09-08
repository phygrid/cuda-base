# Phygrid CUDA - Common Base Image
# Multi-stage build to minimize final image size
# Uses NVIDIA CUDA 12.9 cuDNN runtime + TensorRT runtime libraries only
# Supports both Intel (x64) and ARM architectures

# Multi-stage build args for proper cross-platform support
ARG TARGETPLATFORM
ARG TARGETOS  
ARG TARGETARCH
ARG TARGETVARIANT

# ====== BUILD STAGE: TensorRT Download & Extract ======
FROM nvidia/cuda:12.9.0-runtime-ubuntu24.04 AS tensorrt-builder

# Re-declare args for this stage
ARG TARGETARCH
ARG TENSORRT_VERSION=10.9.0.34

WORKDIR /build

# Install minimal tools needed for download and extraction only
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y \
    wget \
    curl \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Download and extract TensorRT (architecture-aware)
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
    echo "Building TensorRT for ${TARGETARCH} architecture..." && \
    \
    # Set architecture-specific package name
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
    # TensorRT 10.9.0 download URL for CUDA 12.9 support
    TRT_URL="https://developer.download.nvidia.com/compute/machine-learning/tensorrt/10.9.0/tars/TensorRT-10.9.0.34.${TRT_ARCH}.cuda-12.8.tar.gz" && \
    \
    echo "Attempting TensorRT download from: ${TRT_URL}" && \
    mkdir -p /build/tensorrt && \
    \
    # Download with timeout and retry
    if wget --timeout=60 --tries=3 --no-check-certificate -O /tmp/tensorrt.tar.gz "${TRT_URL}"; then \
        echo "✓ TensorRT download successful" && \
        tar -xzf /tmp/tensorrt.tar.gz -C /build/tensorrt --strip-components=1 && \
        rm /tmp/tensorrt.tar.gz && \
        echo "✓ TensorRT extracted successfully" && \
        ls -la /build/tensorrt/; \
    else \
        echo "⚠️  TensorRT download failed - creating minimal structure" && \
        echo "   In production, manually download TensorRT from:" && \
        echo "   https://developer.nvidia.com/tensorrt" && \
        mkdir -p /build/tensorrt/lib /build/tensorrt/python /build/tensorrt/bin /build/tensorrt/include; \
    fi

# ====== STAGE: FFmpeg Builder with CUDA Support ======
FROM nvidia/cuda:12.9.0-devel-ubuntu24.04 AS ffmpeg-builder

WORKDIR /opt

# Install build dependencies for FFmpeg
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    build-essential \
    cmake \
    git \
    pkg-config \
    yasm \
    nasm \
    # Codec development libraries
    libx264-dev \
    libx265-dev \
    libvpx-dev \
    libfdk-aac-dev \
    libmp3lame-dev \
    libopus-dev \
    libvorbis-dev \
    libtheora-dev \
    libass-dev \
    libfreetype6-dev \
    libgnutls28-dev \
    librtmp-dev \
    libsrtp2-dev \
    && rm -rf /var/lib/apt/lists/*

# Download and install NVIDIA codec headers (required for NVENC/NVDEC)
RUN git clone https://git.videolan.org/git/ffmpeg/nv-codec-headers.git \
    && cd nv-codec-headers \
    && make install \
    && cd .. && rm -rf nv-codec-headers

# Download and compile FFmpeg with CUDA acceleration
RUN git clone --depth 1 https://git.ffmpeg.org/ffmpeg.git \
    && cd ffmpeg \
    && ./configure \
        --prefix=/opt/ffmpeg \
        --pkg-config-flags="--static" \
        --extra-cflags="-I/usr/local/cuda/include" \
        --extra-ldflags="-L/usr/local/cuda/lib64" \
        --extra-libs="-lpthread -lm -lz" \
        --bindir=/opt/ffmpeg/bin \
        --libdir=/opt/ffmpeg/lib \
        --incdir=/opt/ffmpeg/include \
        --enable-gpl \
        --enable-nonfree \
        --enable-cuda-nvcc \
        --enable-cuvid \
        --enable-nvenc \
        --enable-libnpp \
        --enable-libx264 \
        --enable-libx265 \
        --enable-libvpx \
        --enable-libfdk-aac \
        --enable-libmp3lame \
        --enable-libopus \
        --enable-libvorbis \
        --enable-libtheora \
        --enable-libass \
        --enable-libfreetype \
        --enable-gnutls \
        --enable-librtmp \
        --disable-debug \
        --disable-doc \
        --disable-static \
        --enable-shared \
    && make -j$(nproc) \
    && make install \
    && cd .. && rm -rf ffmpeg

# ====== STAGE: PyAV Builder ======
FROM ffmpeg-builder AS pyav-builder

# Install Python build dependencies
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    python3-dev \
    python3-pip \
    python3-setuptools \
    python3-wheel \
    && rm -rf /var/lib/apt/lists/*

# Set environment for PyAV to find our custom FFmpeg
ENV PKG_CONFIG_PATH="/opt/ffmpeg/lib/pkgconfig" \
    LD_LIBRARY_PATH="/opt/ffmpeg/lib:$LD_LIBRARY_PATH"

# Build PyAV with custom FFmpeg (creates wheels for later installation)
RUN pip3 install --no-cache-dir cython numpy setuptools wheel \
    && pip3 wheel --no-cache-dir --no-binary av av>=12.0.0

# ====== FINAL STAGE: Runtime Image ======  
FROM nvidia/cuda:12.9.0-runtime-ubuntu24.04

WORKDIR /app

# Re-declare args for final stage
ARG TARGETARCH
ARG TENSORRT_VERSION=10.9.0.34
ENV TENSORRT_VERSION=${TENSORRT_VERSION}

# Install essential runtime dependencies + CUDA math libraries for TensorRT
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --allow-change-held-packages \
    # Minimal Python setup
    python3-minimal \
    python3-pip \
    python3-dev \
    # Essential runtime libraries only (no cmake, build-essential, etc.)
    libgl1 \
    libglx-mesa0 \
    libglib2.0-0 \
    libgomp1 \
    # FFmpeg runtime dependencies
    libx264-164 \
    libx265-199 \
    libvpx9 \
    libfdk-aac2 \
    libmp3lame0 \
    libopus0 \
    libvorbis0a \
    libtheora0 \
    libass9 \
    libfreetype6 \
    libgnutls30t64 \
    librtmp1 \
    libsrtp2-1 \
    # TensorRT runtime dependencies
    libprotobuf32t64 \
    # CUDA math libraries required for TensorRT (CUDA 12.9)
    libcublas-12-9 \
    libcurand-12-9 \
    libcusparse-12-9 \
    libcusolver-12-9 \
    libcufft-12-9 \
    # cuDNN for neural network operations
    libcudnn9-cuda-12 \
    # CUDA compatibility package for hosts with earlier CUDA versions  
    cuda-compat-12-9 \
    && ln -sf /usr/bin/python3 /usr/bin/python \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

# Copy TensorRT runtime files from build stage
COPY --from=tensorrt-builder /build/tensorrt/lib /opt/tensorrt/lib
COPY --from=tensorrt-builder /build/tensorrt/python /opt/tensorrt/python
COPY --from=tensorrt-builder /build/tensorrt/bin /opt/tensorrt/bin
COPY --from=tensorrt-builder /build/tensorrt/include /opt/tensorrt/include

# Copy CUDA-accelerated FFmpeg from build stage
COPY --from=ffmpeg-builder /opt/ffmpeg/bin /opt/ffmpeg/bin
COPY --from=ffmpeg-builder /opt/ffmpeg/lib /opt/ffmpeg/lib
COPY --from=ffmpeg-builder /opt/ffmpeg/include /opt/ffmpeg/include

# Copy PyAV wheels from build stage
COPY --from=pyav-builder /*.whl /opt/pyav/

# Install TensorRT Python wheels (only runtime files copied)
RUN if [ -d "/opt/tensorrt/python" ] && [ "$(ls -A /opt/tensorrt/python/*.whl 2>/dev/null)" ]; then \
        echo "Installing TensorRT Python wheels..." && \
        python -m pip install --no-cache-dir --break-system-packages /opt/tensorrt/python/*.whl || \
        echo "⚠️  TensorRT Python wheel installation failed"; \
    fi

# Install PyAV with CUDA-accelerated FFmpeg
RUN if [ -d "/opt/pyav" ] && [ "$(ls -A /opt/pyav/*.whl 2>/dev/null)" ]; then \
        echo "Installing PyAV with CUDA FFmpeg support..." && \
        python -m pip install --no-cache-dir --break-system-packages /opt/pyav/*.whl || \
        echo "⚠️  PyAV wheel installation failed"; \
    fi

# Add FFmpeg to PATH and library paths
ENV PATH="/opt/ffmpeg/bin:$PATH" \
    PKG_CONFIG_PATH="/opt/ffmpeg/lib/pkgconfig:/usr/lib/pkgconfig:/usr/share/pkgconfig" \
    LD_LIBRARY_PATH="/opt/ffmpeg/lib:$LD_LIBRARY_PATH"

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

# CUDA environment (inherits from base image) with compatibility support
ENV CUDA_HOME="/usr/local/cuda"
ENV PATH="/usr/local/cuda/bin:${PATH}"

# CUDA 12.9 environment with compatibility for earlier host versions
ENV CUDA_COMPAT_PATH="/usr/local/cuda-12.9/compat"
ENV LD_LIBRARY_PATH="/usr/local/cuda-12.9/compat:/usr/local/cuda-12.9/targets/x86_64-linux/lib:${LD_LIBRARY_PATH}"
ENV NVIDIA_DISABLE_REQUIRE=true
ENV NVIDIA_REQUIRE_CUDA="cuda>=11.0"

# Set TensorRT environment
ENV TRT_ROOT=/opt/tensorrt
ENV LD_LIBRARY_PATH="/opt/tensorrt/lib:${LD_LIBRARY_PATH}"

# Create essential directories only
RUN mkdir -p /app/cache

# Create non-root user for security
RUN groupadd -r appuser && useradd -r -g appuser -m appuser
RUN chown -R appuser:appuser /app /opt/tensorrt

# Optimized health check (architecture-aware)
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
LABEL base="nvidia/cuda:13.0.0-cudnn-runtime-ubuntu24.04"
LABEL tensorrt.version="${TENSORRT_VERSION}"
LABEL description="Minimal CUDA base with TensorRT runtime for AI inference (multi-stage optimized)"
LABEL architecture="multi-arch"
LABEL build.stage="optimized"