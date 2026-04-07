#!/usr/bin/env bash
# =============================================================================
# Wan2.1 T2V 1.3B — Text-to-Video (輕量版)
# 輕量級影片生成，適合 VRAM 不足的使用者
# 模式: vid_gen | 解析度: 832x480 | VRAM: ~8 GB | frames: 33
# =============================================================================
set -euo pipefail

MODELS_DIR="${MODELS_DIR:-$HOME/sd-models}"
SD_BIN="${SD_BIN:-$HOME/stable-diffusion.cpp/build/bin/sd-cli}"
OUTPUT_DIR="${OUTPUT_DIR:-$HOME/sd-outputs}"
WAN="$MODELS_DIR/wan"

DIFFUSION_MODEL="$WAN/wan2.1_t2v_1.3B_fp16.safetensors"
VAE="$WAN/wan_2.1_vae.safetensors"
T5XXL="$WAN/umt5_xxl_q8_0.gguf"   # UMT5-XXL（Wan 專用 encoder）

PROMPT="${PROMPT:-a lovely cat playing with a ball of yarn, smooth motion, high quality video}"
NEGATIVE="${NEGATIVE:-色调艳丽，过曝，静态，细节模糊不清，字幕，风格，作品，静止，最差质量，低质量，丑陋的，残缺的}"
STEPS="${STEPS:-20}"
CFG="${CFG:-6.0}"
FLOW_SHIFT="${FLOW_SHIFT:-3.0}"
WIDTH="${WIDTH:-832}"
HEIGHT="${HEIGHT:-480}"
SEED="${SEED:--1}"
SAMPLER="${SAMPLER:-euler}"
FRAMES="${FRAMES:-33}"  # 33 frames ≈ 1.4 秒 @24fps
FPS="${FPS:-24}"
BATCH="${BATCH:-1}"
OUTPUT="${OUTPUT:-$OUTPUT_DIR/wan21_1b_%03d.mp4}"

[[ ! -x "$SD_BIN" ]]          && { echo "[✗] sd binary not found: $SD_BIN"; exit 1; }
[[ ! -f "$DIFFUSION_MODEL" ]] && { echo "[✗] Model not found: $DIFFUSION_MODEL"; echo "    Run: ./download-models.sh and choose [9]"; exit 1; }
[[ ! -f "$VAE" ]]             && { echo "[✗] VAE not found: $VAE"; exit 1; }
[[ ! -f "$T5XXL" ]]           && { echo "[✗] UMT5-XXL not found: $T5XXL"; exit 1; }

mkdir -p "$OUTPUT_DIR"

CMD=("$SD_BIN"
    -M vid_gen
    --diffusion-model "$DIFFUSION_MODEL"
    --vae "$VAE"
    --t5xxl "$T5XXL"
    -p "$PROMPT"
    -n "$NEGATIVE"
    --steps "$STEPS"
    --cfg-scale "$CFG"
    --flow-shift "$FLOW_SHIFT"
    -W "$WIDTH" -H "$HEIGHT"
    -s "$SEED"
    --sampling-method "$SAMPLER"
    --video-frames "$FRAMES"
    --fps "$FPS"
    -b "$BATCH"
    --diffusion-fa       # 影片生成強烈建議開啟
    -o "$OUTPUT"
    -v
)

echo "[i] Model   : $DIFFUSION_MODEL"
echo "[i] Prompt  : $PROMPT"
echo "[i] Frames  : $FRAMES @ ${FPS}fps (~$(echo "scale=1; $FRAMES / $FPS" | bc)s)"
echo "[i] Steps   : $STEPS | CFG: $CFG | Flow-shift: $FLOW_SHIFT | Size: ${WIDTH}x${HEIGHT}"
echo "[i] Output  : $OUTPUT"
echo ""

"${CMD[@]}"
