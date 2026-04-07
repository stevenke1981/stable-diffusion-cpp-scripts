#!/usr/bin/env bash
# =============================================================================
# Chroma — Chroma Unlocked
# 基於 Flux 架構的創意圖像模型，去除 T5 encoder（只需 clip_l + VAE）
# 解析度: 1024px | VRAM: q8_0≈12GB | 無需 t5xxl
# =============================================================================
set -euo pipefail

MODELS_DIR="${MODELS_DIR:-$HOME/sd-models}"
SD_BIN="${SD_BIN:-$HOME/stable-diffusion.cpp/build/bin/sd-cli}"
OUTPUT_DIR="${OUTPUT_DIR:-$HOME/sd-outputs}"
ENC="$MODELS_DIR/encoders"
CHROMA="$MODELS_DIR/chroma"

# 自動選擇可用模型
if   [[ -f "$CHROMA/chroma-q8_0.gguf" ]]; then DIFFUSION_MODEL="$CHROMA/chroma-q8_0.gguf"
else DIFFUSION_MODEL="${DIFFUSION_MODEL:-}"
fi

VAE="$MODELS_DIR/flux/ae.safetensors"
CLIP_L="$ENC/clip_l.safetensors"

PROMPT="${PROMPT:-a fantasy landscape with floating islands, vibrant colors, highly detailed}"
STEPS="${STEPS:-20}"
CFG="${CFG:-1.0}"
GUIDANCE="${GUIDANCE:-3.5}"
WIDTH="${WIDTH:-1024}"
HEIGHT="${HEIGHT:-1024}"
SEED="${SEED:--1}"
SAMPLER="${SAMPLER:-euler}"
BATCH="${BATCH:-1}"
OUTPUT="${OUTPUT:-$OUTPUT_DIR/chroma_%03d.png}"

[[ ! -x "$SD_BIN" ]]          && { echo "[✗] sd binary not found: $SD_BIN"; exit 1; }
[[ -z "$DIFFUSION_MODEL" ]]   && { echo "[✗] No Chroma model found in $CHROMA"; echo "    Run: ./download-models.sh and choose [8]"; exit 1; }
[[ ! -f "$DIFFUSION_MODEL" ]] && { echo "[✗] Model not found: $DIFFUSION_MODEL"; exit 1; }
[[ ! -f "$VAE" ]]             && { echo "[✗] VAE not found: $VAE"; exit 1; }
[[ ! -f "$CLIP_L" ]]          && { echo "[✗] clip_l not found: $CLIP_L"; exit 1; }

mkdir -p "$OUTPUT_DIR"

CMD=("$SD_BIN"
    --diffusion-model "$DIFFUSION_MODEL"
    --vae "$VAE"
    --clip_l "$CLIP_L"
    # 注意：Chroma 不使用 t5xxl
    -p "$PROMPT"
    --steps "$STEPS"
    --cfg-scale "$CFG"
    --guidance "$GUIDANCE"
    -W "$WIDTH" -H "$HEIGHT"
    -s "$SEED"
    --sampling-method "$SAMPLER"
    -b "$BATCH"
    --fa
    -o "$OUTPUT"
    -v
)

echo "[i] Model   : $DIFFUSION_MODEL"
echo "[i] VAE     : $VAE"
echo "[i] Encoder : clip_l only (Chroma 不需要 T5)"
echo "[i] Prompt  : $PROMPT"
echo "[i] Steps   : $STEPS | CFG: $CFG | Guidance: $GUIDANCE | Size: ${WIDTH}x${HEIGHT}"
echo "[i] Output  : $OUTPUT"
echo ""

"${CMD[@]}"
