#!/usr/bin/env bash
# =============================================================================
# SDXL Turbo — Stable Diffusion XL Turbo
# 蒸餾版 SDXL，1-4 步快速生成
# 解析度: 512px | VRAM: 8 GB | cfg-scale: 0 | steps: 1~4
# =============================================================================
set -euo pipefail

MODELS_DIR="${MODELS_DIR:-$HOME/sd-models}"
SD_BIN="${SD_BIN:-$HOME/stable-diffusion.cpp/build/bin/sd}"
OUTPUT_DIR="${OUTPUT_DIR:-$HOME/sd-outputs}"

MODEL="$MODELS_DIR/sdxl/sd_xl_turbo_1.0_fp16.safetensors"

PROMPT="${PROMPT:-a lovely cat, photorealistic}"
NEGATIVE="${NEGATIVE:-}"
STEPS="${STEPS:-4}"
CFG="${CFG:-0.0}"       # Turbo 使用 cfg-scale 0
WIDTH="${WIDTH:-512}"
HEIGHT="${HEIGHT:-512}"
SEED="${SEED:--1}"
SAMPLER="${SAMPLER:-euler_a}"
BATCH="${BATCH:-1}"
OUTPUT="${OUTPUT:-$OUTPUT_DIR/sdxl_turbo_%03d.png}"

[[ ! -x "$SD_BIN" ]] && { echo "[✗] sd binary not found: $SD_BIN"; exit 1; }
[[ ! -f "$MODEL" ]]  && { echo "[✗] Model not found: $MODEL"; echo "    Run: ./download-models.sh and choose [3]"; exit 1; }

mkdir -p "$OUTPUT_DIR"

CMD=("$SD_BIN"
    -m "$MODEL"
    -p "$PROMPT"
    --steps "$STEPS"
    --cfg-scale "$CFG"
    -W "$WIDTH" -H "$HEIGHT"
    -s "$SEED"
    --sampling-method "$SAMPLER"
    -b "$BATCH"
    -o "$OUTPUT"
    -v
)

[[ -n "$NEGATIVE" ]] && CMD+=(-n "$NEGATIVE")

echo "[i] Model   : $MODEL"
echo "[i] Prompt  : $PROMPT"
echo "[i] Steps   : $STEPS | CFG: $CFG (Turbo=0) | Size: ${WIDTH}x${HEIGHT} | Seed: $SEED"
echo "[i] Output  : $OUTPUT"
echo ""

"${CMD[@]}"
