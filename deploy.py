#!/usr/bin/env python3
"""
deploy.py — stable-diffusion.cpp one-shot installer
Supports: NVIDIA (CUDA), AMD (ROCm/HipBLAS), Vulkan, Intel (SYCL), CPU-only
Tested on: Ubuntu 20.04 / 22.04 / 24.04, Debian 11 / 12

Usage:
    python3 deploy.py                          # auto-detect GPU, full install
    python3 deploy.py --backend cpu            # force CPU-only build
    python3 deploy.py --backend cuda           # force CUDA build
    python3 deploy.py --skip-drivers           # skip driver/toolkit install
    python3 deploy.py --skip-build             # drivers only, no cmake build
    python3 deploy.py --cuda-version 12.5      # specific CUDA version
    python3 deploy.py --dry-run                # print commands without executing
"""

from __future__ import annotations

import argparse
import os
import platform
import shutil
import subprocess
import sys
import tempfile
import urllib.request
from pathlib import Path

# ── Defaults (override with env vars) ────────────────────────────────────────
INSTALL_DIR  = Path(os.environ.get("INSTALL_DIR",  Path.home() / "stable-diffusion.cpp"))
BUILD_DIR    = Path(os.environ.get("BUILD_DIR",    INSTALL_DIR / "build"))
MODELS_DIR   = Path(os.environ.get("MODELS_DIR",   Path.home() / "sd-models"))

SD_REPO      = "https://github.com/leejet/stable-diffusion.cpp"
CUDA_VERSIONS = ["12.6", "12.5", "12.4", "12.3", "12.2", "12.1", "12.0", "11.8"]

CUDA_REPO_URL = "https://developer.download.nvidia.com/compute/cuda/repos/{distro}{ver}/x86_64"
CUDA_KEYRING  = "cuda-keyring_1.1-1_all.deb"

ROCM_INSTALL_URL = "https://repo.radeon.com/amdgpu-install/6.3/ubuntu/{codename}/amdgpu-install_6.3.60300-1_all.deb"

BASHRC_PATH_SNIPPET = (
    '\n# CUDA Toolkit\n'
    'export PATH="$PATH:/usr/local/cuda/bin"\n'
    'export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:/usr/local/cuda/lib64"\n'
)

# ── Console helpers ───────────────────────────────────────────────────────────
GRN = "\033[0;32m"; YLW = "\033[1;33m"; RED = "\033[0;31m"
CYN = "\033[0;36m"; BLD = "\033[1m";    RST = "\033[0m"

def log(msg):   print(f"{GRN}[+]{RST} {msg}")
def warn(msg):  print(f"{YLW}[!]{RST} {msg}")
def error(msg): print(f"{RED}[✗]{RST} {msg}", file=sys.stderr)
def info(msg):  print(f"{CYN}[i]{RST} {msg}")
def header(msg):print(f"\n{BLD}══ {msg} ══{RST}\n")

def confirm(msg: str) -> bool:
    ans = input(f"{YLW}[?]{RST} {msg} [Y/n] ").strip().lower()
    return ans in ("", "y", "yes")

# ── subprocess helpers ────────────────────────────────────────────────────────
_DRY = False   # set by --dry-run flag
_SUDO = []     # [] if root, ["sudo"] otherwise

def _run(cmd: list[str], *, check: bool = True, env: dict | None = None) -> int:
    print(f"  $ {' '.join(str(c) for c in cmd)}")
    if _DRY:
        return 0
    result = subprocess.run(cmd, env=env)
    if check and result.returncode != 0:
        error(f"Command failed (exit {result.returncode})")
        sys.exit(result.returncode)
    return result.returncode

def sudo(*cmd, check: bool = True, env: dict | None = None) -> int:
    return _run([*_SUDO, *cmd], check=check, env=env)

def apt_update() -> None:
    sudo("apt-get", "update", "-qq")

def apt_install(*pkgs: str) -> None:
    env = {**os.environ, "DEBIAN_FRONTEND": "noninteractive"}
    _run([*_SUDO, "apt-get", "install", "-y", "--no-install-recommends", *pkgs], env=env)

def check_cmd(name: str) -> bool:
    return shutil.which(name) is not None

