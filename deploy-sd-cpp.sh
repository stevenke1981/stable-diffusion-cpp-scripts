#!/usr/bin/env bash
# =============================================================================
# stable-diffusion.cpp Linux Deployment Script
# https://github.com/leejet/stable-diffusion.cpp
#
# Supports: NVIDIA (CUDA), AMD (ROCm/HipBLAS), Intel (SYCL), Vulkan, CPU-only
# Tested on: Ubuntu 20.04/22.04/24.04, Debian 11/12
# =============================================================================

set -euo pipefail

# ── Color output ──────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

log()    { echo -e "${GREEN}[+]${NC} $*"; }
warn()   { echo -e "${YELLOW}[!]${NC} $*"; }
error()  { echo -e "${RED}[✗]${NC} $*" >&2; }
info()   { echo -e "${CYAN}[i]${NC} $*"; }
header() { echo -e "\n${BOLD}${BLUE}══ $* ══${NC}\n"; }

# ── Configuration (override via environment variables) ────────────────────────
INSTALL_DIR="${INSTALL_DIR:-$HOME/stable-diffusion.cpp}"
BUILD_DIR="${BUILD_DIR:-$INSTALL_DIR/build}"
MODELS_DIR="${MODELS_DIR:-$HOME/sd-models}"
SKIP_DRIVER_INSTALL="${SKIP_DRIVER_INSTALL:-false}"
DOWNLOAD_SAMPLE_MODEL="${DOWNLOAD_SAMPLE_MODEL:-true}"
BACKEND=""        # auto-detected unless set: cuda | hipblas | vulkan | sycl | cpu

# ── Helper utilities ──────────────────────────────────────────────────────────

# Use sudo automatically when not running as root
SUDO=""
[[ $EUID -ne 0 ]] && SUDO="sudo"

require_root() {
    # No-op: kept for compatibility; SUDO variable handles privilege escalation
    :
}

check_cmd() { command -v "$1" &>/dev/null; }

apt_install() {
    DEBIAN_FRONTEND=noninteractive $SUDO apt-get install -y --no-install-recommends "$@"
}

# [FIX LOW] Use printf instead of echo -e inside read -p for portability
confirm() {
    local msg="$1"
    local ans
    printf "${YELLOW}[?]${NC} %s [Y/n] " "$msg"
    read -r ans
    [[ "${ans:-Y}" =~ ^[Yy]$ ]]
}

# Safe model download: downloads to temp file, moves atomically on success
# Prevents corrupt partial files from passing the existence check on next run
download_file() {
    local url="$1"
    local dest="$2"
    local tmp_dest
    tmp_dest=$(mktemp "${dest}.XXXXXX")
    if curl -L --progress-bar -o "$tmp_dest" "$url"; then
        mv "$tmp_dest" "$dest"
    else
        rm -f "$tmp_dest"
        error "Download failed: $url"
        return 1
    fi
}

# ═════════════════════════════════════════════════════════════════════════════
# STEP 1 — Install system dependencies (moved before detect_gpu so lspci exists)
# ═════════════════════════════════════════════════════════════════════════════
install_system_deps() {
    header "System Dependencies"

    if [[ "$SKIP_DRIVER_INSTALL" == "true" ]]; then
        warn "SKIP_DRIVER_INSTALL=true — skipping system package installation"
        return
    fi

    require_root

    log "Updating package lists..."
    $SUDO apt-get update -qq

    log "Installing build essentials..."
    apt_install \
        build-essential \
        cmake \
        ninja-build \
        git \
        curl \
        wget \
        ca-certificates \
        pkg-config \
        libopenblas-dev \
        python3 \
        python3-pip \
        unzip \
        pciutils    # provides lspci

    log "System dependencies installed."
}

