#!/usr/bin/env bash
# =============================================================================
# stable-diffusion.cpp — Model Download & Quantization Script
# https://github.com/leejet/stable-diffusion.cpp
#
# Downloads models for all supported architectures and optionally quantizes
# them to GGUF format using the sd binary.
# =============================================================================

set -euo pipefail

# ── Colors ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'

log()    { echo -e "${GREEN}[+]${NC} $*"; }
warn()   { echo -e "${YELLOW}[!]${NC} $*"; }
error()  { echo -e "${RED}[✗]${NC} $*" >&2; }
info()   { echo -e "${CYAN}[i]${NC} $*"; }
dim()    { echo -e "${DIM}    $*${NC}"; }
header() { echo -e "\n${BOLD}${BLUE}══ $* ══${NC}\n"; }

# ── Configuration ─────────────────────────────────────────────────────────────
MODELS_DIR="${MODELS_DIR:-$HOME/sd-models}"
SD_BIN="${SD_BIN:-}"                        # path to sd binary; auto-detected if empty
HF_TOKEN="${HF_TOKEN:-}"                    # HuggingFace token (required for gated models)
DEFAULT_QUANT="${DEFAULT_QUANT:-q8_0}"      # default quantization: f16|q8_0|q5_k|q4_k|q3_k|q2_k
SKIP_EXISTING="${SKIP_EXISTING:-true}"      # skip download if file already exists

# ── Helpers ───────────────────────────────────────────────────────────────────
check_cmd() { command -v "$1" &>/dev/null; }

confirm() {
    local ans
    printf "${YELLOW}[?]${NC} %s [Y/n] " "$1"
    read -r ans
    [[ "${ans:-Y}" =~ ^[Yy]$ ]]
}

# Atomic download: temp file → mv on success to prevent corrupt partial files
download_file() {
    local url="$1"
    local dest="$2"
    local label="${3:-$(basename "$dest")}"

    if [[ "$SKIP_EXISTING" == "true" && -f "$dest" ]]; then
        log "Already exists: $label — skipping"
        return 0
    fi

    mkdir -p "$(dirname "$dest")"
    local tmp
    tmp=$(mktemp "${dest}.XXXXXX")

    local curl_args=(-L --progress-bar -o "$tmp")
    [[ -n "$HF_TOKEN" ]] && curl_args+=(-H "Authorization: Bearer $HF_TOKEN")

    if curl "${curl_args[@]}" "$url"; then
        mv "$tmp" "$dest"
        log "Saved: $dest"
    else
        rm -f "$tmp"
        error "Download failed: $url"
        return 1
    fi
}

# Find the sd binary
find_sd_bin() {
    if [[ -n "$SD_BIN" && -x "$SD_BIN" ]]; then return; fi
    for candidate in \
        "$HOME/stable-diffusion.cpp/build/bin/sd-cli" \
        "./build/bin/sd-cli" \
        "/usr/local/bin/sd" \
        "$(command -v sd 2>/dev/null || true)"
    do
        if [[ -x "$candidate" ]]; then
            SD_BIN="$candidate"
            return
        fi
    done
    SD_BIN=""
}

# Convert safetensors → GGUF with chosen quantization
quantize_model() {
    local src="$1"
    local quant="${2:-$DEFAULT_QUANT}"
    local dest="${src%.safetensors}_${quant}.gguf"
    dest="${dest%.ckpt}_${quant}.gguf"

    if [[ "$SKIP_EXISTING" == "true" && -f "$dest" ]]; then
        log "GGUF already exists: $(basename "$dest") — skipping"
        return 0
    fi

    find_sd_bin
    if [[ -z "$SD_BIN" ]]; then
        warn "sd binary not found — skipping quantization of $(basename "$src")"
        warn "Set SD_BIN=/path/to/sd or run deploy-sd-cpp.sh first"
        return 1
    fi

    log "Quantizing $(basename "$src") → $(basename "$dest") [${quant}]..."
    "$SD_BIN" -M convert -m "$src" -o "$dest" --type "$quant" -v
    log "GGUF saved: $dest"
}