# ── OS detection ──────────────────────────────────────────────────────────────
def os_release() -> dict[str, str]:
    info: dict[str, str] = {}
    try:
        for line in Path("/etc/os-release").read_text().splitlines():
            if "=" in line:
                k, _, v = line.partition("=")
                info[k] = v.strip('"')
    except FileNotFoundError:
        pass
    return info

# ── Step 1: system deps ───────────────────────────────────────────────────────
def install_system_deps() -> None:
    header("System Dependencies")
    apt_update()
    apt_install(
        "build-essential", "cmake", "ninja-build", "git",
        "curl", "wget", "ca-certificates", "pkg-config",
        "libopenblas-dev", "python3", "python3-pip",
        "unzip", "pciutils",
    )
    log("System dependencies installed.")

# ── Step 2: GPU detection ─────────────────────────────────────────────────────
def detect_gpu(backend_override: str) -> str:
    header("GPU Detection")

    if backend_override:
        info(f"Backend override: {backend_override}")
        return backend_override

    nvidia = amd = intel = False

    if check_cmd("lspci"):
        out = subprocess.run(["lspci"], capture_output=True, text=True).stdout.lower()
        if "nvidia" in out:           nvidia = True
        if any(k in out for k in ("amd", "radeon", "advanced micro")): amd = True
        if any(k in out for k in ("intel.*graphics", "intel.*uhd", "intel.*iris")): intel = True

    if Path("/proc/driver/nvidia").is_dir(): nvidia = True
    if check_cmd("nvidia-smi"):              nvidia = True
    if check_cmd("rocminfo"):                amd   = True

    if nvidia:
        info("Detected: NVIDIA GPU")
        if check_cmd("nvidia-smi"):
            r = subprocess.run(
                ["nvidia-smi", "--query-gpu=name,driver_version,memory.total",
                 "--format=csv,noheader"],
                capture_output=True, text=True,
            )
            for line in r.stdout.strip().splitlines():
                info(f"  {line}")
        return "cuda"
    elif amd:
        info("Detected: AMD GPU")
        return "hipblas"
    elif intel:
        info("Detected: Intel GPU")
        return "sycl"
    else:
        warn("No discrete GPU detected — CPU-only build")
        return "cpu"

# ── Step 3a: CUDA ─────────────────────────────────────────────────────────────
def install_cuda(cuda_ver: str) -> None:
    header("NVIDIA CUDA Toolkit")

    if check_cmd("nvcc"):
        r = subprocess.run(["nvcc", "--version"], capture_output=True, text=True)
        ver_line = r.stdout.strip().splitlines()[-1] if r.stdout else ""
        log(f"nvcc already installed: {ver_line}")
        if not confirm("Re-install / upgrade CUDA toolkit?"):
            return

    rel = os_release()
    distro_id   = rel.get("ID", "ubuntu").lower()
    version_id  = rel.get("VERSION_ID", "").replace(".", "")

    # Map debian major version to keyring path
    if distro_id == "debian":
        repo_url = CUDA_REPO_URL.format(distro="debian", ver=version_id)
    else:
        repo_url = CUDA_REPO_URL.format(distro="ubuntu", ver=version_id)

    keyring_url = f"{repo_url}/{CUDA_KEYRING}"
    info(f"CUDA repo: {repo_url}")

    tmp_deb = tempfile.mktemp(suffix=".deb", prefix="/tmp/cuda-keyring-")
    try:
        log(f"Downloading cuda-keyring...")
        if not _DRY:
            try:
                urllib.request.urlretrieve(keyring_url, tmp_deb)
            except Exception as exc:
                error(f"Download failed: {exc}")
                error("Check https://developer.nvidia.com/cuda-downloads")
                sys.exit(1)
        apt_install(tmp_deb)
    finally:
        if not _DRY and Path(tmp_deb).exists():
            Path(tmp_deb).unlink()

    apt_update()
    pkg = "cuda-toolkit-" + cuda_ver.replace(".", "-")
    log(f"Installing {pkg} ...")
    apt_install(pkg)

    # Update ~/.bashrc
    bashrc = Path.home() / ".bashrc"
    if not _DRY:
        content = bashrc.read_text() if bashrc.exists() else ""
        if "/usr/local/cuda/bin" not in content:
            bashrc.open("a").write(BASHRC_PATH_SNIPPET)
            log(f"Added CUDA PATH to {bashrc}")

    log("CUDA toolkit installed.")
    warn("Run:  source ~/.bashrc   (or open a new terminal) to activate PATH.")

