#!/usr/bin/env bash
# =============================================================================
# SD 1.5 — Stable Diffusion v1.5
# 最廣泛使用的模型，LoRA/ControlNet 生態最豐富
# 解析度: 512px | VRAM: 4 GB | 採樣: euler_a
# =============================================================================
set -euo pipefail

MODELS_DIR="${MODELS_DIR:-$HOME/sd-models}"
SD_BIN="${SD_BIN:-$HOME/stable-diffusion.cpp/build/bin/sd-cli}"
OUTPUT_DIR="${OUTPUT_DIR:-$HOME/sd-outputs}"

MODEL="$MODELS_DIR/sd1x/v1-5-pruned-emaonly.safetensors"

# ── 參數（可透過環境變數覆寫）────────────────────────────────────────────────
PROMPT="${PROMPT:-a lovely cat sitting on a sunny window sill, photorealistic, 8k}"
NEGATIVE="${NEGATIVE:-ugly, blurry, bad anatomy, extra limbs, worst quality, low quality}"
STEPS="${STEPS:-20}"
CFG="${CFG:-7.0}"
WIDTH="${WIDTH:-512}"
HEIGHT="${HEIGHT:-512}"
SEED="${SEED:--1}"
SAMPLER="${SAMPLER:-euler_a}"
SCHEDULER="${SCHEDULER:-karras}"
BATCH="${BATCH:-1}"
LORA_DIR="${LORA_DIR:-}"
OUTPUT="${OUTPUT:-$OUTPUT_DIR/sd15_%03d.png}"

# ── 檢查 ──────────────────────────────────────────────────────────────────────
[[ ! -x "$SD_BIN" ]]   && { echo "[✗] sd binary not found: $SD_BIN"; exit 1; }
[[ ! -f "$MODEL" ]]    && { echo "[✗] Model not found: $MODEL"; echo "    Run: ./download-models.sh and choose [1]"; exit 1; }

mkdir -p "$OUTPUT_DIR"

# ── 組合指令 ──────────────────────────────────────────────────────────────────
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

[[ -n "$LORA_DIR" ]] && CMD+=(--lora-model-dir "$LORA_DIR")

# ── 執行 ──────────────────────────────────────────────────────────────────────
echo "[i] Model   : $MODEL"
echo "[i] Prompt  : $PROMPT"
echo "[i] Steps   : $STEPS | CFG: $CFG | Size: ${WIDTH}x${HEIGHT} | Seed: $SEED"
echo "[i] Output  : $OUTPUT"
echo ""

"${CMD[@]}"
