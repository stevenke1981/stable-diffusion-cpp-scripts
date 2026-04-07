"""REST API routes."""
import asyncio
import json
import time
from pathlib import Path
from typing import Optional

import aiofiles
from fastapi import APIRouter, File, HTTPException, UploadFile
from fastapi.responses import JSONResponse
from pydantic import BaseModel

from webui import config as cfg_mod
from webui.env_detect import (
    SAMPLERS, SCHEDULERS,
    detect_controlnets, detect_loras, detect_models,
    detect_taesd, get_binary_version, get_gpu_info,
)
from webui.generator import current_job, new_job, run_job

router = APIRouter(prefix="/api")

# ── Pydantic models ───────────────────────────────────────────────────────────

class LoraEntry(BaseModel):
    name: str
    weight: float = 1.0
    enabled: bool = False


class GenerateRequest(BaseModel):
    model_id: str
    positive: str = ""
    negative: str = ""
    loras: list[LoraEntry] = []
    steps: int = 20
    cfg: float = 7.5
    guidance: Optional[float] = None
    width: int = 1280
    height: int = 720
    seed: int = -1
    sampler: str = "euler"
    scheduler: str = ""
    batch: int = 1
    img2img_path: Optional[str] = None
    strength: float = 0.75
    controlnet_model: Optional[str] = None
    controlnet_image: Optional[str] = None
    controlnet_strength: float = 0.9
    taesd_path: Optional[str] = None


class PresetBody(BaseModel):
    name: str
    data: dict


class ConfigBody(BaseModel):
    sd_bin: Optional[str] = None
    models_dir: Optional[str] = None
    output_dir: Optional[str] = None
    lora_dir: Optional[str] = None
    controlnet_dir: Optional[str] = None
    taesd_dir: Optional[str] = None
    flash_attention: Optional[bool] = None
    vae_tiling: Optional[bool] = None
    vae_on_cpu: Optional[bool] = None
    clip_on_cpu: Optional[bool] = None
    threads: Optional[int] = None
    theme: Optional[str] = None


# ── System ────────────────────────────────────────────────────────────────────

@router.get("/system")
async def system_info():
    conf = cfg_mod.load_config()
    version = await get_binary_version(conf["sd_bin"])
    binary_ok = version is not None
    return {
        "binary_ok": binary_ok,
        "binary_version": version,
        "samplers": SAMPLERS,
        "schedulers": SCHEDULERS,
    }


@router.get("/gpu")
async def gpu_info():
    return await get_gpu_info()


# ── Models ────────────────────────────────────────────────────────────────────

@router.get("/models")
async def list_models():
    conf = cfg_mod.load_config()
    models = detect_models(conf["models_dir"])
    return {"models": models}


# ── LoRAs ─────────────────────────────────────────────────────────────────────

@router.get("/loras")
async def list_loras():
    conf = cfg_mod.load_config()
    loras = detect_loras(conf["lora_dir"])
    return {"loras": loras}


# ── ControlNet ────────────────────────────────────────────────────────────────

@router.get("/controlnets")
async def list_controlnets():
    conf = cfg_mod.load_config()
    items = detect_controlnets(conf["controlnet_dir"])
    return {"controlnets": items}


# ── TAESD ─────────────────────────────────────────────────────────────────────

@router.get("/taesd")
async def list_taesd():
    conf = cfg_mod.load_config()
    items = detect_taesd(conf["taesd_dir"])
    return {"taesd": items}


# ── Config ────────────────────────────────────────────────────────────────────

@router.get("/config")
async def get_config():
    return cfg_mod.load_config()


@router.post("/config")
async def set_config(body: ConfigBody):
    conf = cfg_mod.load_config()
    data = body.model_dump(exclude_none=True)
    conf.update(data)
    cfg_mod.save_config(conf)
    return {"ok": True}


# ── Presets ───────────────────────────────────────────────────────────────────

@router.get("/presets")
async def get_presets():
    return cfg_mod.load_presets()


@router.post("/presets")
async def save_preset(body: PresetBody):
    presets = cfg_mod.load_presets()
    presets[body.name] = body.data
    cfg_mod.save_presets(presets)
    return {"ok": True}


@router.delete("/presets/{name}")
async def delete_preset(name: str):
    presets = cfg_mod.load_presets()
    presets.pop(name, None)
    cfg_mod.save_presets(presets)
    return {"ok": True}


# ── History ───────────────────────────────────────────────────────────────────

@router.get("/history")
async def get_history():
    return {"history": cfg_mod.load_history()}