# ── Step 3b: AMD ROCm ─────────────────────────────────────────────────────────
def install_rocm() -> None:
    header("AMD ROCm Toolkit")

    if check_cmd("rocminfo"):
        log("ROCm already installed.")
        if not confirm("Re-install ROCm?"):
            return

    rel = os_release()
    codename = rel.get("UBUNTU_CODENAME") or rel.get("VERSION_CODENAME", "jammy")
    url = ROCM_INSTALL_URL.format(codename=codename)
    info(f"ROCm installer: {url}")

    tmp_deb = tempfile.mktemp(suffix=".deb", prefix="/tmp/amdgpu-install-")
    try:
        log("Downloading amdgpu-install...")
        if not _DRY:
            try:
                urllib.request.urlretrieve(url, tmp_deb)
            except Exception as exc:
                error(f"Download failed: {exc}")
                error("Check https://repo.radeon.com/amdgpu-install/")
                sys.exit(1)
        apt_install(tmp_deb)
    finally:
        if not _DRY and Path(tmp_deb).exists():
            Path(tmp_deb).unlink()

    apt_update()
    sudo("amdgpu-install", "--usecase=rocm", "--no-dkms", "-y")

    real_user = os.environ.get("SUDO_USER", os.environ.get("USER", ""))
    if real_user:
        sudo("usermod", "-a", "-G", "render,video", real_user, check=False)

    log("ROCm installed.")
    warn("Log out and back in (or reboot) for group membership to take effect.")

# ── Step 3c: Vulkan ───────────────────────────────────────────────────────────
def install_vulkan() -> None:
    header("Vulkan SDK")
    if check_cmd("vulkaninfo"):
        log("Vulkan already available.")
        return
    apt_install("libvulkan-dev", "vulkan-tools", "spirv-tools", "glslang-tools")
    log("Vulkan SDK installed.")

# ── Step 3d: Intel SYCL ───────────────────────────────────────────────────────
def install_sycl() -> None:
    header("Intel oneAPI Base Toolkit (SYCL)")
    if Path("/opt/intel/oneapi/setvars.sh").exists():
        log("Intel oneAPI already installed.")
        return
    log("Adding Intel oneAPI repository...")
    apt_install("wget", "gnupg2")

    key_url = "https://apt.repos.intel.com/intel-gpg-keys/GPG-PUB-KEY-INTEL-SW-PRODUCTS.PUB"
    tmp_key = tempfile.mktemp(prefix="/tmp/intel-gpg-")
    try:
        if not _DRY:
            urllib.request.urlretrieve(key_url, tmp_key)
        # pipe through gpg --dearmor → /usr/share/keyrings/
        if not _DRY:
            with open(tmp_key, "rb") as f:
                raw = f.read()
            result = subprocess.run(["gpg", "--dearmor"], input=raw, capture_output=True)
            keyring_bytes = result.stdout
            keyring_path = Path("/usr/share/keyrings/oneapi-archive-keyring.gpg")
            proc = subprocess.run(
                [*_SUDO, "tee", str(keyring_path)],
                input=keyring_bytes, capture_output=True,
            )
            if proc.returncode != 0:
                error("Failed to write Intel GPG keyring.")
                sys.exit(1)
        print(f"  $ gpg --dearmor < {tmp_key} | sudo tee /usr/share/keyrings/oneapi-archive-keyring.gpg")
    finally:
        if not _DRY and Path(tmp_key).exists():
            Path(tmp_key).unlink()

    repo_line = (
        "deb [signed-by=/usr/share/keyrings/oneapi-archive-keyring.gpg] "
        "https://apt.repos.intel.com/oneapi all main\n"
    )
    sources_path = Path("/etc/apt/sources.list.d/oneAPI.list")
    if not _DRY:
        proc = subprocess.run(
            [*_SUDO, "tee", str(sources_path)],
            input=repo_line.encode(), capture_output=True,
        )
        if proc.returncode != 0:
            error("Failed to write oneAPI sources.list.d entry.")
            sys.exit(1)
    print(f"  $ echo '...' | sudo tee {sources_path}")

    apt_update()
    log("Installing intel-basekit (this may take a while)...")
    apt_install("intel-basekit")
    log("Intel oneAPI installed at /opt/intel/oneapi/")

