#!/usr/bin/env bash
# =============================================================================
# Wan2.1 T2V 14B — Text-to-Video (高品質版)
# 高品質影片生成，14B 參數
# 模式: vid_gen | 解析度: 1280x720 | VRAM: Q4_K≈10GB / Q8_0≈20GB
# =============================================================================
set -euo pipefail

MODELS_DIR="${MODELS_DIR:-$HOME/sd-models}"
SD_BIN="${SD_BIN:-$HOME/stable-diffusion.cpp/build/bin/sd}"
OUTPUT_DIR="${OUTPUT_DIR:-$HOME/sd-outputs}"
WAN="$MODELS_DIR/wan"

# 自動選擇可用的量化版本
if   [[ -f "$WAN/wan2.1_t2v_14B_q8_0.gguf" ]]; then DIFFUSION_MODEL="$WAN/wan2.1_t2v_14B_q8_0.gguf"
elif [[ -f "$WAN/wan2.1_t2v_14B_q4k.gguf" ]];  then DIFFUSION_MODEL="$WAN/wan2.1_t2v_14B_q4k.gguf"
else DIFFUSION_MODEL="${DIFFUSION_MODEL:-}"
fi

VAE="$WAN/wan_2.1_vae.safetensors"
T5XXL="$WAN/umt5_xxl_q8_0.gguf"

PROMPT="${PROMPT:-sweeping aerial view of a forest at sunrise, cinematic motion, 4K quality}"
NEGATIVE="${NEGATIVE:-色调艳丽，过曝，静态，细节模糊不清，字幕，静止，最差质量，低质量，丑陋的}"
STEPS="${STEPS:-25}"
CFG="${CFG:-6.0}"
FLOW_SHIFT="${FLOW_SHIFT:-5.0}"   # 14B 建議較高 flow-shift
WIDTH="${WIDTH:-1280}"
HEIGHT="${HEIGHT:-720}"
SEED="${SEED:--1}"
SAMPLER="${SAMPLER:-euler}"
FRAMES="${FRAMES:-49}"  # 49 frames ≈ 2 秒 @24fps
FPS="${FPS:-24}"
BATCH="${BATCH:-1}"
OUTPUT="${OUTPUT:-$OUTPUT_DIR/wan21_14b_%03d.mp4}"

[[ ! -x "$SD_BIN" ]]          && { echo "[✗] sd binary not found: $SD_BIN"; exit 1; }
[[ -z "$DIFFUSION_MODEL" ]]   && { echo "[✗] No Wan2.1 14B model found in $WAN"; echo "    Run: ./download-models.sh and choose [10]"; exit 1; }
[[ ! -f "$DIFFUSION_MODEL" ]] && { echo "[✗] Model not found: $DIFFUSION_MODEL"; exit 1; }
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
    --diffusion-fa
    --vae-on-cpu         # 14B 建議 VAE offload 省 VRAM
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
