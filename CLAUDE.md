# CLAUDE.md — stable-diffusion-cpp-scripts

This file gives Claude Code full context to work effectively in this repository
on any machine. Read it before making any changes.

---

## What This Repo Is

Shell scripts for deploying and running [leejet/stable-diffusion.cpp](https://github.com/leejet/stable-diffusion.cpp)
on Linux. The `sd` binary is a pure C/C++ Diffusion inference engine — no Python, no conda, no venv.

**This repo does NOT contain the model weights or the sd binary.**
It only contains automation scripts. The actual engine lives at `~/stable-diffusion.cpp` after deployment.

---

## Repository Structure

```
deploy-sd-cpp.sh         # Step 1: Install drivers + build sd binary from source
download-models.sh       # Step 2: Download and quantize models
start.sd15.sh            # Run SD 1.5
start.sdxl.sh            # Run SDXL 1.0
start.sdxl-turbo.sh      # Run SDXL Turbo (4-step, CFG=0)
start.sd35.sh            # Run SD 3.5 Large (needs 3 encoders + HF token)
start.flux-dev.sh        # Run FLUX.1-dev (auto-selects GGUF variant)
start.flux-schnell.sh    # Run FLUX.1-schnell (4-step, public)
start.chroma.sh          # Run Chroma (Flux-based, no T5)
start.wan21-t2v-1b.sh    # Run Wan2.1 video 1.3B
start.wan21-t2v-14b.sh   # Run Wan2.1 video 14B
start.img2img.sh         # Universal img2img (auto-selects model)
start.lora.sh            # Universal LoRA inference
README.md                # User-facing documentation
CLAUDE.md                # This file — context for Claude Code
```

---

## Key Design Decisions

### 1. All scripts use environment variables for configuration
Every parameter (paths, prompts, steps, CFG) can be overridden via env vars.
Never hardcode user-specific paths. Always default to `$HOME/...`.

```bash
# Correct pattern
MODELS_DIR="${MODELS_DIR:-$HOME/sd-models}"
SD_BIN="${SD_BIN:-$HOME/stable-diffusion.cpp/build/bin/sd}"
```

### 2. Atomic downloads — never leave corrupt files
`download-models.sh` always downloads to a temp file then `mv` on success.
This prevents re-runs from skipping a partial/corrupt file silently.

```bash
download_file() {
    local tmp=$(mktemp "${dest}.XXXXXX")
    curl ... -o "$tmp" && mv "$tmp" "$dest" || { rm -f "$tmp"; return 1; }
}
```

### 3. No `cd` in build functions — use explicit `-S`/`-B` cmake paths
`cd` inside a function permanently mutates the shell's CWD.
Always use `cmake -S "$INSTALL_DIR" -B "$BUILD_DIR"` instead.

### 4. GPU detection runs after system deps install
`lspci` (from `pciutils`) must be installed before `detect_gpu()` calls it.
In `main()`: `install_system_deps` → `detect_gpu` → `install_drivers`.

### 5. SYCL oneAPI env is scoped to a subshell
`source /opt/intel/oneapi/setvars.sh` modifies PATH/LD_LIBRARY_PATH.
Always run it inside `( ... )` so it does not leak into later steps.

### 6. ROCm installer URL uses dynamic distro codename
Never hardcode `jammy`. Read `VERSION_CODENAME` from `/etc/os-release`.

### 7. Pre-flight checks in every start script
Each start script validates that the binary and model exist before running.
Print a helpful message pointing to the download/deploy script on failure.

---

## Model & Path Conventions

### Default directory tree

```
~/sd-models/
  sd1x/      → SD 1.x models
  sdxl/      → SDXL models + VAE
  sd3/       → SD3/SD3.5 models
  flux/      → Flux models + ae.safetensors (shared VAE)
  chroma/    → Chroma models
  wan/       → Wan video models + umt5_xxl + wan_2.1_vae
  encoders/  → Shared: clip_l, clip_g, t5xxl_fp16
  taesd/     → TAESD fast decoders
  loras/     → LoRA files (user-managed)
```

### GGUF naming convention

`<model_name>_<quantization>.gguf`
Examples: `flux1-dev-q8_0.gguf`, `chroma-q8_0.gguf`, `wan2.1_t2v_14B_q4k.gguf`

### Shared encoders

These files are reused across multiple models and live in `encoders/`:
- `clip_l.safetensors` — used by: Flux, SD3.5, SDXL, Chroma
- `clip_g.safetensors` — used by: SDXL, SD3.5
- `t5xxl_fp16.safetensors` — used by: Flux, SD3.5
- `umt5_xxl_q8_0.gguf` — used by: Wan (different encoder, lives in `wan/`)

---

## Model-Specific Gotchas

| Model | Critical setting | Wrong value breaks |
|-------|-----------------|-------------------|
| FLUX.1-dev/schnell | `--cfg-scale 1.0` | Any other CFG causes blown-out output |
| FLUX.1-dev/schnell | `--sampling-method euler` | Other samplers degrade quality |
| SDXL Turbo | `--cfg-scale 0.0` | CFG > 0 causes artifacts |
| SD 2.1 | `--prediction v` | Default eps prediction gives bad output |
| SD 3.5 | `--cfg-scale 4.5` | Values far from 4.5 hurt quality |
| Chroma | Do NOT add `--t5xxl` | Chroma has no T5 encoder |
| Wan video | `-M vid_gen` mode | Default `img_gen` mode will fail |
| Wan video | `--diffusion-fa` | Without it, large VRAM usage and slow |

---

## Adding a New Model Script

When adding a `start.<model>.sh`:

1. Follow the existing pattern: env vars at the top, pre-flight checks, build CMD array, print info, exec.
2. Declare every parameter with a default: `STEPS="${STEPS:-20}"`.
3. Add a pre-flight check for the binary AND every required model file.
4. Print a helpful `echo` with the download script option when a file is missing.
5. Use `CMD=(...)` array construction — never build a string for execution.
6. Add `--fa` for Flux/DiT models by default.
7. Name output files with `_%03d.png` pattern for batch support.
8. Document the script in `README.md` under the per-script table.

Template:
```bash
#!/usr/bin/env bash
# Brief description, resolution, VRAM, key flags
set -euo pipefail

MODELS_DIR="${MODELS_DIR:-$HOME/sd-models}"
SD_BIN="${SD_BIN:-$HOME/stable-diffusion.cpp/build/bin/sd}"
OUTPUT_DIR="${OUTPUT_DIR:-$HOME/sd-outputs}"

MODEL="$MODELS_DIR/<dir>/<file>"
PROMPT="${PROMPT:-default prompt here}"
STEPS="${STEPS:-20}"
CFG="${CFG:-7.0}"
# ... other params

[[ ! -x "$SD_BIN" ]] && { echo "[✗] sd binary not found: $SD_BIN"; exit 1; }
[[ ! -f "$MODEL" ]]  && { echo "[✗] Model not found. Run: ./download-models.sh"; exit 1; }

mkdir -p "$OUTPUT_DIR"

CMD=("$SD_BIN" -m "$MODEL" -p "$PROMPT" --steps "$STEPS" --cfg-scale "$CFG" -o "$OUTPUT" -v)

echo "[i] Model : $MODEL"
echo "[i] Prompt: $PROMPT"
echo ""
"${CMD[@]}"
```

---

## Adding a New Model to `download-models.sh`

1. Add a `download_<model>()` function following the existing pattern.
2. Call `download_file "$url" "$dest" "label (~size)"` for each file.
3. Add a quantization prompt with `if confirm "Quantize..."; then quantize_model ...`.
4. Add the option to the `case` block in `main()`.
5. Add an entry to the menu in `print_menu()`.
6. Update `README.md` menu table.

---

## Shell Script Standards

- Always start with `set -euo pipefail`.
- Use `[[ ]]` not `[ ]` for conditionals.
- Use `"${var}"` quoting everywhere.
- Never use `eval` or unquoted variable expansion in commands.
- Use `printf` instead of `echo -e` for prompts.
- Temp files: always use `mktemp` and clean up with `rm -f "$tmp"` on failure.
- Arrays for commands: `CMD=(...); "${CMD[@]}"` — never build a string.
- Comments: describe *why*, not *what*.

---

## Testing Checklist

Before committing changes to any script:

- [ ] `bash -n <script.sh>` — syntax check passes
- [ ] Script runs with `SKIP_EXISTING=true` (no re-downloads)
- [ ] Pre-flight checks print clear messages when files are missing
- [ ] Works when called from a different working directory
- [ ] `MODELS_DIR=/tmp/test ./start.<model>.sh` fails gracefully with model-not-found message
- [ ] New env vars are documented in README.md

---

## Common Tasks for Claude

### "Add a new model script"
1. Read an existing similar `start.*.sh` for reference.
2. Follow the Adding a New Model Script section above.
3. Add entry to README.md per-script table.
4. Commit with `feat: add start.<model>.sh`.

### "Fix a bug in a script"
1. Read the failing script first.
2. Check the Key Design Decisions section for relevant patterns.
3. Run `bash -n <script>` to verify syntax after edit.
4. Commit with `fix: <description>`.

### "Update model URLs"
Check the official docs for current URLs:
- https://github.com/leejet/stable-diffusion.cpp/tree/master/docs
- https://huggingface.co/leejet

### "Add support for a new backend"
1. Edit `deploy-sd-cpp.sh`: add detection in `detect_gpu()`, add install function, add cmake flags in `build_project()`.
2. Update README.md GPU Backends table.
3. Follow the no-cd, subshell-for-env-sourcing patterns.

---

## Git Conventions

- Commit format: `<type>: <description>` (feat / fix / docs / chore)
- One logical change per commit
- Always update README.md when adding scripts or changing behavior
- Do not commit model files, output images, or `.env` files
- `.gitignore` excludes `.claude/` — do not remove this
