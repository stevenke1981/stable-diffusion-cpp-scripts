#!/usr/bin/env bash
# =============================================================================
# SDXL 1.0 — Stable Diffusion XL
# 高品質 1024px 圖像，適合寫實/藝術風格
# 解析度: 1024px | VRAM: 8 GB | 採樣: dpm++2m karras
# =============================================================================
set -euo pipefail

MODELS_DIR="${MODELS_DIR:-$HOME/sd-models}"
SD_BIN="${SD_BIN:-$HOME/stable-diffusion.cpp/build/bin/sd-cli}"
OUTPUT_DIR="${OUTPUT_DIR:-$HOME/sd-outputs}"

MODEL="$MODELS_DIR/sdxl/sd_xl_base_1.0.safetensors"
VAE="$MODELS_DIR/sdxl/sdxl_vae.safetensors"

PROMPT="${PROMPT:-cinematic photo of a mountain landscape at golden hour, highly detailed, 8k}"
NEGATIVE="${NEGATIVE:-ugly, blurry, bad anatomy, worst quality, low quality, watermark}"
STEPS="${STEPS:-25}"
CFG="${CFG:-7.5}"
WIDTH="${WIDTH:-1024}"
HEIGHT="${HEIGHT:-1024}"
SEED="${SEED:--1}"
SAMPLER="${SAMPLER:-dpm++2m}"
SCHEDULER="${SCHEDULER:-karras}"
BATCH="${BATCH:-1}"
LORA_DIR="${LORA_DIR:-}"
OUTPUT="${OUTPUT:-$OUTPUT_DIR/sdxl_%03d.png}"

[[ ! -x "$SD_BIN" ]] && { echo "[✗] sd binary not found: $SD_BIN"; exit 1; }
[[ ! -f "$MODEL" ]]  && { echo "[✗] Model not found: $MODEL"; echo "    Run: ./download-models.sh and choose [2]"; exit 1; }

mkdir -p "$OUTPUT_DIR"

CMD=("$SD_BIN"
    -m "$MODEL"
    -p "$PROMPT"
    -n "$NEGATIVE"
    --steps "$STEPS"
    --cfg-scale "$CFG"
    -W "$WIDTH" -H "$HEIGHT"
    -s "$SEED"
    --sampling-method "$SAMPLER"
    --scheduler "$SCHEDULER"
    -b "$BATCH"
    -o "$OUTPUT"
    -v
)

[[ -f "$VAE" ]]       && CMD+=(--vae "$VAE")
[[ -n "$LORA_DIR" ]]  && CMD+=(--lora-model-dir "$LORA_DIR")

echo "[i] Model   : $MODEL"
[[ -f "$VAE" ]] && echo "[i] VAE     : $VAE"
echo "[i] Prompt  : $PROMPT"
echo "[i] Steps   : $STEPS | CFG: $CFG | Size: ${WIDTH}x${HEIGHT} | Seed: $SEED"
echo "[i] Output  : $OUTPUT"
echo ""

"${CMD[@]}"
