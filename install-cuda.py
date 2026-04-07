#!/usr/bin/env python3
"""
install-cuda.py — Install NVIDIA CUDA Toolkit on Ubuntu/Debian
Automatically detects distro version and installs CUDA from the official NVIDIA repo.

Usage:
    python3 install-cuda.py              # auto-detect, install latest supported
    python3 install-cuda.py --version 12.6
    python3 install-cuda.py --dry-run    # print commands without executing
"""
import argparse
import os
import platform
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.request
from pathlib import Path

# ── Supported CUDA versions (newest first) ───────────────────────────────────
CUDA_VERSIONS = ["12.6", "12.5", "12.4", "12.3", "12.2", "12.1", "12.0", "11.8"]

# Ubuntu version → cuda-keyring package URL prefix
UBUNTU_CUDA_REPO = (
    "https://developer.download.nvidia.com/compute/cuda/repos/ubuntu{ver}/x86_64"
)
DEBIAN_CUDA_REPO = (
    "https://developer.download.nvidia.com/compute/cuda/repos/debian{ver}/x86_64"
)
CUDA_KEYRING_PKG = "cuda-keyring_1.1-1_all.deb"

CUDA_DEFAULT_PATH = Path("/usr/local/cuda/bin")
PROFILE_SNIPPET = '\n# CUDA Toolkit\nexport PATH="$PATH:/usr/local/cuda/bin"\nexport LD_LIBRARY_PATH="$LD_LIBRARY_PATH:/usr/local/cuda/lib64"\n'


# ── Helpers ───────────────────────────────────────────────────────────────────

def run(cmd: list[str], *, check: bool = True, dry_run: bool = False) -> int:
    print(f"  $ {' '.join(cmd)}")
    if dry_run:
        return 0
    result = subprocess.run(cmd)
    if check and result.returncode != 0:
        print(f"[✗] Command failed (exit {result.returncode}): {' '.join(cmd)}", file=sys.stderr)
        sys.exit(result.returncode)
    return result.returncode


def sudo(*cmd, dry_run: bool = False) -> int:
    prefix = [] if os.geteuid() == 0 else ["sudo"]
    return run([*prefix, *cmd], dry_run=dry_run)


def apt_install(*packages: str, dry_run: bool = False) -> None:
    env = {**os.environ, "DEBIAN_FRONTEND": "noninteractive"}
    cmd = ([] if os.geteuid() == 0 else ["sudo"])
    cmd += ["apt-get", "install", "-y", "--no-install-recommends", *packages]
    print(f"  $ {' '.join(cmd)}")
    if not dry_run:
        result = subprocess.run(cmd, env=env)
        if result.returncode != 0:
            print(f"[✗] apt install failed for: {' '.join(packages)}", file=sys.stderr)
            sys.exit(result.returncode)


def check_cmd(name: str) -> bool:
    return shutil.which(name) is not None


# ── Distro detection ──────────────────────────────────────────────────────────

def get_os_release() -> dict[str, str]:
    info: dict[str, str] = {}
    try:
        with open("/etc/os-release") as f:
            for line in f:
                line = line.strip()
                if "=" in line:
                    k, _, v = line.partition("=")
                    info[k] = v.strip('"')
    except FileNotFoundError:
        pass
    return info


def get_distro() -> tuple[str, str, str]:
    """Returns (distro_id, version_id_nodot, codename)."""
    info = get_os_release()
    distro_id = info.get("ID", "").lower()
    version_id = info.get("VERSION_ID", "")
    codename = info.get("UBUNTU_CODENAME") or info.get("VERSION_CODENAME", "")
    version_nodot = version_id.replace(".", "")
    return distro_id, version_nodot, codename


# ── Core installation ─────────────────────────────────────────────────────────

def install_prereqs(dry_run: bool) -> None:
    print("\n[+] Installing prerequisites...")
    sudo("apt-get", "update", "-qq", dry_run=dry_run)
    apt_install("wget", "ca-certificates", "gnupg2", dry_run=dry_run)