# ═════════════════════════════════════════════════════════════════════════════
# STEP 2 — Detect GPU (after system deps so lspci is available)
# ═════════════════════════════════════════════════════════════════════════════
detect_gpu() {
    header "GPU Detection"

    local nvidia_found=false
    local amd_found=false
    local intel_found=false

    if check_cmd lspci; then
        if lspci | grep -qi "nvidia"; then nvidia_found=true; fi
        if lspci | grep -qi "amd\|radeon\|advanced micro"; then amd_found=true; fi
        if lspci | grep -qi "intel.*graphics\|intel.*uhd\|intel.*iris"; then intel_found=true; fi
    fi

    [[ -d /proc/driver/nvidia ]] && nvidia_found=true
    check_cmd nvidia-smi && nvidia_found=true
    check_cmd rocminfo   && amd_found=true

    if [[ "$nvidia_found" == true ]]; then
        GPU_VENDOR="nvidia"
        info "Detected: NVIDIA GPU"
        if check_cmd nvidia-smi; then
            nvidia-smi --query-gpu=name,driver_version,memory.total \
                       --format=csv,noheader 2>/dev/null | while IFS=',' read -r name drv mem; do
                info "  GPU: ${name// /} | Driver: ${drv// /} | VRAM:${mem}"
            done
        fi
    elif [[ "$amd_found" == true ]]; then
        GPU_VENDOR="amd"
        info "Detected: AMD GPU"
    elif [[ "$intel_found" == true ]]; then
        GPU_VENDOR="intel"
        info "Detected: Intel GPU"
    else
        GPU_VENDOR="cpu"
        warn "No discrete GPU detected — will build CPU-only"
    fi

    # Allow manual override
    if [[ -n "$BACKEND" ]]; then
        info "Backend override: $BACKEND"
    else
        case "$GPU_VENDOR" in
            nvidia) BACKEND="cuda"    ;;
            amd)    BACKEND="hipblas" ;;
            intel)  BACKEND="sycl"   ;;
            *)      BACKEND="cpu"    ;;
        esac
        info "Selected backend: $BACKEND"
    fi
}

# ═════════════════════════════════════════════════════════════════════════════
# STEP 3 — Install GPU drivers / toolkits
# ═════════════════════════════════════════════════════════════════════════════
install_nvidia_driver() {
    header "NVIDIA Driver & CUDA Toolkit"

    if check_cmd nvidia-smi; then
        local current_driver
        current_driver=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader | head -1 | tr -d ' ')
        log "NVIDIA driver already installed (version: $current_driver)"
        if confirm "Re-install / upgrade NVIDIA driver?"; then
            _do_nvidia_install
        fi
    else
        _do_nvidia_install
    fi
}

_do_nvidia_install() {
    require_root

    . /etc/os-release
    local distro_id="${ID}"

    log "Removing old driver packages if any..."
    $SUDO apt-get remove --purge -y 'nvidia-*' 'cuda-*' 2>/dev/null || true
    $SUDO apt-get autoremove -y 2>/dev/null || true

    log "Adding NVIDIA repository..."
    case "$distro_id" in
        ubuntu)
            apt_install software-properties-common
            $SUDO add-apt-repository -y ppa:graphics-drivers/ppa
            $SUDO apt-get update -qq
            apt_install ubuntu-drivers-common
            ubuntu-drivers autoinstall || true
            ;;
        debian)
            apt_install software-properties-common apt-transport-https gnupg2

            # [FIX LOW] Use a drop-in file instead of modifying /etc/apt/sources.list
            # Avoids fragile sed on files that may already have contrib, and handles
            # both Debian 11 (no non-free-firmware) and Debian 12+
            local codename="${VERSION_CODENAME:-$(. /etc/os-release && echo "$VERSION_CODENAME")}"
            local nonfree_components="main contrib non-free"
            # non-free-firmware only exists in Debian 12+ (bookworm)
            if dpkg --compare-versions "${VERSION_ID:-0}" ge 12 2>/dev/null; then
                nonfree_components="$nonfree_components non-free-firmware"
            fi
            echo "deb http://deb.debian.org/debian ${codename} ${nonfree_components}" \
                | $SUDO tee /etc/apt/sources.list.d/non-free.list > /dev/null
            $SUDO apt-get update -qq
            apt_install nvidia-driver firmware-misc-nonfree
            ;;
        *)
            warn "Unsupported distro '$distro_id'. Attempting generic install..."
            apt_install nvidia-driver-525
            ;;
    esac

    # [FIX MEDIUM] Warn about APT cuda-toolkit being stale; offer NVIDIA repo instead
    warn "The 'nvidia-cuda-toolkit' package from APT may be 1-3 versions behind CUDA 12.x."
    warn "For best results with modern GPUs, install from https://developer.nvidia.com/cuda-downloads"
    if confirm "Install nvidia-cuda-toolkit from APT anyway (older, but simpler)?"; then
        apt_install nvidia-cuda-toolkit
    else
        # Add NVIDIA CUDA network repository for a current toolkit
        local ubuntu_ver="${VERSION_ID//./}"
        local cuda_keyring_url="https://developer.download.nvidia.com/compute/cuda/repos/ubuntu${ubuntu_ver}/x86_64/cuda-keyring_1.1-1_all.deb"
        local tmp_deb
        tmp_deb=$(mktemp /tmp/cuda-keyring.XXXXXX.deb)
        if wget -q -O "$tmp_deb" "$cuda_keyring_url"; then
            apt_install "$tmp_deb"
            rm -f "$tmp_deb"
            $SUDO apt-get update -qq
            apt_install cuda-toolkit-12-6
        else
            rm -f "$tmp_deb"
            warn "Could not reach NVIDIA CUDA repo. Falling back to APT cuda-toolkit."
            apt_install nvidia-cuda-toolkit
        fi
    fi

    log "NVIDIA driver installation complete."
    warn "A system reboot is REQUIRED before CUDA will work."
    warn "After reboot, run this script again to continue the build."
    if confirm "Reboot now?"; then
        $SUDO reboot
    fi
}