# Print quantization reference table
print_quant_table() {
    echo -e "\n${BOLD}Quantization Reference (Flux.1-dev as example):${NC}"
    printf "  %-8s  %-12s  %-8s  %s\n" "Type" "VRAM (Flux)" "Quality" "Recommended for"
    printf "  %-8s  %-12s  %-8s  %s\n" "--------" "------------" "--------" "---------------"
    printf "  %-8s  %-12s  %-8s  %s\n" "f32"   "~48 GB"      "★★★★★"  "Archival/research"
    printf "  %-8s  %-12s  %-8s  %s\n" "f16"   "~24 GB"      "★★★★★"  "High-VRAM (24 GB+)"
    printf "  %-8s  %-12s  %-8s  %s\n" "q8_0"  "~12 GB"      "★★★★☆"  "Daily use (12 GB VRAM)"
    printf "  %-8s  %-12s  %-8s  %s\n" "q5_k"  "~8 GB"       "★★★★☆"  "8 GB VRAM"
    printf "  %-8s  %-12s  %-8s  %s\n" "q4_k"  "~6 GB"       "★★★☆☆"  "6 GB VRAM"
    printf "  %-8s  %-12s  %-8s  %s\n" "q3_k"  "~5 GB"       "★★★☆☆"  "4-6 GB VRAM"
    printf "  %-8s  %-12s  %-8s  %s\n" "q2_k"  "~4 GB"       "★★☆☆☆"  "Minimum (4 GB VRAM)"
    echo ""
}

# ── Shared encoder downloads ──────────────────────────────────────────────────
download_clip_encoders() {
    local dir="$MODELS_DIR/encoders"
    header "Shared Text Encoders"
    log "Downloading CLIP-L..."
    download_file \
        "https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/clip_l.safetensors" \
        "$dir/clip_l.safetensors" "clip_l"
    log "Downloading T5-XXL fp16..."
    download_file \
        "https://huggingface.co/comfyanonymous/flux_text_encoders/resolve/main/t5xxl_fp16.safetensors" \
        "$dir/t5xxl_fp16.safetensors" "t5xxl_fp16"
    log "Downloading CLIP-G (for SDXL/SD3)..."
    download_file \
        "https://huggingface.co/Comfy-Org/stable-diffusion-3.5-fp8/resolve/main/text_encoders/clip_g.safetensors" \
        "$dir/clip_g.safetensors" "clip_g"
}

download_taesd() {
    local dir="$MODELS_DIR/taesd"
    header "TAESD (Fast VAE Decoder)"
    info "Tiny AutoEncoder — 3-4x faster decoding, slight quality loss"
    download_file \
        "https://github.com/madebyollin/taesd/raw/main/taesd_decoder.safetensors" \
        "$dir/taesd_decoder.safetensors" "taesd (SD1.x)"
    download_file \
        "https://github.com/madebyollin/taesd/raw/main/taesdxl_decoder.safetensors" \
        "$dir/taesdxl_decoder.safetensors" "taesdxl (SDXL)"
}

# =============================================================================
# MODEL GROUPS
# =============================================================================

# ── SD 1.x ────────────────────────────────────────────────────────────────────
download_sd15() {
    header "SD 1.5"
    info "最廣泛使用的模型，LoRA/ControlNet 生態最豐富"
    dim "解析度: 512px | VRAM: 4 GB | 格式: safetensors"
    local dir="$MODELS_DIR/sd1x"
    download_file \
        "https://huggingface.co/stable-diffusion-v1-5/stable-diffusion-v1-5/resolve/main/v1-5-pruned-emaonly.safetensors" \
        "$dir/v1-5-pruned-emaonly.safetensors" "SD 1.5 pruned (~2 GB)"
    if confirm "Quantize SD 1.5 to GGUF ($DEFAULT_QUANT)?"; then
        quantize_model "$dir/v1-5-pruned-emaonly.safetensors"
    fi
}

