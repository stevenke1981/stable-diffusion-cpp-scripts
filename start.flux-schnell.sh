#!/usr/bin/env bash
# =============================================================================
# FLUX.1-schnell — Black Forest Labs FLUX.1-schnell
# 4 步快速推理版，公開授權，速度快品質略低於 dev
# 解析度: 1024px | VRAM: q8_0≈12GB / q4_k≈6GB
# cfg-scale: 1.0 | steps: 4 | 採樣: euler
# =============================================================================
set -euo pipefail

MODELS_DIR="${MODELS_DIR:-$HOME/sd-models}"
SD_BIN="${SD_BIN:-$HOME/stable-diffusion.cpp/build/bin/sd}"
OUTPUT_DIR="${OUTPUT_DIR:-$HOME/sd-outputs}"
ENC="$MODELS_DIR/encoders"
FLUX="$MODELS_DIR/flux"

# 自動選擇可用的模型（Q8 優先，Q4 次之）
if   [[ -f "$FLUX/flux1-schnell-q8_0.gguf" ]]; then DIFFUSION_MODEL="$FLUX/flux1-schnell-q8_0.gguf"
elif [[ -f "$FLUX/flux1-schnell-q4_k.gguf" ]]; then DIFFUSION_MODEL="$FLUX/flux1-schnell-q4_k.gguf"
else DIFFUSION_MODEL="${DIFFUSION_MODEL:-}"
fi

VAE="$FLUX/ae.safetensors"
CLIP_L="$ENC/clip_l.safetensors"
T5XXL="$ENC/t5xxl_fp16.safetensors"

PROMPT="${PROMPT:-a serene Japanese garden with koi fish, soft morning light}"
STEPS="${STEPS:-4}"     # schnell 標準 4 步
CFG="${CFG:-1.0}"
WIDTH="${WIDTH:-1024}"
HEIGHT="${HEIGHT:-1024}"
SEED="${SEED:--1}"
SAMPLER="${SAMPLER:-euler}"
BATCH="${BATCH:-1}"
OUTPUT="${OUTPUT:-$OUTPUT_DIR/flux_schnell_%03d.png}"

[[ ! -x "$SD_BIN" ]]          && { echo "[✗] sd binary not found: $SD_BIN"; exit 1; }
[[ -z "$DIFFUSION_MODEL" ]]   && { echo "[✗] No FLUX.1-schnell model found in $FLUX"; echo "    Run: ./download-models.sh and choose [6]"; exit 1; }
[[ ! -f "$DIFFUSION_MODEL" ]] && { echo "[✗] Model not found: $DIFFUSION_MODEL"; exit 1; }
[[ ! -f "$VAE" ]]             && { echo "[✗] VAE not found: $VAE"; exit 1; }
[[ ! -f "$CLIP_L" ]]          && { echo "[✗] clip_l not found: $CLIP_L"; exit 1; }
[[ ! -f "$T5XXL" ]]           && { echo "[✗] t5xxl not found: $T5XXL"; exit 1; }

mkdir -p "$OUTPUT_DIR"

CMD=("$SD_BIN"
    --diffusion-model "$DIFFUSION_MODEL"
    --vae "$VAE"
    --clip_l "$CLIP_L"
    --t5xxl "$T5XXL"
    -p "$PROMPT"
    --steps "$STEPS"
    --cfg-scale "$CFG"
    -W "$WIDTH" -H "$HEIGHT"
    -s "$SEED"
    --sampling-method "$SAMPLER"
    -b "$BATCH"
    --fa
    -o "$OUTPUT"
    -v
)

echo "[i] Model   : $DIFFUSION_MODEL"
echo "[i] Prompt  : $PROMPT"
echo "[i] Steps   : $STEPS (schnell 4步) | CFG: $CFG | Size: ${WIDTH}x${HEIGHT}"
echo "[i] Output  : $OUTPUT"
echo ""

"${CMD[@]}"