install_amd_driver() {
    header "AMD ROCm Toolkit"

    if check_cmd rocminfo; then
        log "ROCm already installed."
        rocminfo 2>/dev/null | grep -i "gfx\|name" | head -10 || true
        if ! confirm "Re-install ROCm?"; then return; fi
    fi

    require_root

    # [FIX HIGH] Detect Ubuntu codename dynamically instead of hardcoding 'jammy'
    . /etc/os-release
    local codename="${UBUNTU_CODENAME:-${VERSION_CODENAME:-jammy}}"
    local amdgpu_ver="6.3.60300-1"
    local deb_url="https://repo.radeon.com/amdgpu-install/6.3/ubuntu/${codename}/amdgpu-install_${amdgpu_ver}_all.deb"
    local tmp_deb
    tmp_deb=$(mktemp /tmp/amdgpu-install.XXXXXX.deb)

    log "Installing ROCm via amdgpu-install (distro: ${codename})..."
    if ! wget -q -O "$tmp_deb" "$deb_url"; then
        rm -f "$tmp_deb"
        error "Could not download amdgpu-install for '${codename}'."
        error "Check https://repo.radeon.com/amdgpu-install/ for your distro version."
        exit 1
    fi

    apt_install "$tmp_deb"
    rm -f "$tmp_deb"   # [FIX LOW] clean up temp deb

    $SUDO apt-get update -qq
    $SUDO amdgpu-install --usecase=rocm --no-dkms -y

    local REAL_USER="${SUDO_USER:-$USER}"
    $SUDO usermod -a -G render,video "$REAL_USER" 2>/dev/null || true

    log "ROCm installation complete."
    warn "Log out and back in (or reboot) for group changes to take effect."
}

install_vulkan_sdk() {
    header "Vulkan SDK"

    if check_cmd vulkaninfo; then
        log "Vulkan already available."
        return
    fi

    require_root
    log "Installing Vulkan SDK..."
    apt_install \
        libvulkan-dev \
        vulkan-tools \
        spirv-tools \
        glslang-tools
    log "Vulkan SDK installed."
}

install_intel_sycl() {
    header "Intel oneAPI Base Toolkit (SYCL)"

    if [[ -f /opt/intel/oneapi/setvars.sh ]]; then
        log "Intel oneAPI already installed."
        return
    fi

    require_root
    log "Adding Intel oneAPI repository..."

    # [FIX HIGH] Download key to temp file and verify fingerprint before trusting
    local tmp_key
    tmp_key=$(mktemp /tmp/intel-gpg.XXXXXX)
    wget -qO "$tmp_key" https://apt.repos.intel.com/intel-gpg-keys/GPG-PUB-KEY-INTEL-SW-PRODUCTS.PUB

    # Verify against Intel's known fingerprint before adding to trusted store
    local fingerprint
    fingerprint=$(gpg --no-default-keyring \
        --keyring "gnupg-ring:${tmp_key}.gpg" \
        --import "$tmp_key" 2>/dev/null; \
        gpg --no-default-keyring \
        --keyring "gnupg-ring:${tmp_key}.gpg" \
        --fingerprint 2>/dev/null | tr -d ' :' | grep -i "B1EE8B481F4FA0607B360C759F210B2A7FD46E28" || true)

    if [[ -z "$fingerprint" ]]; then
        rm -f "$tmp_key" "${tmp_key}.gpg"
        error "Intel GPG key fingerprint verification FAILED."
        error "Expected fingerprint: B1EE 8B48 1F4F A060 7B36  0C75 9F21 0B2A 7FD4 6E28"
        error "Do NOT proceed. Check https://www.intel.com/content/www/us/en/developer/tools/oneapi/base-toolkit.html"
        exit 1
    fi

    gpg --dearmor < "$tmp_key" | $SUDO tee /usr/share/keyrings/oneapi-archive-keyring.gpg > /dev/null
    rm -f "$tmp_key" "${tmp_key}.gpg"
    log "Intel GPG key fingerprint verified."

    echo "deb [signed-by=/usr/share/keyrings/oneapi-archive-keyring.gpg] \
https://apt.repos.intel.com/oneapi all main" \
        | $SUDO tee /etc/apt/sources.list.d/oneAPI.list > /dev/null

    $SUDO apt-get update -qq
    log "Installing intel-basekit (this may take a while)..."
    apt_install intel-basekit
    log "Intel oneAPI installed at /opt/intel/oneapi/"
}

