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
ARG DOWNLOADS_DIR=./downloads-cache

WORKDIR /build

# Copy pre-downloaded TensorRT files
COPY ${DOWNLOADS_DIR}/tensorrt-*.tar.gz /tmp/

# Extract TensorRT (architecture-aware)
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
    # Set architecture-specific file
    case "${TARGETARCH}" in \
        "amd64") \
            TRT_FILE="/tmp/tensorrt-amd64.tar.gz" \
            ;; \
        "arm64") \
            TRT_FILE="/tmp/tensorrt-arm64.tar.gz" \
            ;; \
        *) \
            echo "Unsupported architecture: ${TARGETARCH}" && exit 1 \
            ;; \
    esac && \
    \
    echo "Extracting TensorRT from: ${TRT_FILE}" && \
    mkdir -p /build/tensorrt && \
    \
    # Extract pre-downloaded file
    if [ -f "${TRT_FILE}" ]; then \
        tar -xzf "${TRT_FILE}" -C /build/tensorrt --strip-components=1 && \
        rm -f /tmp/tensorrt-*.tar.gz && \
        echo "✓ TensorRT extracted successfully" && \
        ls -la /build/tensorrt/; \
    else \
        echo "⚠️  TensorRT file not found: ${TRT_FILE}" && \
        echo "   Creating minimal structure as fallback" && \
        mkdir -p /build/tensorrt/lib /build/tensorrt/python /build/tensorrt/bin /build/tensorrt/include; \
    fi

# ====== STAGE: FFmpeg Builder with CUDA Support ======
FROM nvidia/cuda:12.9.0-devel-ubuntu24.04 AS ffmpeg-builder

# Accept build arg for downloads directory
ARG DOWNLOADS_DIR=./downloads-cache

WORKDIR /opt

