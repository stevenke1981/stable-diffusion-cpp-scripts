# Spec — SD.cpp Web UI Prompt Manager v1.0

## 1. Technology Stack

| Layer | Choice | Reason |
|-------|--------|--------|
| Backend | FastAPI 0.111+ + Uvicorn | Async, WebSocket, fast |
| Frontend | Vue 3 (CDN) + Tailwind CSS (Play CDN) | Zero build step |
| Real-time | WebSocket `/ws/{job_id}` | Stream stdout line by line |
| Image serving | FastAPI StaticFiles | Serve OUTPUT_DIR as `/outputs` |
| Config | JSON (`~/.config/sdcpp-webui/`) | Human-editable |
| Subprocess | `asyncio.create_subprocess_exec` | Non-blocking |
| Screenshots / Testing | Playwright (dev only) | Headless verify |

No Node.js, no Webpack, no Gradio, no Electron.

---

## 2. Config Files

`~/.config/sdcpp-webui/config.json`
```json
{
  "sd_bin": "~/stable-diffusion.cpp/build/bin/sd",
  "models_dir": "~/sd-models",
  "output_dir": "~/sd-outputs",
  "lora_dir": "~/sd-models/loras",
  "controlnet_dir": "~/sd-models/controlnet",
  "taesd_dir": "~/sd-models/taesd",
  "host": "127.0.0.1",
  "port": 7860,
  "flash_attention": true,
  "vae_tiling": false,
  "vae_on_cpu": false,
  "clip_on_cpu": false,
  "threads": -1,
  "theme": "dark"
}
```

`~/.config/sdcpp-webui/presets.json` — named prompt presets  
`~/.config/sdcpp-webui/history.json` — last 100 generations  
`~/.config/sdcpp-webui/favorites.json` — starred image filenames  

---

## 3. REST API

| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/system` | Binary version + samplers + schedulers |
| GET | `/api/gpu` | nvidia-smi: name, VRAM used/total, GPU% |
| GET | `/api/models` | Detected models with defaults + availability |
| GET | `/api/loras` | All LoRA files in lora_dir (recursive) |
| GET | `/api/controlnets` | ControlNet model files |
| GET | `/api/taesd` | TAESD decoder files |
| GET/POST | `/api/config` | Read/write config |
| GET | `/api/presets` | All presets |
| POST | `/api/presets` | Save/overwrite preset `{name, data}` |
| DELETE | `/api/presets/{name}` | Delete preset |
| GET | `/api/history` | Last 100 generation entries |
| GET | `/api/gallery` | Image list with pagination + favorites_only filter |
| POST | `/api/favorites/{filename}` | Toggle star on image |
| POST | `/api/upload` | Upload image (img2img / controlnet) → temp path |
| POST | `/api/generate` | Start job → `{job_id}` |
| POST | `/api/cancel` | SIGTERM running job |
| GET | `/api/status` | Running job status + progress |
| GET | `/api/image-meta/{filename}` | PNG text chunk metadata |

---

## 4. WebSocket Protocol

`WS /ws/{job_id}`

Server → client JSON messages:

```json
{ "type": "log",      "line": "step 5 / 20 ..." }
{ "type": "progress", "current": 5, "total": 20 }
{ "type": "done",     "outputs": ["/outputs/flux_001.png"], "seed": 42 }
{ "type": "error",    "message": "Process exited with code 1" }
{ "type": "ping" }
```

Reconnect with same `job_id` replays buffered lines.

---

## 5. Model Detection

| Model ID | Path pattern | CLI mode | Key flags |
|----------|-------------|----------|-----------|
| flux-dev | `flux/flux1-dev*.gguf` | `--diffusion-model` | `--vae`, `--clip_l`, `--t5xxl`, `--fa` |
| flux-schnell | `flux/flux1-schnell*.gguf` | `--diffusion-model` | same, steps=4 |
| chroma | `chroma/chroma-*.gguf` | `--diffusion-model` | `--vae`, `--clip_l` only |
| sd35 | `sd3/*.safetensors` | `--diffusion-model` | clip_l + clip_g + t5xxl |
| sdxl | `sdxl/sd_xl_base_1.0.safetensors` | `-m` | — |
| sdxl-turbo | `sdxl/sd_xl_turbo*.safetensors` | `-m` | cfg=0 |
| sd15 | `sd1x/*.safetensors` | `-m` | — |

Per-model defaults auto-applied on selection:

| Model | Steps | CFG | Guidance | Sampler | Default W×H |
|-------|-------|-----|---------|---------|------------|
| FLUX dev | 20 | 1.0 | 3.5 | euler | 1280×720 |
| FLUX schnell | 4 | 1.0 | 3.5 | euler | 1280×720 |
| Chroma | 30 | 7.0 | — | dpm++2m | 1280×720 |
| SD 3.5 | 28 | 4.5 | — | euler | 1280×720 |
| SDXL | 25 | 7.5 | — | dpm++2m | 1280×720 |
| SDXL Turbo | 4 | 0.0 | — | euler | 1280×720 |
| SD 1.5 | 25 | 7.5 | — | dpm++2m | 1280×720 |

---

## 6. Resolution Presets (default: 720p Landscape)

| Label | W | H |
|-------|---|---|
| **720p Landscape** ← default | 1280 | 720 |
| 720p Portrait | 720 | 1280 |
| 1080p Landscape | 1920 | 1080 |
| 1080p Portrait | 1080 | 1920 |
| Square 1K | 1024 | 1024 |
| Square 768 | 768 | 768 |
| 2K Landscape | 2048 | 1152 |
| Custom | input | input |

Custom W/H auto-snapped to nearest multiple of 64 on blur.

---

## 7. 10 Extra Features

### F1 — Prompt History
- Auto-saved to `history.json` on every `POST /api/generate`
- Up to 100 entries: model, positive, negative, seed, W×H, timestamp
- One-click reload from history panel in main page

### F2 — img2img
- Drag-and-drop or click-to-upload on left panel
- File uploaded to `/api/upload` → temp path stored as `img2img_path`
- Strength slider (0.01–1.0)
- Passed to sd binary as `-i <path> --strength <value>`

### F3 — ControlNet
- Scan `controlnet_dir` for model files
- Upload control image to `/api/upload`
- Strength slider (0–2.0)
- Passed as `--control-net`, `--control-image`, `--control-strength`

### F4 — GPU/VRAM Monitor
- `GET /api/gpu` polls `nvidia-smi --query-gpu=name,memory.used,memory.total,utilization.gpu`
- Frontend polls every 5 seconds via `setInterval`
- Displayed in navbar: name, used/total VRAM (MB), GPU% (red if >80%)

### F5 — Seed Lock & Randomize
- 🎲 button: sets `seed = Math.random() * 4294967295` (disabled when locked)
- 🔒 button: toggle lock; when locked, seed persists across generations
- "Use seed" button in output panel locks last resolved seed
- "Copy seed" button copies last seed to clipboard

### F6 — Smart Tag Builder
- 8 tag groups: Quality, Style, Subject, Mood + Negative (common)
- Click any tag → appended to positive prompt at cursor (with `, ` separator)
- Collapsible panel to save space
- Approximate CLIP token counter below positive prompt (warn >77)

### F7 — Seed Variations
- 🎲×4 button (enabled when `lastSeed !== -1`)
- Queues seeds: `[+1, +2, -1, -2]` relative to last seed
- Each variation fires after previous WebSocket connection closes
- All output images accumulate in the output panel for comparison

### F8 — Favorites Gallery
- `POST /api/favorites/{filename}` toggles favorite (stored in `favorites.json`)
- Gallery page: "★ Favorites only" checkbox filter
- Star icon on hover in both main page thumbnails and gallery grid
- Lightbox shows ★ Favorited / ☆ Favorite toggle button

### F9 — VRAM Options
- Left panel "VRAM Options" section:
  - VAE Tiling → `--vae-tiling`
  - VAE on CPU → `--vae-on-cpu`
  - CLIP on CPU → `--clip-on-cpu`
- TAESD fast decoder dropdown (scans `taesd_dir`)
- Settings page: persistent Flash Attention + VRAM defaults

### F10 — Image Metadata Viewer
- `GET /api/image-meta/{filename}` reads PNG text chunks via Pillow
- Returns: `{ size: {w, h}, meta: {key: value, ...} }`
- Gallery lightbox shows metadata panel below image
- Gallery grid: ℹ button opens dedicated metadata dialog

---

## 8. CMD Construction

`generator.py:build_cmd()` mirrors existing shell scripts exactly:

```python
# diffusion-model style (Flux, SD3.5, Chroma)
cmd = [sd_bin, "--diffusion-model", path, "--vae", vae, "--clip_l", clip_l]
if t5xxl: cmd += ["--t5xxl", t5xxl]
if clip_g: cmd += ["--clip_g", clip_g]

# model style (SD1.5, SDXL)
cmd = [sd_bin, "-m", path]

# common
cmd += ["-p", positive, "-n", negative]
cmd += ["--steps", steps, "--cfg-scale", cfg]
if guidance: cmd += ["--guidance", guidance]
cmd += ["-W", width, "-H", height, "-s", seed]
cmd += ["--sampling-method", sampler]
if scheduler: cmd += ["--scheduler", scheduler]
cmd += ["-b", batch]
if loras_enabled: cmd += ["--lora-model-dir", lora_dir]
if img2img: cmd += ["-i", path, "--strength", strength]
if controlnet: cmd += ["--control-net", model, "--control-image", img, "--control-strength", s]
if taesd: cmd += ["--taesd", path]
if vae_tiling: cmd += ["--vae-tiling"]
if vae_on_cpu: cmd += ["--vae-on-cpu"]
if clip_on_cpu: cmd += ["--clip-on-cpu"]
if flash_attention and mode=="diffusion_model": cmd += ["--fa"]
if threads > 0: cmd += ["-t", threads]
cmd += ["-o", output_pattern, "-v"]
```

---

## 9. Launch Scripts

`./launch-webui.sh` — auto-creates venv, installs deps, starts uvicorn  
`launch-webui.bat` — Windows equivalent  

```bash
# Quick start
./launch-webui.sh

# LAN access
HOST=0.0.0.0 ./launch-webui.sh

# SSH tunnel
ssh -L 7860:localhost:7860 user@server
```

---

## 10. Acceptance Criteria (all verified)

- [x] 14/14 API endpoint tests pass (TestClient)
- [x] Main page loads with correct 3-column layout
- [x] Settings page shows all config fields with correct defaults
- [x] Gallery page renders with favorites filter
- [x] GPU monitor visible in navbar (NVIDIA RTX detected)
- [x] Binary not-found banner shown when sd binary missing
- [x] Model selector shows "No models detected" (no models on test machine)
- [x] All 10 extra features implemented and wired to backend
- [x] App runs on Windows via `launch-webui.bat`
- [x] SSH tunnel instructions in Settings page
