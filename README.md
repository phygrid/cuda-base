# Phygrid CUDA Base Image

[![Docker Hub](https://img.shields.io/docker/pulls/phygrid/cuda-base.svg)](https://hub.docker.com/r/phygrid/cuda-base)
[![Docker Image Version](https://img.shields.io/docker/v/phygrid/cuda-base?sort=semver)](https://hub.docker.com/r/phygrid/cuda-base/tags)
[![Build Status](https://github.com/phygrid/cuda-base/workflows/Build%20and%20Deploy%20Docker%20Image/badge.svg)](https://github.com/phygrid/cuda-base/actions)
[![License](https://img.shields.io/github/license/phygrid/cuda-base)](LICENSE)

A multi-architecture Docker base image optimized for AI inference services, providing common system dependencies and Python packages for CUDA-accelerated applications. Supports both Intel/AMD x64 systems and ARM64 NVIDIA Jetson devices.

## 🚀 Quick Start

```bash
# Pull the latest image
docker pull phygrid/cuda-base:latest

# Use as base image in your Dockerfile
FROM phygrid/cuda-base:1.0.0
```

## 📋 What's Included

### System Dependencies
- **Build tools**: `build-essential`, `cmake`, `git`, `wget`, `curl`
- **Audio processing**: `libasound2-dev`, `portaudio19-dev`, `libsndfile1`, `ffmpeg`
- **Image processing**: `libgl1`, `libglib2.0-0`, OpenCV dependencies
- **Security**: `patchelf` for executable stack fixes
- **Networking**: `ca-certificates` and utilities

### Python Environment
- **Base**: Python 3.11 with optimized pip, setuptools, wheel
- **Web frameworks**: FastAPI 0.104.1, Uvicorn, Pydantic 2.5.0
- **Core libraries**: NumPy 1.24.4, Pillow 10.1.0, Requests 2.31.0
- **Utilities**: `aiofiles`, `python-dotenv`, `python-multipart`

### Container Features
- **Security**: Non-root `appuser` with proper permissions
- **Structure**: Pre-created `/app/{cache,models,data,logs}` directories
- **Health check**: Built-in health check endpoint
- **Multi-arch**: AMD64 (Intel/AMD) and ARM64 (NVIDIA Jetson) support
- **CUDA**: GPU acceleration for NVIDIA Blackwell and earlier architectures
- **Port**: Exposes port 8000 (customizable)

## 🐳 Docker Hub

**Repository**: [phygrid/cuda-base](https://hub.docker.com/r/phygrid/cuda-base)

### Available Tags
- `latest` - Latest stable release
- `1.0.0`, `1.0.1`, etc. - Specific semantic versions
- Multi-architecture support: `linux/amd64`, `linux/arm64`

## 📦 Usage Examples

### As Base Image
```dockerfile
FROM phygrid/cuda-base:1.0.0

# Copy your application
COPY . /app/

# Install additional dependencies
RUN pip install -r requirements.txt

# Override default command
CMD ["python", "main.py"]
```

### Development Environment
```bash
# Run interactive container
docker run -it --rm \
  -v $(pwd):/app/workspace \
  -p 8000:8000 \
  phygrid/cuda-base:latest \
  bash
```

### Production Deployment
```bash
# Run with GPU support (Intel/AMD systems)
docker run -d \
  --name my-ai-service \
  --gpus all \
  -p 8000:8000 \
  -v /data:/app/data \
  phygrid/cuda-base:latest

# Run on NVIDIA Jetson devices
docker run -d \
  --name my-ai-service \
  --runtime nvidia \
  --gpus all \
  -p 8000:8000 \
  -v /data:/app/data \
  phygrid/cuda-base:latest
```

## 🏗️ Building from Source

```bash
# Clone repository
git clone https://github.com/phygrid/cuda-base.git
cd cuda-base

# Build image
docker build -t phygrid/cuda-base:custom .

# Build for multiple architectures
docker buildx build --platform linux/amd64,linux/arm64 -t phygrid/cuda-base:custom .
```

## 🔄 Versioning

This project uses automated semantic versioning:

- **Automatic**: Patch versions increment on main branch changes
- **Manual**: Edit `VERSION` file for major/minor bumps
- **Tags**: Git tags created automatically (e.g., `v1.0.0`)

See [DOCKER_DEPLOYMENT.md](DOCKER_DEPLOYMENT.md) for detailed deployment workflow.

## 🧪 Health Check

The image includes a built-in health check:

```bash
# Test health endpoint
docker run --rm phygrid/cuda-base:latest python /app/health_check.py
```

## 🤝 Contributing

We welcome contributions! Please:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit changes (`git commit -m 'Add amazing feature'`)
4. Push to branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

### Development Setup
```bash
# Clone and setup
git clone https://github.com/phygrid/cuda-base.git
cd cuda-base

# Test build locally
docker build -t phygrid/cuda-base:test .
docker run --rm phygrid/cuda-base:test python /app/health_check.py
```

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🔧 Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `PYTHONUNBUFFERED` | `1` | Disable Python output buffering |
| `PYTHONDONTWRITEBYTECODE` | `1` | Don't write .pyc files |
| `PIP_NO_CACHE_DIR` | `1` | Disable pip cache |
| `PIP_DISABLE_PIP_VERSION_CHECK` | `1` | Skip pip version checks |

## 🏷️ Labels

The image includes standard OCI labels:

```dockerfile
LABEL org.opencontainers.image.title="Phygrid CUDA Base"
LABEL org.opencontainers.image.description="Common CUDA base image for AI inference services"
LABEL org.opencontainers.image.vendor="Phygrid"
LABEL org.opencontainers.image.version="1.0.0"
```

## 🆘 Support

- **Issues**: [GitHub Issues](https://github.com/phygrid/cuda-base/issues)
- **Discussions**: [GitHub Discussions](https://github.com/phygrid/cuda-base/discussions)
- **Docker Hub**: [phygrid/cuda-base](https://hub.docker.com/r/phygrid/cuda-base)

## 📈 Metrics

- **Image size**: ~800MB compressed (AMD64), ~1.2GB (ARM64 with CUDA)
- **Build time**: ~5-10 minutes (with cache)
- **Architectures**: AMD64 (Intel/AMD), ARM64 (NVIDIA Jetson)
- **Python version**: 3.12 (Ubuntu 24.04 default)
- **Base OS**: Ubuntu 24.04 + CUDA 12.9 (unified for both architectures)
- **CUDA version**: 12.9.0 with compatibility layer for edge deployment