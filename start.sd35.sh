#!/usr/bin/env bash
# =============================================================================
# SD 3.5 Large — Stable Diffusion 3.5 Large
# DiT 架構新世代，極高品質，需要 clip_l + clip_g + t5xxl
# 解析度: 1024px | VRAM: 16 GB | cfg-scale: 4.5 | ⚠ 需要 HF Token
# =============================================================================
set -euo pipefail

MODELS_DIR="${MODELS_DIR:-$HOME/sd-models}"
SD_BIN="${SD_BIN:-$HOME/stable-diffusion.cpp/build/bin/sd-cli}"
OUTPUT_DIR="${OUTPUT_DIR:-$HOME/sd-outputs}"
ENC="$MODELS_DIR/encoders"

MODEL="$MODELS_DIR/sd3/sd3.5_large.safetensors"
CLIP_L="$ENC/clip_l.safetensors"
CLIP_G="$ENC/clip_g.safetensors"
T5XXL="$ENC/t5xxl_fp16.safetensors"

PROMPT="${PROMPT:-a majestic lion in the savanna, golden hour lighting, ultra detailed, 8k}"
NEGATIVE="${NEGATIVE:-ugly, blurry, worst quality, low quality}"
STEPS="${STEPS:-28}"
CFG="${CFG:-4.5}"       # SD3.5 建議 4.5
WIDTH="${WIDTH:-1024}"
HEIGHT="${HEIGHT:-1024}"
SEED="${SEED:--1}"
SAMPLER="${SAMPLER:-euler}"
BATCH="${BATCH:-1}"
OUTPUT="${OUTPUT:-$OUTPUT_DIR/sd35_%03d.png}"

# SLG (Skip Layer Guidance) — SD3.5 特有，可提升品質
SLG_SCALE="${SLG_SCALE:-2.5}"
SLG_START="${SLG_START:-0.01}"
SLG_END="${SLG_END:-0.2}"

[[ ! -x "$SD_BIN" ]] && { echo "[✗] sd binary not found: $SD_BIN"; exit 1; }
[[ ! -f "$MODEL" ]]  && { echo "[✗] Model not found: $MODEL"; echo "    Run: ./download-models.sh and choose [4] (需要 HF Token)"; exit 1; }
[[ ! -f "$CLIP_L" ]] && { echo "[✗] clip_l not found: $CLIP_L"; echo "    Run: ./download-models.sh and choose [11]"; exit 1; }
[[ ! -f "$CLIP_G" ]] && { echo "[✗] clip_g not found: $CLIP_G"; echo "    Run: ./download-models.sh and choose [11]"; exit 1; }
[[ ! -f "$T5XXL" ]]  && { echo "[✗] t5xxl not found: $T5XXL";  echo "    Run: ./download-models.sh and choose [11]"; exit 1; }

mkdir -p "$OUTPUT_DIR"

CMD=("$SD_BIN"
    --diffusion-model "$MODEL"
    --clip_l "$CLIP_L"
    --clip_g "$CLIP_G"
    --t5xxl "$T5XXL"
    -p "$PROMPT"
    -n "$NEGATIVE"
    --steps "$STEPS"
    --cfg-scale "$CFG"
    -W "$WIDTH" -H "$HEIGHT"
    -s "$SEED"
    --sampling-method "$SAMPLER"
    -b "$BATCH"
    --slg-scale "$SLG_SCALE"
    --skip-layer-start "$SLG_START"
    --skip-layer-end "$SLG_END"
    --clip-on-cpu        # 節省 VRAM
    -o "$OUTPUT"
    -v
)

echo "[i] Model   : $MODEL"
echo "[i] Encoders: clip_l + clip_g + t5xxl"
echo "[i] Prompt  : $PROMPT"
echo "[i] Steps   : $STEPS | CFG: $CFG | SLG: $SLG_SCALE | Size: ${WIDTH}x${HEIGHT}"
echo "[i] Output  : $OUTPUT"
echo ""

"${CMD[@]}"