install_drivers() {
    case "$BACKEND" in
        cuda)    install_nvidia_driver ;;
        hipblas) install_amd_driver    ;;
        vulkan)  install_vulkan_sdk    ;;
        sycl)    install_intel_sycl    ;;
        cpu)
            log "CPU-only mode — no GPU driver installation needed."
            if confirm "Install OpenBLAS for better CPU performance?"; then
                require_root
                apt_install libopenblas-dev
            fi
            ;;
    esac
}

# ═════════════════════════════════════════════════════════════════════════════
# STEP 4 — Clone / update repository
# ═════════════════════════════════════════════════════════════════════════════
clone_repository() {
    header "stable-diffusion.cpp Repository"

    if [[ -d "$INSTALL_DIR/.git" ]]; then
        log "Repository already exists at $INSTALL_DIR"
        if confirm "Pull latest changes?"; then
            # [FIX MEDIUM] Pull the currently tracked branch instead of hardcoding 'master'
            local branch
            branch=$(git -C "$INSTALL_DIR" symbolic-ref --short HEAD 2>/dev/null || echo "master")
            git -C "$INSTALL_DIR" pull origin "$branch"
            git -C "$INSTALL_DIR" submodule update --init --recursive
        fi
    else
        log "Cloning repository to $INSTALL_DIR ..."
        git clone --recursive https://github.com/leejet/stable-diffusion.cpp "$INSTALL_DIR"
    fi
    log "Repository ready."
}

# ═════════════════════════════════════════════════════════════════════════════
# STEP 5 — CMake build
# ═════════════════════════════════════════════════════════════════════════════
build_project() {
    header "Build — backend: ${BACKEND}"

    local NPROC
    NPROC=$(nproc)

    local cmake_extra_args=()

    case "$BACKEND" in
        cuda)
            log "Configuring with CUDA support..."
            if ! check_cmd nvcc; then
                error "nvcc not found. Install CUDA toolkit first:"
                error "  python3 install-cuda.py          # auto-install from NVIDIA repo"
                error "  python3 install-cuda.py --version 12.6  # specific version"
                error "Then re-run this script."
                exit 1
            fi
            cmake_extra_args+=(-DSD_CUDA=ON)
            ;;
        hipblas)
            log "Configuring with HipBLAS (AMD ROCm) support..."
            local GFX_NAME=""
            if check_cmd rocminfo; then
                # [FIX MEDIUM] Match GPU agents explicitly to avoid CPU/APU false positives
                GFX_NAME=$(rocminfo | awk '/Device Type.*GPU/{found=1} found && /Name:/{print $2; exit}')
            fi
            if [[ -z "$GFX_NAME" ]]; then
                warn "Could not detect AMD GPU architecture. Set GFX_NAME manually."
                warn "Example: export GFX_NAME=gfx1030"
                read -r -p "  Enter GFX_NAME (or press Enter to abort): " GFX_NAME
                [[ -z "$GFX_NAME" ]] && exit 1
            fi
            info "Building for AMD GPU: $GFX_NAME"
            # [FIX HIGH] Remove duplicate -DCMAKE_BUILD_TYPE=Release from this array;
            # it is set unconditionally on the cmake invocation line below.
            cmake_extra_args+=(
                -G "Ninja"
                -DCMAKE_C_COMPILER=clang
                -DCMAKE_CXX_COMPILER=clang++
                -DSD_HIPBLAS=ON
                -DGPU_TARGETS="$GFX_NAME"
                -DAMDGPU_TARGETS="$GFX_NAME"
                -DCMAKE_BUILD_WITH_INSTALL_RPATH=ON
                -DCMAKE_POSITION_INDEPENDENT_CODE=ON
            )
            ;;
        vulkan)
            log "Configuring with Vulkan support..."
            cmake_extra_args+=(-DSD_VULKAN=ON)
            ;;
        sycl)
            log "Configuring with SYCL (Intel) support..."
            if [[ ! -f /opt/intel/oneapi/setvars.sh ]]; then
                error "Intel oneAPI not found at /opt/intel/oneapi/setvars.sh"
                exit 1
            fi
            cmake_extra_args+=(
                -DSD_SYCL=ON
                -DCMAKE_C_COMPILER=icx
                -DCMAKE_CXX_COMPILER=icpx
            )
            ;;
        cpu)
            log "Configuring CPU-only build with OpenBLAS..."
            cmake_extra_args+=(-DGGML_OPENBLAS=ON)
            ;;
    esac

    # [FIX HIGH] Use explicit -S / -B paths instead of cd to avoid mutating the
    # shell's working directory permanently for all subsequent steps.
    log "Running CMake configure..."
    cmake -S "$INSTALL_DIR" -B "$BUILD_DIR" \
        -DCMAKE_BUILD_TYPE=Release \
        "${cmake_extra_args[@]}"

    # [FIX MEDIUM] For SYCL: source setvars.sh inside a subshell so its PATH/env
    # changes do not leak into the rest of the script (create_wrapper, run_test, etc.)
    if [[ "$BACKEND" == "sycl" ]]; then
        log "Building with $NPROC parallel jobs (SYCL — sourcing oneAPI env in subshell)..."
        (
            # shellcheck source=/dev/null
            source /opt/intel/oneapi/setvars.sh
            cmake --build "$BUILD_DIR" --config Release --parallel "$NPROC"
        )
    else
        log "Building with $NPROC parallel jobs..."
        cmake --build "$BUILD_DIR" --config Release --parallel "$NPROC"
    fi

    log "Build complete."
    info "Binaries are in: $BUILD_DIR/bin/"
}

