#!/usr/bin/env bash
# =============================================================================
# img2img — 通用圖生圖腳本（支援 SD1.5 / SDXL）
# 以輸入圖片為基礎，按提示詞重繪
# =============================================================================
set -euo pipefail

MODELS_DIR="${MODELS_DIR:-$HOME/sd-models}"
SD_BIN="${SD_BIN:-$HOME/stable-diffusion.cpp/build/bin/sd}"
OUTPUT_DIR="${OUTPUT_DIR:-$HOME/sd-outputs}"

# 自動選擇可用模型（SDXL 優先，次選 SD1.5）
if   [[ -f "$MODELS_DIR/sdxl/sd_xl_base_1.0.safetensors" ]]; then
    MODEL="$MODELS_DIR/sdxl/sd_xl_base_1.0.safetensors"
    WIDTH="${WIDTH:-1024}"; HEIGHT="${HEIGHT:-1024}"
elif [[ -f "$MODELS_DIR/sd1x/v1-5-pruned-emaonly.safetensors" ]]; then
    MODEL="$MODELS_DIR/sd1x/v1-5-pruned-emaonly.safetensors"
    WIDTH="${WIDTH:-512}"; HEIGHT="${HEIGHT:-512}"
else
    MODEL="${MODEL:-}"
fi

INPUT_IMG="${1:-${INPUT_IMG:-}}"    # 第一個參數或環境變數
PROMPT="${PROMPT:-same scene but at sunset, highly detailed}"
NEGATIVE="${NEGATIVE:-ugly, blurry, bad anatomy, worst quality}"
STRENGTH="${STRENGTH:-0.75}"        # 0.0=完全保留 / 1.0=完全重繪
STEPS="${STEPS:-20}"
CFG="${CFG:-7.0}"
SEED="${SEED:--1}"
SAMPLER="${SAMPLER:-euler_a}"
OUTPUT="${OUTPUT:-$OUTPUT_DIR/img2img_%03d.png}"

[[ ! -x "$SD_BIN" ]]  && { echo "[✗] sd binary not found: $SD_BIN"; exit 1; }
[[ -z "$MODEL" ]]     && { echo "[✗] No model found. Run ./download-models.sh first"; exit 1; }
[[ ! -f "$MODEL" ]]   && { echo "[✗] Model not found: $MODEL"; exit 1; }
[[ -z "$INPUT_IMG" ]] && { echo "Usage: $0 <input_image.png>"; echo "  or:  INPUT_IMG=image.png $0"; exit 1; }
[[ ! -f "$INPUT_IMG" ]] && { echo "[✗] Input image not found: $INPUT_IMG"; exit 1; }

mkdir -p "$OUTPUT_DIR"

CMD=("$SD_BIN"
    -m "$MODEL"
    -i "$INPUT_IMG"
    --strength "$STRENGTH"
    -p "$PROMPT"
    -n "$NEGATIVE"
    --steps "$STEPS"
    --cfg-scale "$CFG"
    -W "$WIDTH" -H "$HEIGHT"
    -s "$SEED"
    --sampling-method "$SAMPLER"
    -o "$OUTPUT"
    -v
)

echo "[i] Model   : $MODEL"
echo "[i] Input   : $INPUT_IMG"
echo "[i] Prompt  : $PROMPT"
echo "[i] Strength: $STRENGTH | Steps: $STEPS | CFG: $CFG | Size: ${WIDTH}x${HEIGHT}"
echo "[i] Output  : $OUTPUT"
echo ""

"${CMD[@]}"