# ── Gallery ───────────────────────────────────────────────────────────────────

@router.get("/gallery")
async def gallery(limit: int = 50, offset: int = 0, favorites_only: bool = False):
    conf = cfg_mod.load_config()
    output_dir = Path(conf["output_dir"])
    if not output_dir.exists():
        return {"images": [], "total": 0}

    favs = set(cfg_mod.load_favorites())
    all_imgs = sorted(
        (f for f in output_dir.glob("*.png") if f.is_file()),
        key=lambda f: f.stat().st_mtime,
        reverse=True,
    )

    if favorites_only:
        all_imgs = [f for f in all_imgs if f.name in favs]

    total = len(all_imgs)
    page = all_imgs[offset: offset + limit]
    images = [
        {
            "filename": f.name,
            "url": f"/outputs/{f.name}",
            "mtime": int(f.stat().st_mtime),
            "size": f.stat().st_size,
            "favorite": f.name in favs,
        }
        for f in page
    ]
    return {"images": images, "total": total}


# ── Favorites ─────────────────────────────────────────────────────────────────

@router.post("/favorites/{filename}")
async def toggle_favorite(filename: str):
    favs = cfg_mod.load_favorites()
    if filename in favs:
        favs.remove(filename)
        added = False
    else:
        favs.append(filename)
        added = True
    cfg_mod.save_favorites(favs)
    return {"favorite": added}


# ── File upload (img2img / controlnet) ────────────────────────────────────────

@router.post("/upload")
async def upload_file(file: UploadFile = File(...)):
    import tempfile, os
    suffix = Path(file.filename).suffix or ".png"
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=suffix)
    try:
        content = await file.read()
        tmp.write(content)
        tmp.close()
        return {"path": tmp.name, "filename": file.filename}
    except Exception as e:
        tmp.close()
        os.unlink(tmp.name)
        raise HTTPException(status_code=500, detail=str(e))


# ── Generate ─────────────────────────────────────────────────────────────────

@router.post("/generate")
async def generate(req: GenerateRequest):
    conf = cfg_mod.load_config()
    job = current_job()
    if job and job.status == "running":
        raise HTTPException(status_code=409, detail="A job is already running")

    # resolve model object
    models = detect_models(conf["models_dir"])
    model_obj = next((m for m in models if m["id"] == req.model_id), None)
    if model_obj is None:
        raise HTTPException(status_code=422, detail=f"Model '{req.model_id}' not found")
    if not model_obj["available"]:
        raise HTTPException(
            status_code=422,
            detail=f"Model missing files: {model_obj['missing_files']}",
        )

    params = req.model_dump()
    params["model"] = model_obj
    params["loras"] = [lr.model_dump() for lr in req.loras]

    new = new_job(params)

    # run in background
    asyncio.create_task(run_job(new, conf))

    # save to history
    cfg_mod.append_history({
        "job_id": new.job_id,
        "ts": int(time.time()),
        "model": req.model_id,
        "positive": req.positive,
        "negative": req.negative,
        "steps": req.steps,
        "cfg": req.cfg,
        "width": req.width,
        "height": req.height,
        "seed": req.seed,
        "loras": [lr.model_dump() for lr in req.loras],
    })

    return {"job_id": new.job_id, "status": "started"}


@router.post("/cancel")
async def cancel_job():
    job = current_job()
    if job is None:
        return {"cancelled": False, "reason": "No running job"}
    await job.cancel()
    return {"cancelled": True}


@router.get("/status")
async def job_status():
    job = current_job()
    if job is None:
        return {"running": False}
    return {
        "running": job.status == "running",
        "job_id": job.job_id,
        "status": job.status,
        "progress": job.progress,
    }


# ── Image metadata ────────────────────────────────────────────────────────────

@router.get("/image-meta/{filename}")
async def image_meta(filename: str):
    """Return PNG text chunks (generation metadata) if present."""
    conf = cfg_mod.load_config()
    output_dir = Path(conf["output_dir"])
    img_path = output_dir / filename
    if not img_path.exists():
        raise HTTPException(status_code=404, detail="Image not found")
    try:
        from PIL import Image
        with Image.open(img_path) as im:
            meta = dict(im.info)
            # remove non-serializable keys
            meta = {k: str(v) for k, v in meta.items() if isinstance(v, (str, int, float))}
            size = {"width": im.width, "height": im.height}
        return {"filename": filename, "size": size, "meta": meta}
    except Exception as e:
        return {"filename": filename, "size": {}, "meta": {"error": str(e)}}