# ═════════════════════════════════════════════════════════════════════════════
# STEP 6 — Download a sample model
# ═════════════════════════════════════════════════════════════════════════════
download_sample_model() {
    header "Sample Model Download"

    mkdir -p "$MODELS_DIR"

    echo -e "Choose a model to download:"
    echo "  1) SD 1.5 pruned (2 GB) — safe default, works on 4 GB VRAM"
    echo "  2) SDXL 1.0 base (7 GB) — higher quality, needs ≥8 GB VRAM"
    echo "  3) Skip model download"
    read -r -p "Choice [1/2/3]: " choice

    # [FIX MEDIUM] Use download_file() for atomic download + corruption prevention
    case "${choice:-1}" in
        1)
            local model_url="https://huggingface.co/stable-diffusion-v1-5/stable-diffusion-v1-5/resolve/main/v1-5-pruned-emaonly.safetensors"
            local model_file="$MODELS_DIR/v1-5-pruned-emaonly.safetensors"
            if [[ -f "$model_file" ]]; then
                log "Model already exists at $model_file"
            else
                log "Downloading SD 1.5 (~2 GB)..."
                download_file "$model_url" "$model_file"
                log "Model saved to $model_file"
            fi
            SAMPLE_MODEL="$model_file"
            ;;
        2)
            local model_url="https://huggingface.co/stabilityai/stable-diffusion-xl-base-1.0/resolve/main/sd_xl_base_1.0.safetensors"
            local model_file="$MODELS_DIR/sd_xl_base_1.0.safetensors"
            if [[ -f "$model_file" ]]; then
                log "Model already exists at $model_file"
            else
                log "Downloading SDXL 1.0 (~7 GB)..."
                download_file "$model_url" "$model_file"
                log "Model saved to $model_file"
            fi
            SAMPLE_MODEL="$model_file"
            ;;
        3)
            warn "Skipping model download."
            SAMPLE_MODEL=""
            return
            ;;
        *)
            warn "Invalid choice. Skipping."
            SAMPLE_MODEL=""
            return
            ;;
    esac
}