# ── Step 4: Clone / update repo ───────────────────────────────────────────────
def clone_repo() -> None:
    header("stable-diffusion.cpp Repository")

    if (INSTALL_DIR / ".git").is_dir():
        log(f"Repo already at {INSTALL_DIR}")
        if confirm("Pull latest changes?"):
            branch = subprocess.run(
                ["git", "-C", str(INSTALL_DIR), "symbolic-ref", "--short", "HEAD"],
                capture_output=True, text=True,
            ).stdout.strip() or "master"
            _run(["git", "-C", str(INSTALL_DIR), "pull", "origin", branch])
            _run(["git", "-C", str(INSTALL_DIR), "submodule", "update", "--init", "--recursive"])
    else:
        log(f"Cloning {SD_REPO} → {INSTALL_DIR}")
        _run(["git", "clone", "--recursive", SD_REPO, str(INSTALL_DIR)])

    log("Repository ready.")

# ── Step 5: CMake build ───────────────────────────────────────────────────────
def build(backend: str) -> None:
    header(f"CMake Build — backend: {backend}")

    import multiprocessing
    nproc = multiprocessing.cpu_count()

    cmake_args: list[str] = [
        "cmake", "-S", str(INSTALL_DIR), "-B", str(BUILD_DIR),
        "-DCMAKE_BUILD_TYPE=Release",
    ]

    if backend == "cuda":
        # Search common CUDA install paths in priority order
        nvcc = (
            shutil.which("nvcc")
            or next(
                (str(p) for p in [
                    Path("/usr/local/cuda/bin/nvcc"),
                    Path("/usr/local/cuda-12.6/bin/nvcc"),
                    Path("/usr/local/cuda-12.5/bin/nvcc"),
                    Path("/usr/local/cuda-12.4/bin/nvcc"),
                    Path("/usr/local/cuda-12/bin/nvcc"),
                    Path("/usr/local/cuda-11.8/bin/nvcc"),
                ] if p.exists()),
                None,
            )
        )
        if not nvcc:
            error("nvcc not found in PATH or common CUDA paths.")
            error("Run:  python3 deploy.py --skip-build  to install CUDA first.")
            sys.exit(1)
        log(f"nvcc: {nvcc}")
        cuda_bin = str(Path(nvcc).parent)
        cmake_args += [
            "-DSD_CUDA=ON",
            f"-DCMAKE_CUDA_COMPILER={nvcc}",
        ]
        # Ensure nvcc directory is in PATH for cmake sub-processes
        os.environ["PATH"] = cuda_bin + ":" + os.environ.get("PATH", "")
        os.environ["CUDACXX"] = nvcc

    elif backend == "hipblas":
        gfx = ""
        if check_cmd("rocminfo"):
            r = subprocess.run(["rocminfo"], capture_output=True, text=True)
            for line in r.stdout.splitlines():
                if "gfx" in line.lower() and "Name:" in line:
                    gfx = line.split()[-1].strip()
                    break
        if not gfx:
            gfx = input(f"{YLW}[?]{RST} Enter AMD GPU GFX target (e.g. gfx1030): ").strip()
            if not gfx:
                sys.exit(1)
        info(f"AMD GPU target: {gfx}")
        cmake_args += [
            "-G", "Ninja",
            "-DCMAKE_C_COMPILER=clang",
            "-DCMAKE_CXX_COMPILER=clang++",
            "-DSD_HIPBLAS=ON",
            f"-DGPU_TARGETS={gfx}",
            f"-DAMDGPU_TARGETS={gfx}",
            "-DCMAKE_BUILD_WITH_INSTALL_RPATH=ON",
            "-DCMAKE_POSITION_INDEPENDENT_CODE=ON",
        ]

    elif backend == "vulkan":
        cmake_args.append("-DSD_VULKAN=ON")

    elif backend == "sycl":
        if not Path("/opt/intel/oneapi/setvars.sh").exists():
            error("Intel oneAPI not found. Run deploy.py to install it first.")
            sys.exit(1)
        cmake_args += [
            "-DSD_SYCL=ON",
            "-DCMAKE_C_COMPILER=icx",
            "-DCMAKE_CXX_COMPILER=icpx",
        ]

    else:  # cpu
        cmake_args.append("-DGGML_OPENBLAS=ON")

    _run(cmake_args)

    build_cmd = [
        "cmake", "--build", str(BUILD_DIR),
        "--config", "Release", "--parallel", str(nproc),
    ]

    if backend == "sycl":
        log("Building with SYCL (sourcing oneAPI env)...")
        script = (
            "source /opt/intel/oneapi/setvars.sh --force && "
            + " ".join(build_cmd)
        )
        _run(["bash", "-c", script])
    else:
        log(f"Building with {nproc} parallel jobs...")
        _run(build_cmd)

    log(f"Build complete. Binaries: {BUILD_DIR}/bin/")

