# Plan — SD.cpp Web UI Prompt Manager

**Status: SHIPPED v1.0**

## Overview

**FastAPI + Vue 3 (CDN)** web application for stable-diffusion.cpp.  
Browser-based UI — works locally, over SSH tunnel, or on LAN.  
No Gradio, no Electron, no Node.js build step.

Backend: FastAPI + Uvicorn (Python 3.11+)  
Frontend: Vue 3 via CDN + Tailwind CSS via CDN  
Real-time: WebSocket `/ws/{job_id}`  
Images: FastAPI StaticFiles mount on OUTPUT_DIR  

---

## 10 Features Implemented

| # | Feature | Where |
|---|---------|-------|
| 1 | **Prompt History** | Auto-saves 100 entries; one-click reload in history panel |
| 2 | **img2img** | Drag-and-drop or click upload; strength slider |
| 3 | **ControlNet** | Model select + control image upload + strength control |
| 4 | **GPU/VRAM Monitor** | nvidia-smi polling every 5s in navbar |
| 5 | **Seed Lock & Randomize** | 🎲 randomize + 🔒 lock seed buttons |
| 6 | **Smart Tag Builder** | Clickable quality/style/mood/subject tags → appended to prompt |
| 7 | **Seed Variations** | 🎲×4 generates seed ±1, ±2 chained via WebSocket queue |
| 8 | **Favorites Gallery** | Star/unstar images; filter-by-favorites in Gallery page |
| 9 | **VRAM Options** | VAE Tiling, VAE on CPU, CLIP on CPU toggles + TAESD fast decoder |
| 10 | **Image Metadata Viewer** | PNG metadata (size + text chunks) shown in gallery lightbox |

---

## File Tree

```
stable-diffusion.cpp_scripts/
├── webui/
│   ├── __init__.py
│   ├── main.py               FastAPI app, page routes, StaticFiles
│   ├── config.py             Config + presets + history + favorites JSON I/O
│   ├── env_detect.py         Scan models/LoRAs/ControlNet/TAESD + GPU info
│   ├── generator.py          CMD builder + async subprocess + job state + WS broadcast
│   └── router/
│       ├── __init__.py
│       ├── api.py            REST endpoints (/api/*)
│       └── ws.py             WebSocket /ws/{job_id}
│   └── static/
│       ├── index.html        Main generation page (Vue 3 SPA)
│       ├── gallery.html      Full output gallery with masonry grid
│       └── settings.html     Settings page
├── launch-webui.sh           Linux/macOS launcher (auto venv)
├── launch-webui.bat          Windows launcher
├── requirements.txt          fastapi, uvicorn, aiofiles, Pillow
└── ... (existing shell scripts unchanged)
```

---

## Remote Access

```bash
# Local
./launch-webui.sh                      # → http://localhost:7860

# LAN (same network)
HOST=0.0.0.0 ./launch-webui.sh        # → http://<server-ip>:7860

# SSH tunnel (internet remote, secure)
./launch-webui.sh                      # server: default 127.0.0.1
ssh -L 7860:localhost:7860 user@host  # client: then open http://localhost:7860
```

---

## Phases Completed

- [x] Phase 1 — Backend scaffold + config + env_detect
- [x] Phase 2 — Static file serving + page routes
- [x] Phase 3 — Main window layout (3-column Vue SPA)
- [x] Phase 4 — Prompt editor with tag builder + token counter
- [x] Phase 5 — LoRA panel with weight sliders + inject
- [x] Phase 6 — Model selector + per-model defaults + resolution presets
- [x] Phase 7 — Generate + WebSocket streaming + progress bar
- [x] Phase 8 — Gallery page with masonry grid + favorites
- [x] Phase 9 — Settings page with binary test
- [x] Phase 10 — 10 extra features + code review + bug fixes + GitHub push
