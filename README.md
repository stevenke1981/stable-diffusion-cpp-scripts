# stable-diffusion.cpp Scripts

A collection of Linux deployment, model management, and inference scripts for
[leejet/stable-diffusion.cpp](https://github.com/leejet/stable-diffusion.cpp) —
a pure C/C++ Diffusion model inference engine with no external Python dependencies.

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Quick Start](#quick-start)
3. [Script Reference](#script-reference)
   - [deploy-sd-cpp.sh](#deploy-sd-cppsh)
   - [download-models.sh](#download-modelssh)
   - [start.\*.sh — Per-model inference](#startsh--per-model-inference-scripts)
4. [Supported Models](#supported-models)
5. [GPU Backends](#gpu-backends)
6. [Quantization Guide](#quantization-guide)
7. [Environment Variables](#environment-variables)
8. [Directory Layout](#directory-layout)
9. [Troubleshooting](#troubleshooting)

---

## Prerequisites

| Requirement | Notes |
|-------------|-------|
| Linux (Ubuntu 20.04/22.04/24.04 or Debian 11/12) | Other distros work but are untested |
| bash 4.0+ | Pre-installed on all modern Linux |
| git | For cloning stable-diffusion.cpp |
| cmake 3.15+ | Installed by `deploy-sd-cpp.sh` |
| GPU driver | NVIDIA / AMD / Intel — installed by `deploy-sd-cpp.sh` |
| curl / wget | For model downloads |
| 4 GB+ VRAM | 4 GB minimum (quantized models); 12 GB+ recommended |
| 16 GB+ RAM | Required when offloading model to CPU |
| 20 GB+ disk | Per model (each model is 2–24 GB) |

> **HuggingFace Token** — Required for gated models (FLUX.1-dev, SD 3.5 Large).
> Get one at https://huggingface.co/settings/tokens

---

## Quick Start

```bash
# 1. Clone this repository
git clone https://github.com/stevenke1981/stable-diffusion-cpp-scripts
cd stable-diffusion-cpp-scripts

# 2. Make all scripts executable
chmod +x *.sh

# 3. Deploy: install drivers + build from source
sudo ./deploy-sd-cpp.sh

# 4. Download a model (interactive menu)
./download-models.sh

# 5. Run inference
./start.flux-schnell.sh

# Override prompt
PROMPT="a snowy mountain at dusk" ./start.sdxl.sh
```

---

## Script Reference

### `deploy-sd-cpp.sh`

**Purpose:** Full Linux deployment — installs GPU drivers, builds stable-diffusion.cpp from source.

```bash
sudo ./deploy-sd-cpp.sh                                        # full deploy
SKIP_DRIVER_INSTALL=true ./deploy-sd-cpp.sh                    # skip driver install
BACKEND=vulkan ./deploy-sd-cpp.sh                              # force backend
INSTALL_DIR=/opt/sd MODELS_DIR=/data/models ./deploy-sd-cpp.sh # custom paths
```

**What it does (9 steps):**

| Step | Action |
|------|--------|
| 1 | Install system deps: cmake, ninja, git, curl, pciutils, libopenblas-dev |
| 2 | Auto-detect GPU via lspci / nvidia-smi / rocminfo |
| 3 | Install GPU driver + toolkit (CUDA / ROCm / Vulkan / Intel oneAPI) |
| 4 | Clone `leejet/stable-diffusion.cpp` with submodules |
| 5 | CMake configure + multi-core build |
| 6 | Download sample model (SD1.5 or SDXL, interactive) |
| 7 | Create `sd` wrapper, optional symlink to `/usr/local/bin/sd` |
| 8 | Quick test: generate one image |
| 9 | Print summary with usage examples |

**Environment variables:**

| Variable | Default | Description |
|----------|---------|-------------|
| `INSTALL_DIR` | `~/stable-diffusion.cpp` | Where to clone the repo |
| `BUILD_DIR` | `$INSTALL_DIR/build` | CMake build directory |
| `MODELS_DIR` | `~/sd-models` | Where models are stored |
| `BACKEND` | auto-detected | `cuda` \| `hipblas` \| `vulkan` \| `sycl` \| `cpu` |
| `SKIP_DRIVER_INSTALL` | `false` | Skip driver/toolkit installation |
| `DOWNLOAD_SAMPLE_MODEL` | `true` | Set `false` to skip sample model |

---

### `download-models.sh`

**Purpose:** Interactive menu to download any supported model and quantize to GGUF.

```bash
./download-models.sh             # interactive menu
HF_TOKEN=hf_xxx ./download-models.sh   # with HuggingFace token
```

**Menu options:**

| # | Model | Size | VRAM | Notes |
|---|-------|------|------|-------|
| 1 | SD 1.5 | ~2 GB | 4 GB | Most LoRA/ControlNet support |
| 2 | SDXL 1.0 + VAE | ~7 GB | 8 GB | High quality 1024px |
| 3 | SDXL Turbo | ~7 GB | 8 GB | 1-4 step generation |
| 4 | SD 3.5 Large | ~16 GB | 16 GB | ⚠ HF Token required |
| 5 | FLUX.1-dev | ~24 GB raw | 6-12 GB GGUF | ⚠ HF Token; pre-quantized fallback |
| 6 | FLUX.1-schnell | 6-12 GB | 6-12 GB | Public, no token needed |
| 7 | FLUX.2-dev | — | — | Shows documentation link |
| 8 | Chroma | ~12 GB | 12 GB | Flux-based, no T5 encoder |
| 9 | Wan2.1 T2V 1.3B | ~3 GB | 8 GB | Video generation (lightweight) |
| 10 | Wan2.1 T2V 14B | ~10 GB | 10-20 GB | Video generation (high quality) |
| 11 | Shared Encoders | ~8 GB total | — | clip_l + t5xxl + clip_g |
| 12 | TAESD | ~5 MB | — | Fast VAE decoder |
| 13 | Quantize model | — | — | Convert existing model to GGUF |
| a | All common models | — | — | 1-3, 6, 8, 11, 12 |

**Environment variables:**

| Variable | Default | Description |
|----------|---------|-------------|
| `MODELS_DIR` | `~/sd-models` | Download destination |
| `HF_TOKEN` | _(empty)_ | HuggingFace token for gated models |
| `DEFAULT_QUANT` | `q8_0` | Quantization type when converting to GGUF |
| `SD_BIN` | auto-detected | Path to `sd` binary |
| `SKIP_EXISTING` | `true` | Skip files that already exist |

---

### `start.*.sh` — Per-model inference scripts

All inference scripts follow the same pattern:

```bash
./start.<model>.sh                              # default prompt
PROMPT="your prompt" ./start.<model>.sh         # custom prompt
PROMPT="x" STEPS=30 SEED=42 ./start.sdxl.sh    # multiple overrides
./start.img2img.sh /path/to/input.png           # img2img with input
LORA_DIR=~/loras PROMPT="x <lora:name:0.8>" ./start.lora.sh
```

**Common environment variables:**

| Variable | Default | Description |
|----------|---------|-------------|
| `MODELS_DIR` | `~/sd-models` | Root model directory |
| `SD_BIN` | `~/stable-diffusion.cpp/build/bin/sd` | sd binary path |
| `OUTPUT_DIR` | `~/sd-outputs` | Output directory |
| `PROMPT` | model-specific | Generation prompt |
| `NEGATIVE` | model-specific | Negative prompt |
| `STEPS` | model-specific | Denoising steps |
| `CFG` | model-specific | CFG scale |
| `WIDTH` / `HEIGHT` | model-specific | Output resolution |
| `SEED` | `-1` (random) | RNG seed (fixed = reproducible) |
| `SAMPLER` | model-specific | Sampling method |
| `BATCH` | `1` | Images per run |
| `OUTPUT` | `~/sd-outputs/<model>_%03d.png` | Output path pattern |

#### Per-script quick reference

| Script | Resolution | Steps | CFG | Sampler | Special |
|--------|-----------|-------|-----|---------|---------|
| `start.sd15.sh` | 512×512 | 20 | 7.0 | euler_a karras | `LORA_DIR=` |
| `start.sdxl.sh` | 1024×1024 | 25 | 7.5 | dpm++2m karras | auto VAE, `LORA_DIR=` |
| `start.sdxl-turbo.sh` | 512×512 | 4 | **0.0** | euler_a | CFG must be 0 |
| `start.sd35.sh` | 1024×1024 | 28 | 4.5 | euler | SLG=2.5, needs 3 encoders |
| `start.flux-dev.sh` | 1024×1024 | 20 | **1.0** | euler | FA enabled, auto GGUF select |
| `start.flux-schnell.sh` | 1024×1024 | **4** | **1.0** | euler | FA enabled |
| `start.chroma.sh` | 1024×1024 | 20 | 1.0 | euler | No T5 encoder |
| `start.wan21-t2v-1b.sh` | 832×480 | 20 | 6.0 | euler | `FRAMES=33 FPS=24` |
| `start.wan21-t2v-14b.sh` | 1280×720 | 25 | 6.0 | euler | `FRAMES=49`, VAE on CPU |
| `start.img2img.sh` | auto | 20 | 7.0 | euler_a | `STRENGTH=0.75` |
| `start.lora.sh` | auto | 25 | 7.5 | dpm++2m | `LORA_DIR=`, `LORA_APPLY_MODE=` |

---

## Supported Models

### Image Models

| Model | VRAM (fp16) | VRAM (q4_k) | Notes |
|-------|-------------|-------------|-------|
| SD 1.5 | 4 GB | — | Richest LoRA/ControlNet ecosystem |
| SD 2.1 | 6 GB | — | v-prediction, use `--prediction v` |
| SDXL 1.0 | 8 GB | — | Best native 1024px |
| SDXL Turbo | 8 GB | — | 1-4 steps, CFG=0 |
| SD 3 / SD 3.5 | 8-16 GB | — | DiT, needs clip_l+clip_g+t5xxl |
| FLUX.1-dev | 24 GB | 6 GB | Highest quality; gated |
| FLUX.1-schnell | 24 GB | 6 GB | 4-step; public |
| FLUX.2-dev | — | ~8 GB | Needs LLM encoder |
| Chroma | ~24 GB | ~6 GB | Flux-based, no T5 |
| Qwen Image | — | — | Alibaba multimodal |
| Z-Image / Z-Image Turbo | — | — | Added 2025/12 |
| Ovis-Image | — | — | Multimodal |
| Anima | — | — | Animation style |

### Image Edit Models

| Model | Type |
|-------|------|
| FLUX.1-Kontext-dev | Reference-guided image editing |
| Qwen Image Edit / Edit 2509 | Instruction-based editing |

### Video Models

| Model | Type | Resolution | VRAM |
|-------|------|-----------|------|
| Wan2.1 T2V 1.3B | Text-to-Video | 832×480 | 8 GB |
| Wan2.1 T2V 14B | Text-to-Video | 1280×720 | 10 GB (q4) |
| Wan2.1 I2V 14B 480P | Image-to-Video | 832×480 | 10 GB |
| Wan2.1 I2V 14B 720P | Image-to-Video | 1280×720 | 12 GB |
| Wan2.1 VACE 1.3B/14B | Video editing | — | — |
| Wan2.2 TI2V 5B | Text+Image-to-Video | — | — |
| Wan2.2 T2V/I2V A14B | MoE video | — | 12 GB |

---

## GPU Backends

| GPU | Backend | cmake Flag | Toolkit |
|-----|---------|-----------|---------|
| NVIDIA | CUDA | `-DSD_CUDA=ON` | CUDA Toolkit 11.x+ |
| AMD | HipBLAS | `-DSD_HIPBLAS=ON` | ROCm 5.x+ |
| Any GPU | Vulkan | `-DSD_VULKAN=ON` | Vulkan 1.2+ driver |
| Intel GPU | SYCL | `-DSD_SYCL=ON` | Intel oneAPI Base Toolkit |
| CPU | OpenBLAS | `-DGGML_OPENBLAS=ON` | libopenblas-dev |

---

## Quantization Guide

Convert any `.safetensors` to GGUF using option `[13]` in `download-models.sh` or manually:

```bash
# Convert to q8_0
sd -M convert -m model.safetensors -o model_q8_0.gguf --type q8_0 -v

# Per-layer precision (keep VAE in f16, rest in q4_k)
sd -M convert -m model.safetensors -o out.gguf \
   --tensor-type-rules "^vae\.=f16,model\.=q4_k"
```

| Type | VRAM (Flux) | Quality | Recommended for |
|------|-------------|---------|----------------|
| `f32` | ~48 GB | ★★★★★ | Research / archival |
| `f16` | ~24 GB | ★★★★★ | 24 GB+ VRAM |
| `q8_0` | ~12 GB | ★★★★☆ | Daily use (recommended) |
| `q5_k` | ~8 GB | ★★★★☆ | 8 GB VRAM |
| `q4_k` | ~6 GB | ★★★☆☆ | 6 GB VRAM |
| `q3_k` | ~5 GB | ★★★☆☆ | 4-6 GB VRAM |
| `q2_k` | ~4 GB | ★★☆☆☆ | 4 GB minimum |

---

## Environment Variables

Add to `~/.bashrc` for persistence:

```bash
export MODELS_DIR=~/sd-models
export SD_BIN=~/stable-diffusion.cpp/build/bin/sd
export OUTPUT_DIR=~/sd-outputs
export HF_TOKEN=hf_xxxxxxxxxxxxxxxxxxxx   # for gated models
export DEFAULT_QUANT=q8_0
```

---

## Directory Layout

```
~/stable-diffusion.cpp/
│   build/bin/sd                   ← compiled binary
│   sd                             ← wrapper script
│
~/sd-models/
│   sd1x/
│   │   v1-5-pruned-emaonly.safetensors
│   sdxl/
│   │   sd_xl_base_1.0.safetensors
│   │   sdxl_vae.safetensors
│   sd3/
│   │   sd3.5_large.safetensors
│   flux/
│   │   flux1-dev-q8_0.gguf
│   │   flux1-schnell-q8_0.gguf
│   │   ae.safetensors              ← shared Flux VAE
│   chroma/
│   │   chroma-q8_0.gguf
│   wan/
│   │   wan2.1_t2v_1.3B_fp16.safetensors
│   │   wan_2.1_vae.safetensors
│   │   umt5_xxl_q8_0.gguf
│   encoders/                       ← shared text encoders
│   │   clip_l.safetensors
│   │   clip_g.safetensors
│   │   t5xxl_fp16.safetensors
│   taesd/
│       taesd_decoder.safetensors
│       taesdxl_decoder.safetensors
│
~/sd-outputs/
    sd15_001.png
    flux_dev_001.png
    wan21_1b_001.mp4
```

---

## Troubleshooting

### Binary not found

```bash
ls ~/stable-diffusion.cpp/build/bin/sd   # verify build succeeded
export SD_BIN=/custom/path/to/sd         # override path
```

### CUDA not found at build time

```bash
export PATH=$PATH:/usr/local/cuda/bin
nvcc --version
cd ~/stable-diffusion.cpp/build
cmake .. -DSD_CUDA=ON && cmake --build . --parallel $(nproc)
```

### Out of VRAM (in order of impact)

```bash
--fa                   # Flash Attention (fastest, minimal quality loss)
--vae-tiling           # Tile VAE processing
--vae-on-cpu           # Offload VAE to RAM
--clip-on-cpu          # Offload CLIP to RAM
--offload-to-cpu       # Full model to RAM (slowest)
```

Or use a lower quantization (`q4_k` or `q2_k`) via `download-models.sh [13]`.

### Black / corrupt output

```bash
--vae ~/sd-models/sdxl/sdxl_vae.safetensors   # missing VAE
--prediction v                                  # SD 2.x needs v-prediction
--cfg-scale 1.0                                 # Flux requires CFG=1.0
```

### AMD GPU not detected

```bash
export HSA_OVERRIDE_GFX_VERSION=10.3.0   # RX 6xxx series
sudo usermod -a -G render,video $USER    # add to GPU groups
# Log out and back in
```

### Re-download a failed/corrupt model

```bash
SKIP_EXISTING=false ./download-models.sh
```

---

## Links

- **stable-diffusion.cpp**: https://github.com/leejet/stable-diffusion.cpp
- **Model docs**: https://github.com/leejet/stable-diffusion.cpp/tree/master/docs
- **Pre-quantized GGUF models**: https://huggingface.co/leejet
- **This repo**: https://github.com/stevenke1981/stable-diffusion-cpp-scripts