# ── SDXL ──────────────────────────────────────────────────────────────────────
download_sdxl() {
    header "SDXL 1.0"
    info "高品質 1024px 圖像，適合寫實/藝術風格"
    dim "解析度: 1024px | VRAM: 8 GB | 格式: safetensors"
    local dir="$MODELS_DIR/sdxl"
    download_file \
        "https://huggingface.co/stabilityai/stable-diffusion-xl-base-1.0/resolve/main/sd_xl_base_1.0.safetensors" \
        "$dir/sd_xl_base_1.0.safetensors" "SDXL 1.0 base (~7 GB)"
    log "Downloading SDXL VAE (fp16 fix)..."
    download_file \
        "https://huggingface.co/madebyollin/sdxl-vae-fp16-fix/resolve/main/sdxl_vae.safetensors" \
        "$dir/sdxl_vae.safetensors" "SDXL VAE"
    if confirm "Quantize SDXL to GGUF ($DEFAULT_QUANT)?"; then
        quantize_model "$dir/sd_xl_base_1.0.safetensors"
    fi
}

download_sdxl_turbo() {
    header "SDXL Turbo"
    info "1-4 步快速生成，蒸餾版 SDXL"
    dim "解析度: 512px | VRAM: 8 GB | cfg-scale: 0"
    local dir="$MODELS_DIR/sdxl"
    download_file \
        "https://huggingface.co/stabilityai/sdxl-turbo/resolve/main/sd_xl_turbo_1.0_fp16.safetensors" \
        "$dir/sd_xl_turbo_1.0_fp16.safetensors" "SDXL Turbo fp16 (~7 GB)"
}

# ── SD3 / SD3.5 ───────────────────────────────────────────────────────────────
download_sd35() {
    header "SD 3.5 Large"
    info "DiT 架構新世代，需要 HuggingFace token（gated model）"
    dim "解析度: 1024px | VRAM: 16 GB | 需要 clip_l + clip_g + t5xxl"
    if [[ -z "$HF_TOKEN" ]]; then
        warn "SD3.5 是 gated model，需要 HF_TOKEN"
        warn "申請存取: https://huggingface.co/stabilityai/stable-diffusion-3.5-large"
        warn "設定方式: export HF_TOKEN=hf_xxxxxxxx"
        return 1
    fi
    local dir="$MODELS_DIR/sd3"
    download_file \
        "https://huggingface.co/stabilityai/stable-diffusion-3.5-large/resolve/main/sd3.5_large.safetensors" \
        "$dir/sd3.5_large.safetensors" "SD3.5 Large (~16 GB)"
    if confirm "Quantize SD3.5 to GGUF ($DEFAULT_QUANT)?"; then
        quantize_model "$dir/sd3.5_large.safetensors"
    fi
}

# ── FLUX ──────────────────────────────────────────────────────────────────────
download_flux_shared_vae() {
    log "Downloading Flux VAE (ae.safetensors)..."
    download_file \
        "https://huggingface.co/black-forest-labs/FLUX.1-dev/resolve/main/ae.safetensors" \
        "$MODELS_DIR/flux/ae.safetensors" "Flux VAE"
}

download_flux_dev() {
    header "FLUX.1-dev"
    info "目前最高品質圖像模型，guidance distilled 版本"
    dim "解析度: 1024px | VRAM: q8_0≈12GB / q4_k≈6GB | cfg-scale: 1.0"
    dim "需要: ae.safetensors + clip_l + t5xxl"
    if [[ -z "$HF_TOKEN" ]]; then
        warn "FLUX.1-dev 是 gated model，需要 HF_TOKEN"
        warn "申請存取: https://huggingface.co/black-forest-labs/FLUX.1-dev"

        info "替代方案：下載預量化 GGUF（無需 token）..."
        if confirm "Download pre-quantized FLUX.1-dev Q8_0 GGUF instead?"; then
            local dir="$MODELS_DIR/flux"
            download_flux_shared_vae
            download_file \
                "https://huggingface.co/leejet/FLUX.1-dev-gguf/resolve/main/flux1-dev-Q8_0.gguf" \
                "$dir/flux1-dev-q8_0.gguf" "FLUX.1-dev Q8_0 (~12 GB)"
        fi
        return
    fi
    local dir="$MODELS_DIR/flux"
    download_flux_shared_vae
    download_file \
        "https://huggingface.co/black-forest-labs/FLUX.1-dev/resolve/main/flux1-dev.safetensors" \
        "$dir/flux1-dev.safetensors" "FLUX.1-dev (~24 GB)"
    if confirm "Quantize FLUX.1-dev to GGUF ($DEFAULT_QUANT)?"; then
        quantize_model "$dir/flux1-dev.safetensors"
    fi
}

