#!/usr/bin/env bash
# =============================================================================
# FLUX.1-dev — Black Forest Labs FLUX.1-dev
# 目前最高品質圖像模型，guidance distilled
# 解析度: 1024px | VRAM: q8_0≈12GB / q4_k≈6GB
# cfg-scale: 1.0 | 採樣: euler | 需要 ae + clip_l + t5xxl
# =============================================================================
set -euo pipefail

MODELS_DIR="${MODELS_DIR:-$HOME/sd-models}"
SD_BIN="${SD_BIN:-$HOME/stable-diffusion.cpp/build/bin/sd}"
OUTPUT_DIR="${OUTPUT_DIR:-$HOME/sd-outputs}"
ENC="$MODELS_DIR/encoders"
FLUX="$MODELS_DIR/flux"

# 自動選擇可用的 diffusion model（GGUF 優先，VRAM 較省）
if   [[ -f "$FLUX/flux1-dev-q8_0.gguf" ]];  then DIFFUSION_MODEL="$FLUX/flux1-dev-q8_0.gguf"
elif [[ -f "$FLUX/flux1-dev-q4_k.gguf" ]];  then DIFFUSION_MODEL="$FLUX/flux1-dev-q4_k.gguf"
elif [[ -f "$FLUX/flux1-dev.safetensors" ]]; then DIFFUSION_MODEL="$FLUX/flux1-dev.safetensors"
else DIFFUSION_MODEL="${DIFFUSION_MODEL:-}"
fi

VAE="$FLUX/ae.safetensors"
CLIP_L="$ENC/clip_l.safetensors"
T5XXL="$ENC/t5xxl_fp16.safetensors"

PROMPT="${PROMPT:-a cat holding a sign that says 'FLUX', cinematic lighting, ultra detailed}"
STEPS="${STEPS:-20}"
CFG="${CFG:-1.0}"           # Flux 固定使用 1.0
GUIDANCE="${GUIDANCE:-3.5}" # distilled guidance scale
WIDTH="${WIDTH:-1024}"
HEIGHT="${HEIGHT:-1024}"
SEED="${SEED:--1}"
SAMPLER="${SAMPLER:-euler}"
BATCH="${BATCH:-1}"
OUTPUT="${OUTPUT:-$OUTPUT_DIR/flux_dev_%03d.png}"

[[ ! -x "$SD_BIN" ]]              && { echo "[✗] sd binary not found: $SD_BIN"; exit 1; }
[[ -z "$DIFFUSION_MODEL" ]]       && { echo "[✗] No FLUX.1-dev model found in $FLUX"; echo "    Run: ./download-models.sh and choose [5]"; exit 1; }
[[ ! -f "$DIFFUSION_MODEL" ]]     && { echo "[✗] Model not found: $DIFFUSION_MODEL"; exit 1; }
[[ ! -f "$VAE" ]]                 && { echo "[✗] VAE not found: $VAE"; echo "    Run: ./download-models.sh and choose [5]"; exit 1; }
[[ ! -f "$CLIP_L" ]]              && { echo "[✗] clip_l not found: $CLIP_L"; echo "    Run: ./download-models.sh and choose [11]"; exit 1; }
[[ ! -f "$T5XXL" ]]               && { echo "[✗] t5xxl not found: $T5XXL";  echo "    Run: ./download-models.sh and choose [11]"; exit 1; }

mkdir -p "$OUTPUT_DIR"

CMD=("$SD_BIN"
    --diffusion-model "$DIFFUSION_MODEL"
    --vae "$VAE"
    --clip_l "$CLIP_L"
    --t5xxl "$T5XXL"
    -p "$PROMPT"
    --steps "$STEPS"
    --cfg-scale "$CFG"
    --guidance "$GUIDANCE"
    -W "$WIDTH" -H "$HEIGHT"
    -s "$SEED"
    --sampling-method "$SAMPLER"
    -b "$BATCH"
    --fa                 # Flash Attention — 省 VRAM + 加速
    -o "$OUTPUT"
    -v
)

echo "[i] Model   : $DIFFUSION_MODEL"
echo "[i] VAE     : $VAE"
echo "[i] Encoders: clip_l + t5xxl"
echo "[i] Prompt  : $PROMPT"
echo "[i] Steps   : $STEPS | CFG: $CFG | Guidance: $GUIDANCE | Size: ${WIDTH}x${HEIGHT}"
echo "[i] Output  : $OUTPUT"
echo ""

"${CMD[@]}"