def install_cuda_keyring(distro_id: str, version_nodot: str, dry_run: bool) -> None:
    """Download and install the NVIDIA cuda-keyring .deb."""
    if distro_id == "ubuntu":
        base_url = UBUNTU_CUDA_REPO.format(ver=version_nodot)
    elif distro_id == "debian":
        base_url = DEBIAN_CUDA_REPO.format(ver=version_nodot)
    else:
        print(f"[!] Unsupported distro '{distro_id}'. Trying ubuntu2204 repo as fallback.")
        base_url = UBUNTU_CUDA_REPO.format(ver="2204")

    keyring_url = f"{base_url}/{CUDA_KEYRING_PKG}"
    print(f"\n[+] Downloading CUDA keyring from:\n    {keyring_url}")

    tmp_deb = tempfile.mktemp(suffix=".deb", prefix="cuda-keyring-")
    try:
        if not dry_run:
            try:
                urllib.request.urlretrieve(keyring_url, tmp_deb)
            except Exception as e:
                print(f"[✗] Download failed: {e}", file=sys.stderr)
                print("[!] Check https://developer.nvidia.com/cuda-downloads for your distro.", file=sys.stderr)
                sys.exit(1)
        apt_install(tmp_deb, dry_run=dry_run)
    finally:
        if not dry_run and Path(tmp_deb).exists():
            Path(tmp_deb).unlink()

    sudo("apt-get", "update", "-qq", dry_run=dry_run)


def install_cuda_toolkit(cuda_ver: str, dry_run: bool) -> None:
    pkg = "cuda-toolkit-" + cuda_ver.replace(".", "-")
    print(f"\n[+] Installing {pkg} ...")
    apt_install(pkg, dry_run=dry_run)


def update_path_profile(dry_run: bool) -> None:
    """Append CUDA PATH export to ~/.bashrc if not already present."""
    bashrc = Path.home() / ".bashrc"
    if not dry_run:
        content = bashrc.read_text() if bashrc.exists() else ""
        if "/usr/local/cuda/bin" not in content:
            with open(bashrc, "a") as f:
                f.write(PROFILE_SNIPPET)
            print(f"[+] Added CUDA PATH to {bashrc}")
        else:
            print(f"[i] CUDA PATH already in {bashrc} — skipped")
    else:
        print(f"  [dry-run] Would append CUDA PATH snippet to {bashrc}")


def verify_nvcc() -> None:
    """Check nvcc after installation (may need PATH sourced first)."""
    nvcc_path = shutil.which("nvcc") or str(CUDA_DEFAULT_PATH / "nvcc")
    if Path(nvcc_path).exists():
        result = subprocess.run([nvcc_path, "--version"], capture_output=True, text=True)
        print("\n[✓] nvcc found:")
        print("   ", result.stdout.strip().splitlines()[-1])
    else:
        print("\n[!] nvcc not in PATH yet. Run:")
        print('    export PATH="$PATH:/usr/local/cuda/bin"')
        print("    Then re-run: nvcc --version")


# ── Main ──────────────────────────────────────────────────────────────────────

def main() -> None:
    parser = argparse.ArgumentParser(description="Install NVIDIA CUDA Toolkit")
    parser.add_argument(
        "--version",
        default=CUDA_VERSIONS[0],
        choices=CUDA_VERSIONS,
        help=f"CUDA version to install (default: {CUDA_VERSIONS[0]})",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print commands without executing",
    )
    args = parser.parse_args()

    if platform.system() != "Linux":
        print("[✗] This script is for Linux only.", file=sys.stderr)
        sys.exit(1)

    print("╔══════════════════════════════════════════╗")
    print("║   CUDA Toolkit Installer (install-cuda)  ║")
    print("╚══════════════════════════════════════════╝")

    distro_id, version_nodot, codename = get_distro()
    print(f"\n[i] Distro  : {distro_id} {version_nodot} ({codename})")
    print(f"[i] CUDA    : {args.version}")
    print(f"[i] Dry-run : {args.dry_run}")

    if check_cmd("nvcc"):
        result = subprocess.run(["nvcc", "--version"], capture_output=True, text=True)
        ver_line = result.stdout.strip().splitlines()[-1] if result.stdout else ""
        print(f"\n[i] nvcc already installed: {ver_line}")
        answer = input("[?] Re-install anyway? [y/N] ").strip().lower()
        if answer not in ("y", "yes"):
            print("[i] Skipping installation.")
            sys.exit(0)

    install_prereqs(args.dry_run)
    install_cuda_keyring(distro_id, version_nodot, args.dry_run)
    install_cuda_toolkit(args.version, args.dry_run)
    update_path_profile(args.dry_run)
    verify_nvcc()

    print("\n[✓] Done. If nvcc is still not found, run:")
    print('    source ~/.bashrc')
    print("    # or open a new terminal")


if __name__ == "__main__":
    main()