download_flux_schnell() {
    header "FLUX.1-schnell"
    info "4 步快速推理版，速度快但品質略低於 dev"
    dim "解析度: 1024px | VRAM: q8_0≈12GB | steps: 4 | cfg-scale: 1.0"
    local dir="$MODELS_DIR/flux"
    download_flux_shared_vae
    info "下載預量化 GGUF（公開，無需 token）..."
    download_file \
        "https://huggingface.co/leejet/FLUX.1-schnell-gguf/resolve/main/flux1-schnell-Q8_0.gguf" \
        "$dir/flux1-schnell-q8_0.gguf" "FLUX.1-schnell Q8_0 (~12 GB)"
    download_file \
        "https://huggingface.co/leejet/FLUX.1-schnell-gguf/resolve/main/flux1-schnell-Q4_K_M.gguf" \
        "$dir/flux1-schnell-q4_k.gguf" "FLUX.1-schnell Q4_K (~6 GB)"
}

# ── FLUX.2 ────────────────────────────────────────────────────────────────────
download_flux2_dev() {
    header "FLUX.2-dev"
    info "第二代 Flux，需要 LLM 文字編碼器（mistral-small3.2）"
    dim "解析度: 1024px | VRAM: ~8 GB (Q4) | 2026/01 新增"
    warn "FLUX.2 需要額外的 LLM encoder，模型較大，請確認 VRAM 充足"
    local dir="$MODELS_DIR/flux2"
    info "參考: https://github.com/leejet/stable-diffusion.cpp/blob/master/docs/flux2.md"
    warn "FLUX.2-dev 目前需手動下載，詳見上方文件連結"
}

# ── Chroma ────────────────────────────────────────────────────────────────────
download_chroma() {
    header "Chroma"
    info "基於 Flux 架構的創意圖像模型，去除 T5 encoder"
    dim "解析度: 1024px | VRAM: q8_0≈12GB | 無需 t5xxl"
    local dir="$MODELS_DIR/chroma"
    download_file \
        "https://huggingface.co/leejet/chroma-gguf/resolve/main/chroma-unlocked-v35-Q8_0.gguf" \
        "$dir/chroma-q8_0.gguf" "Chroma Q8_0 (~12 GB)"
    log "Downloading Chroma VAE..."
    download_file \
        "https://huggingface.co/black-forest-labs/FLUX.1-dev/resolve/main/ae.safetensors" \
        "$MODELS_DIR/flux/ae.safetensors" "Flux VAE (shared)"
}

# ── Wan Video ─────────────────────────────────────────────────────────────────
download_wan21_t2v_1b() {
    header "Wan2.1 T2V 1.3B (Text-to-Video)"
    info "輕量級影片生成，適合 VRAM 不足的使用者"
    dim "影片: 480p | VRAM: ~8 GB | 模式: vid_gen"
    local dir="$MODELS_DIR/wan"
    download_file \
        "https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/diffusion_models/wan2.1_t2v_1.3B_fp16.safetensors" \
        "$dir/wan2.1_t2v_1.3B_fp16.safetensors" "Wan2.1 T2V 1.3B (~3 GB)"
    log "Downloading Wan VAE..."
    download_file \
        "https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/vae/wan_2.1_vae.safetensors" \
        "$dir/wan_2.1_vae.safetensors" "Wan2.1 VAE"
    log "Downloading UMT5-XXL text encoder..."
    download_file \
        "https://huggingface.co/city96/umt5-xxl-encoder-gguf/resolve/main/umt5-xxl-encoder-Q8_0.gguf" \
        "$dir/umt5_xxl_q8_0.gguf" "UMT5-XXL Q8_0"
}

