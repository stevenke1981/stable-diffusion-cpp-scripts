"""SD.cpp Web UI — FastAPI entry point."""
import argparse
import sys
from pathlib import Path

from fastapi import FastAPI
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles

from webui.router.api import router as api_router
from webui.router.ws import router as ws_router
from webui import config as cfg_mod

# ── App ───────────────────────────────────────────────────────────────────────

app = FastAPI(title="SD.cpp Web UI", version="1.0.0")

# Static assets (JS, CSS, icons)
STATIC_DIR = Path(__file__).parent / "static"
app.mount("/static", StaticFiles(directory=str(STATIC_DIR)), name="static")

# Output images served as /outputs/*
def _mount_outputs():
    conf = cfg_mod.load_config()
    out = Path(conf["output_dir"])
    out.mkdir(parents=True, exist_ok=True)
    app.mount("/outputs", StaticFiles(directory=str(out)), name="outputs")

_mount_outputs()

# Routers
app.include_router(api_router)
app.include_router(ws_router)


# ── HTML pages ────────────────────────────────────────────────────────────────

@app.get("/")
async def index():
    return FileResponse(str(STATIC_DIR / "index.html"))


@app.get("/gallery")
async def gallery_page():
    return FileResponse(str(STATIC_DIR / "gallery.html"))


@app.get("/settings")
async def settings_page():
    return FileResponse(str(STATIC_DIR / "settings.html"))


# ── Dev helper ────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    import uvicorn

    parser = argparse.ArgumentParser(description="SD.cpp Web UI")
    parser.add_argument("--host", default=None)
    parser.add_argument("--port", type=int, default=None)
    args = parser.parse_args()

    conf = cfg_mod.load_config()
    host = args.host or conf.get("host", "127.0.0.1")
    port = args.port or int(conf.get("port", 7860))

    print(f"[i] SD.cpp Web UI → http://{host}:{port}")
    uvicorn.run("webui.main:app", host=host, port=port, reload=False)