# ── Step 6: create wrapper ────────────────────────────────────────────────────
def create_wrapper() -> None:
    header("Wrapper Script")
    wrapper = INSTALL_DIR / "sd"
    content = (
        "#!/usr/bin/env bash\n"
        f'SD_BIN="{BUILD_DIR}/bin/sd"\n'
        '[[ ! -x "$SD_BIN" ]] && { echo "Error: binary not found at $SD_BIN" >&2; exit 1; }\n'
        'exec "$SD_BIN" "$@"\n'
    )
    if not _DRY:
        wrapper.write_text(content)
        wrapper.chmod(0o755)
    log(f"Wrapper: {wrapper}")

    if confirm("Symlink 'sd' to /usr/local/bin? (system-wide access)"):
        sudo("ln", "-sf", str(wrapper), "/usr/local/bin/sd")
        log("Symlinked: /usr/local/bin/sd")

# ── Step 7: summary ───────────────────────────────────────────────────────────
def print_summary(backend: str) -> None:
    header("Summary")
    print(f"{BLD}Backend   :{RST}  {backend}")
    print(f"{BLD}Install   :{RST}  {INSTALL_DIR}")
    print(f"{BLD}Build     :{RST}  {BUILD_DIR}")
    print(f"{BLD}Models    :{RST}  {MODELS_DIR}")
    print(f"{BLD}Binary    :{RST}  {BUILD_DIR}/bin/sd")
    print()
    print(f"{BLD}Quick test:{RST}")
    print(f"  {BUILD_DIR}/bin/sd -m {MODELS_DIR}/<model.gguf> -p \"a cat\" -o out.png")
    print()
    info("Download models: python3 download-models.py  (or ./download-models.sh)")

# ── Main ──────────────────────────────────────────────────────────────────────
def main() -> None:
    global _DRY, _SUDO

    parser = argparse.ArgumentParser(
        description="stable-diffusion.cpp one-shot installer",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    parser.add_argument("--backend", choices=["cuda", "hipblas", "vulkan", "sycl", "cpu"],
                        help="Force GPU backend (default: auto-detect)")
    parser.add_argument("--cuda-version", default=CUDA_VERSIONS[0], choices=CUDA_VERSIONS,
                        metavar="VER", help=f"CUDA version (default: {CUDA_VERSIONS[0]})")
    parser.add_argument("--skip-drivers", action="store_true",
                        help="Skip driver/toolkit installation")
    parser.add_argument("--skip-build", action="store_true",
                        help="Install drivers only, skip cmake build")
    parser.add_argument("--dry-run", action="store_true",
                        help="Print commands without executing")
    args = parser.parse_args()

    _DRY  = args.dry_run
    _SUDO = [] if os.geteuid() == 0 else ["sudo"]

    if platform.system() != "Linux":
        error("This script is for Linux only.")
        sys.exit(1)

    print(f"\n{BLD}╔══════════════════════════════════════════════════════╗{RST}")
    print(f"{BLD}║     stable-diffusion.cpp — Python Deploy Script      ║{RST}")
    print(f"{BLD}╚══════════════════════════════════════════════════════╝{RST}\n")
    info(f"Install dir : {INSTALL_DIR}")
    info(f"Models dir  : {MODELS_DIR}")
    info(f"Dry-run     : {_DRY}")
    if _SUDO:
        warn("Not root — will use sudo for privileged commands.")

    install_system_deps()
    backend = detect_gpu(args.backend or "")

    if not args.skip_drivers:
        if backend == "cuda":
            install_cuda(args.cuda_version)
        elif backend == "hipblas":
            install_rocm()
        elif backend == "vulkan":
            install_vulkan()
        elif backend == "sycl":
            install_sycl()
        else:
            log("CPU-only — no GPU driver needed.")

    if not args.skip_build:
        clone_repo()
        build(backend)
        create_wrapper()
        print_summary(backend)


if __name__ == "__main__":
    main()