download_wan21_t2v_14b() {
    header "Wan2.1 T2V 14B (Text-to-Video)"
    info "高品質影片生成，14B 參數版本"
    dim "影片: 720p | VRAM: Q8_0≈20GB / Q4_K≈10GB"
    local dir="$MODELS_DIR/wan"
    download_file \
        "https://huggingface.co/city96/Wan2.1-T2V-14B-gguf/resolve/main/Wan2.1-T2V-14B-Q4_K_S.gguf" \
        "$dir/wan2.1_t2v_14B_q4k.gguf" "Wan2.1 T2V 14B Q4_K (~10 GB)"
    # VAE and encoder shared with 1.3B version
    if [[ ! -f "$dir/wan_2.1_vae.safetensors" ]]; then
        log "Downloading Wan VAE..."
        download_file \
            "https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/vae/wan_2.1_vae.safetensors" \
            "$dir/wan_2.1_vae.safetensors" "Wan2.1 VAE"
    fi
    if [[ ! -f "$dir/umt5_xxl_q8_0.gguf" ]]; then
        log "Downloading UMT5-XXL text encoder..."
        download_file \
            "https://huggingface.co/city96/umt5-xxl-encoder-gguf/resolve/main/umt5-xxl-encoder-Q8_0.gguf" \
            "$dir/umt5_xxl_q8_0.gguf" "UMT5-XXL Q8_0"
    fi
}

# ── Standalone quantization menu ──────────────────────────────────────────────
quantize_menu() {
    header "Quantize Existing Model"
    print_quant_table

    local src quant
    read -r -p "  Source model path (.safetensors or .gguf): " src
    [[ ! -f "$src" ]] && { error "File not found: $src"; return 1; }

    echo -e "\n  Available quantizations: f16 q8_0 q5_k q4_k q3_k q2_k"
    read -r -p "  Quantization type [$DEFAULT_QUANT]: " quant
    quant="${quant:-$DEFAULT_QUANT}"

    quantize_model "$src" "$quant"
}

# ── Show run commands after download ─────────────────────────────────────────
show_run_examples() {
    header "Usage Examples"
    local enc="$MODELS_DIR/encoders"
    local flux="$MODELS_DIR/flux"
    local wan="$MODELS_DIR/wan"

    echo -e "${BOLD}SD 1.5${NC}"
    echo "  sd -m $MODELS_DIR/sd1x/v1-5-pruned-emaonly.safetensors \\"
    echo "     -p \"a lovely cat\" --steps 20 --cfg-scale 7 -o out.png"
    echo ""
    echo -e "${BOLD}SDXL${NC}"
    echo "  sd -m $MODELS_DIR/sdxl/sd_xl_base_1.0.safetensors \\"
    echo "     --vae $MODELS_DIR/sdxl/sdxl_vae.safetensors \\"
    echo "     -p \"cinematic landscape\" -H 1024 -W 1024 --steps 25 -o sdxl.png"
    echo ""
    echo -e "${BOLD}FLUX.1-dev (pre-quantized GGUF)${NC}"
    echo "  sd --diffusion-model $flux/flux1-dev-q8_0.gguf \\"
    echo "     --vae $flux/ae.safetensors \\"
    echo "     --clip_l $enc/clip_l.safetensors \\"
    echo "     --t5xxl $enc/t5xxl_fp16.safetensors \\"
    echo "     -p \"a cat\" --cfg-scale 1.0 --sampling-method euler --steps 20 -o flux.png"
    echo ""
    echo -e "${BOLD}FLUX.1-schnell (4 steps)${NC}"
    echo "  sd --diffusion-model $flux/flux1-schnell-q8_0.gguf \\"
    echo "     --vae $flux/ae.safetensors \\"
    echo "     --clip_l $enc/clip_l.safetensors \\"
    echo "     --t5xxl $enc/t5xxl_fp16.safetensors \\"
    echo "     -p \"a cat\" --cfg-scale 1.0 --sampling-method euler --steps 4 -o schnell.png"
    echo ""
    echo -e "${BOLD}Wan2.1 T2V 1.3B (video)${NC}"
    echo "  sd -M vid_gen \\"
    echo "     --diffusion-model $wan/wan2.1_t2v_1.3B_fp16.safetensors \\"
    echo "     --vae $wan/wan_2.1_vae.safetensors \\"
    echo "     --t5xxl $wan/umt5_xxl_q8_0.gguf \\"
    echo "     -p \"a lovely cat playing\" --cfg-scale 6.0 \\"
    echo "     --sampling-method euler -W 832 -H 480 --video-frames 33 \\"
    echo "     --diffusion-fa -o video.mp4"
    echo ""
}