# Install confirmed available build dependencies
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    # Build tools (confirmed available)
    build-essential \
    git \
    pkg-config \
    nasm \
    yasm \
    # Confirmed codec development libraries
    libx264-dev \
    libx265-dev \
    libvpx-dev \
    libopus-dev \
    libvorbis-dev \
    libssl-dev \
    # Additional codec libraries for better H264 support
    libavformat-dev \
    libavcodec-dev \
    libavdevice-dev \
    libavutil-dev \
    libswscale-dev \
    libswresample-dev \
    libavfilter-dev \
    && rm -rf /var/lib/apt/lists/*

# Download NVIDIA Video Codec SDK headers (required for NVENC/NVDEC)
RUN git clone https://git.videolan.org/git/ffmpeg/nv-codec-headers.git \
    && cd nv-codec-headers \
    && make install \
    && cd .. && rm -rf nv-codec-headers

# Copy pre-downloaded FFmpeg source
COPY ${DOWNLOADS_DIR}/ffmpeg.tar.gz /tmp/

# Extract FFmpeg source
RUN echo "=== Extracting FFmpeg source ===" && \
    if [ -f "/tmp/ffmpeg.tar.gz" ]; then \
        tar -xzf /tmp/ffmpeg.tar.gz && \
        mv FFmpeg-master ffmpeg && \
        rm /tmp/ffmpeg.tar.gz && \
        echo "✓ FFmpeg source extracted successfully"; \
    else \
        echo "FFmpeg tarball not found, trying git clone fallback..." && \
        git clone --depth 1 https://git.ffmpeg.org/ffmpeg.git || \
        (echo "Failed to obtain FFmpeg source" && exit 1); \
    fi

# Configure FFmpeg (separate step to isolate configure issues) - use /usr/local prefix
RUN cd ffmpeg && \
    echo "=== FFmpeg Configure Phase ===" && \
    ./configure \
        --prefix=/usr/local/ffmpeg \
        --bindir=/usr/local/ffmpeg/bin \
        --libdir=/usr/local/ffmpeg/lib \
        --incdir=/usr/local/ffmpeg/include \
        --enable-gpl \
        --enable-nonfree \
        --enable-shared \
        --disable-static \
        --extra-cflags="-I/usr/local/cuda/include" \
        --extra-ldflags="-L/usr/local/cuda/lib64" \
        --enable-cuda-nvcc \
        --enable-cuvid \
        --enable-nvenc \
        --enable-libx264 \
        --enable-libx265 \
        --enable-libvpx \
        --enable-libopus \
        --enable-libvorbis \
        --enable-openssl \
        --enable-decoder=h264 \
        --enable-decoder=h264_cuvid \
        --enable-encoder=h264_nvenc \
        --enable-hwaccel=h264_nvdec \
        --enable-hwaccel=h264_cuvid || \
    (echo "=== CONFIGURE FAILED - showing config.log ==="; tail -20 ffbuild/config.log; exit 1) && \
    echo "=== Configure completed successfully ==="

# Compile FFmpeg (separate step to isolate compile issues) 
RUN cd ffmpeg && \
    echo "=== FFmpeg Compilation Phase ===" && \
    make -j2 || \
    (echo "=== COMPILATION FAILED ===" && exit 1) && \
    echo "=== Compilation completed successfully ==="

# Install and verify FFmpeg (separate step to isolate install issues)
RUN cd ffmpeg && \
    echo "=== FFmpeg Installation Phase ===" && \
    make install && \
    echo "=== Debugging FFmpeg installation location ===" && \
    find /usr/local -name "ffmpeg" -type f 2>/dev/null | head -10 && \
    ls -la /usr/local/ffmpeg/ && \
    echo "=== Verifying FFmpeg installation ===" && \
    test -f /usr/local/ffmpeg/bin/ffmpeg || (echo "ERROR: ffmpeg binary missing at /usr/local/ffmpeg/bin/ffmpeg" && exit 1) && \
    test -d /usr/local/ffmpeg/lib || (echo "ERROR: ffmpeg lib directory missing at /usr/local/ffmpeg/lib" && exit 1) && \
    ls -la /usr/local/ffmpeg/bin/ && \
    /usr/local/ffmpeg/bin/ffmpeg -version 2>&1 | head -3 && \
    echo "=== FFmpeg build SUCCESSFUL ===" && \
    cd .. && rm -rf ffmpeg

# ====== STAGE: PyAV Builder ======
FROM ffmpeg-builder AS pyav-builder

# Install Python build dependencies
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y \
    python3-dev \
    python3-pip \
    python3-setuptools \
    python3-wheel \
    python3-venv \
    git \
    && rm -rf /var/lib/apt/lists/*

# Set environment for PyAV to use our custom FFmpeg
ENV PKG_CONFIG_PATH="/usr/local/ffmpeg/lib/pkgconfig" \
    LD_LIBRARY_PATH="/usr/local/ffmpeg/lib:$LD_LIBRARY_PATH" \
    PYTHONPATH="/usr/local/lib/python3.12/site-packages"

# Build PyAV with custom CUDA FFmpeg (step by step with error checking)
RUN set -ex && \
    echo "=== Installing PyAV build dependencies ===" && \
    pip3 install --no-cache-dir --break-system-packages cython numpy setuptools wheel && \
    echo "=== Building PyAV wheel with CUDA FFmpeg ===" && \
    pip3 wheel --wheel-dir=/wheels --no-cache-dir av && \
    echo "=== PyAV wheel build complete ===" && \
    ls -la /wheels/

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
    # Confirmed FFmpeg runtime dependencies
    libx264-164 \
    libx265-199 \
    libvpx9 \
    libopus0 \
    libvorbis0a \
    libvorbisenc2 \
    libssl3t64 \
    # Additional codec runtime libraries
    libavcodec60 \
    libavformat60 \
    libavutil58 \
    libswscale7 \
    libswresample4 \
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

# Copy CUDA FFmpeg from build stage (from /usr/local/ffmpeg)
COPY --from=ffmpeg-builder /usr/local/ffmpeg /opt/ffmpeg

# Copy PyAV wheels from build stage (must exist)
COPY --from=pyav-builder /wheels/*.whl /opt/pyav/

# Install TensorRT Python wheels (only runtime files copied)
RUN if [ -d "/opt/tensorrt/python" ] && [ "$(ls -A /opt/tensorrt/python/*.whl 2>/dev/null)" ]; then \
        echo "Installing TensorRT Python wheels..." && \
        python -m pip install --no-cache-dir --break-system-packages /opt/tensorrt/python/*.whl || \
        echo "⚠️  TensorRT Python wheel installation failed"; \
    else \
        echo "⚠️  No TensorRT Python wheels found"; \
    fi

# Install custom PyAV with CUDA FFmpeg support (must succeed)
RUN echo "Installing custom PyAV with CUDA FFmpeg support..." && \
    python -m pip install --no-cache-dir --break-system-packages /opt/pyav/*.whl && \
    echo "✅ PyAV installation successful"

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
LABEL base="nvidia/cuda:12.9.0-runtime-ubuntu24.04"
LABEL tensorrt.version="${TENSORRT_VERSION}"
LABEL description="Minimal CUDA base with TensorRT runtime for AI inference (multi-stage optimized)"
LABEL architecture="multi-arch"
LABEL build.stage="optimized"