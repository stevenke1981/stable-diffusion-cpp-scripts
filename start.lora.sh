#!/usr/bin/env bash
# =============================================================================
# LoRA — 通用 LoRA 套用腳本（搭配 SD1.5 或 SDXL）
# 在 prompt 中使用 <lora:name:weight> 語法套用 LoRA
# =============================================================================
set -euo pipefail

MODELS_DIR="${MODELS_DIR:-$HOME/sd-models}"
SD_BIN="${SD_BIN:-$HOME/stable-diffusion.cpp/build/bin/sd-cli}"
OUTPUT_DIR="${OUTPUT_DIR:-$HOME/sd-outputs}"
LORA_DIR="${LORA_DIR:-$HOME/sd-models/loras}"

# 自動選擇基底模型
if   [[ -f "$MODELS_DIR/sdxl/sd_xl_base_1.0.safetensors" ]]; then
    MODEL="$MODELS_DIR/sdxl/sd_xl_base_1.0.safetensors"
    WIDTH="${WIDTH:-1024}"; HEIGHT="${HEIGHT:-1024}"
elif [[ -f "$MODELS_DIR/sd1x/v1-5-pruned-emaonly.safetensors" ]]; then
    MODEL="$MODELS_DIR/sd1x/v1-5-pruned-emaonly.safetensors"
    WIDTH="${WIDTH:-512}"; HEIGHT="${HEIGHT:-512}"
else MODEL="${MODEL:-}"
fi

# LoRA 名稱與權重在 prompt 內指定：<lora:lora_name:0.8>
PROMPT="${PROMPT:-a portrait of a woman <lora:my_lora:0.8>, detailed face, soft lighting}"
NEGATIVE="${NEGATIVE:-ugly, blurry, bad anatomy, worst quality}"
STEPS="${STEPS:-25}"
CFG="${CFG:-7.5}"
SEED="${SEED:--1}"
SAMPLER="${SAMPLER:-dpm++2m}"
SCHEDULER="${SCHEDULER:-karras}"
LORA_APPLY_MODE="${LORA_APPLY_MODE:-auto}"   # auto | immediately | at_runtime
OUTPUT="${OUTPUT:-$OUTPUT_DIR/lora_%03d.png}"

[[ ! -x "$SD_BIN" ]]  && { echo "[✗] sd binary not found: $SD_BIN"; exit 1; }
[[ -z "$MODEL" ]]     && { echo "[✗] No model found. Run ./download-models.sh first"; exit 1; }
[[ ! -d "$LORA_DIR" ]] && { mkdir -p "$LORA_DIR"; echo "[i] Created LoRA dir: $LORA_DIR"; }

mkdir -p "$OUTPUT_DIR"

CMD=("$SD_BIN"
    -m "$MODEL"
    --lora-model-dir "$LORA_DIR"
    --lora-apply-mode "$LORA_APPLY_MODE"
    -p "$PROMPT"
    -n "$NEGATIVE"
    --steps "$STEPS"
    --cfg-scale "$CFG"
    -W "$WIDTH" -H "$HEIGHT"
    -s "$SEED"
    --sampling-method "$SAMPLER"
    --scheduler "$SCHEDULER"
    -o "$OUTPUT"
    -v
)

echo "[i] Model    : $MODEL"
echo "[i] LoRA dir : $LORA_DIR"
echo "[i] Apply    : $LORA_APPLY_MODE"
echo "[i] Prompt   : $PROMPT"
echo "[i] Steps    : $STEPS | CFG: $CFG | Size: ${WIDTH}x${HEIGHT}"
echo "[i] Output   : $OUTPUT"
echo "[!] LoRA 語法: <lora:filename_without_ext:weight>"
echo ""

"${CMD[@]}"