# ═════════════════════════════════════════════════════════════════════════════
# STEP 7 — Create helper wrapper script
# ═════════════════════════════════════════════════════════════════════════════
create_wrapper() {
    header "Wrapper Script"

    local wrapper="$INSTALL_DIR/sd"
    cat > "$wrapper" <<WRAPPER_EOF
#!/usr/bin/env bash
# Wrapper for stable-diffusion.cpp sd binary
# Generated by deploy-sd-cpp.sh

SD_BIN="$BUILD_DIR/bin/sd-cli"

if [[ ! -x "\$SD_BIN" ]]; then
    echo "Error: binary not found at \$SD_BIN" >&2
    exit 1
fi

exec "\$SD_BIN" "\$@"
WRAPPER_EOF
    chmod +x "$wrapper"
    log "Wrapper created at $wrapper"

    if confirm "Symlink 'sd' to /usr/local/bin for system-wide access? (requires sudo)"; then
        $SUDO ln -sf "$wrapper" /usr/local/bin/sd-cli
        log "Symlinked: /usr/local/bin/sd -> $wrapper"
    fi
}

# ═════════════════════════════════════════════════════════════════════════════
# STEP 8 — Quick test
# ═════════════════════════════════════════════════════════════════════════════
run_test() {
    header "Quick Test"

    local sd_bin="$BUILD_DIR/bin/sd-cli"
    if [[ ! -x "$sd_bin" ]]; then
        error "Binary not found at $sd_bin"
        return 1
    fi

    log "Binary info:"
    "$sd_bin" --help 2>&1 | head -5 || true

    if [[ -n "${SAMPLE_MODEL:-}" && -f "$SAMPLE_MODEL" ]]; then
        local output_dir="$HOME/sd-outputs"
        mkdir -p "$output_dir"
        log "Generating test image..."
        "$sd_bin" \
            -m "$SAMPLE_MODEL" \
            -p "a lovely cat sitting on a sunny window sill" \
            --steps 20 \
            -o "$output_dir/test-output.png"
        log "Test image saved to: $output_dir/test-output.png"
    else
        warn "No model available — skipping image generation test."
        info "Run manually:"
        info "  $sd_bin -m <model.safetensors> -p \"your prompt\" -o output.png"
    fi
}

# ═════════════════════════════════════════════════════════════════════════════
# STEP 9 — Print summary
# ═════════════════════════════════════════════════════════════════════════════
print_summary() {
    header "Installation Summary"

    echo -e "${BOLD}Backend:${NC}      $BACKEND"
    echo -e "${BOLD}Install dir:${NC}  $INSTALL_DIR"
    echo -e "${BOLD}Build dir:${NC}    $BUILD_DIR"
    echo -e "${BOLD}Models dir:${NC}   $MODELS_DIR"
    echo -e "${BOLD}Binary:${NC}       $BUILD_DIR/bin/sd-cli"
    echo ""
    echo -e "${BOLD}Usage examples:${NC}"
    echo "  # Text to image"
    echo "  sd -m $MODELS_DIR/<model.safetensors> -p \"your prompt\" -o output.png"
    echo ""
    echo "  # With steps and seed"
    echo "  sd -m $MODELS_DIR/<model.gguf> -p \"a sunset\" --steps 30 --seed 42 -o sunset.png"
    echo ""
    echo "  # SDXL"
    echo "  sd -m $MODELS_DIR/<sdxl.safetensors> -p \"photo\" --height 1024 --width 1024 -o sdxl.png"
    echo ""
    info "Full CLI reference: $INSTALL_DIR/examples/cli/README.md"
    info "More guides:        https://github.com/leejet/stable-diffusion.cpp"
}

# ═════════════════════════════════════════════════════════════════════════════
# MAIN
# ═════════════════════════════════════════════════════════════════════════════
main() {
    echo -e "${BOLD}${BLUE}"
    echo "╔════════════════════════════════════════════════════════╗"
    echo "║       stable-diffusion.cpp — Linux Deploy Script       ║"
    echo "╚════════════════════════════════════════════════════════╝"
    echo -e "${NC}"

    if [[ $EUID -ne 0 ]] && [[ "$SKIP_DRIVER_INSTALL" != "true" ]]; then
        warn "Not running as root. Driver installation steps will request sudo."
        warn "To skip driver install: SKIP_DRIVER_INSTALL=true $0"
        echo ""
    fi

    # [FIX LOW] install_system_deps first so lspci exists when detect_gpu runs
    install_system_deps
    detect_gpu
    install_drivers
    clone_repository
    build_project

    if [[ "$DOWNLOAD_SAMPLE_MODEL" == "true" ]]; then
        download_sample_model
    fi

    create_wrapper
    run_test
    print_summary
}

# Allow sourcing without executing
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
