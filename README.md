# stable-diffusion.cpp Scripts

Linux deployment scripts for [leejet/stable-diffusion.cpp](https://github.com/leejet/stable-diffusion.cpp).

## deploy-sd-cpp.sh

Automated Linux deployment script that installs GPU drivers, builds from source, and optionally downloads a sample model.

### Features
- Auto-detects GPU vendor (NVIDIA/AMD/Intel/CPU-only)
- Installs the correct driver/toolkit (CUDA, ROCm, Vulkan, SYCL, OpenBLAS)
- Clones and builds stable-diffusion.cpp from source
- Downloads SD 1.5 or SDXL sample model
- Creates a system-wide `sd` wrapper

### Usage

```bash
chmod +x deploy-sd-cpp.sh

# Full install (requires sudo for driver steps)
sudo ./deploy-sd-cpp.sh

# Skip driver installation (already have GPU drivers)
SKIP_DRIVER_INSTALL=true ./deploy-sd-cpp.sh

# Force a specific backend
BACKEND=vulkan ./deploy-sd-cpp.sh

# Custom directories
INSTALL_DIR=/opt/stable-diffusion MODELS_DIR=/data/models ./deploy-sd-cpp.sh
```

### Supported Backends

| GPU | Backend | CMake Flag |
|-----|---------|-----------|
| NVIDIA | CUDA | `-DSD_CUDA=ON` |
| AMD | ROCm/HipBLAS | `-DSD_HIPBLAS=ON` |
| Any | Vulkan | `-DSD_VULKAN=ON` |
| Intel GPU | SYCL | `-DSD_SYCL=ON` |
| CPU | OpenBLAS | `-DGGML_OPENBLAS=ON` |

### Tested On
- Ubuntu 20.04 / 22.04 / 24.04
- Debian 11 / 12