# ═════════════════════════════════════════════════════════════════════════════
# MAIN MENU
# ═════════════════════════════════════════════════════════════════════════════
print_menu() {
    echo -e "${BOLD}${BLUE}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║        stable-diffusion.cpp — Model Download Manager        ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
    echo -e "  Models dir : ${CYAN}$MODELS_DIR${NC}"
    echo -e "  SD binary  : ${CYAN}${SD_BIN:-auto-detect}${NC}"
    echo -e "  HF Token   : ${CYAN}${HF_TOKEN:+set}${HF_TOKEN:-not set (gated models unavailable)}${NC}"
    echo -e "  Default Q  : ${CYAN}$DEFAULT_QUANT${NC}"
    echo ""
    echo -e "${BOLD}  ── Image Models ───────────────────────────────────────────${NC}"
    echo "  [1]  SD 1.5          — 512px, 4 GB VRAM, 生態最豐富"
    echo "  [2]  SDXL 1.0        — 1024px, 8 GB VRAM, 高品質"
    echo "  [3]  SDXL Turbo      — 512px, 1-4步快速生成"
    echo "  [4]  SD 3.5 Large    — 1024px, 16 GB VRAM ⚠ 需要 HF Token"
    echo ""
    echo -e "${BOLD}  ── Flux Series ────────────────────────────────────────────${NC}"
    echo "  [5]  FLUX.1-dev      — 1024px, 目前最高品質 ⚠ 需要 HF Token"
    echo "  [6]  FLUX.1-schnell  — 1024px, 4步快速 (公開)"
    echo "  [7]  FLUX.2-dev      — 1024px, 第二代 (查看說明)"
    echo ""
    echo -e "${BOLD}  ── Other Image Models ──────────────────────────────────────${NC}"
    echo "  [8]  Chroma          — 1024px, 基於Flux, 無需T5"
    echo ""
    echo -e "${BOLD}  ── Video Models ────────────────────────────────────────────${NC}"
    echo "  [9]  Wan2.1 T2V 1.3B — 輕量影片生成, ~8 GB VRAM"
    echo "  [10] Wan2.1 T2V 14B  — 高品質影片生成, ~10 GB VRAM"
    echo ""
    echo -e "${BOLD}  ── Shared Components ───────────────────────────────────────${NC}"
    echo "  [11] Shared Encoders — clip_l + t5xxl + clip_g"
    echo "  [12] TAESD           — 快速 VAE decoder"
    echo ""
    echo -e "${BOLD}  ── Tools ───────────────────────────────────────────────────${NC}"
    echo "  [13] Quantize model  — 將現有模型量化為 GGUF"
    echo "  [14] Show quant table"
    echo "  [15] Show run examples"
    echo "  [a]  Download ALL image models (1-3, 5-6, 8)"
    echo "  [q]  Quit"
    echo ""
}

main() {
    find_sd_bin

    while true; do
        print_menu
        read -r -p "Choice: " choice
        case "$choice" in
            1)  download_sd15 ;;
            2)  download_sdxl ;;
            3)  download_sdxl_turbo ;;
            4)  download_sd35 ;;
            5)  download_flux_dev ;;
            6)  download_flux_schnell ;;
            7)  download_flux2_dev ;;
            8)  download_chroma ;;
            9)  download_wan21_t2v_1b ;;
            10) download_wan21_t2v_14b ;;
            11) download_clip_encoders ;;
            12) download_taesd ;;
            13) quantize_menu ;;
            14) print_quant_table ;;
            15) show_run_examples ;;
            a|A)
                download_clip_encoders
                download_sd15
                download_sdxl
                download_sdxl_turbo
                download_flux_schnell
                download_chroma
                download_taesd
                show_run_examples
                ;;
            q|Q) log "Done."; exit 0 ;;
            *) warn "Invalid choice: $choice" ;;
        esac
        echo ""
        read -r -p "Press Enter to continue..."
    done
}

# Allow sourcing without executing
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
