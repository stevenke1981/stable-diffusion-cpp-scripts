"""Detect available models, LoRAs, and system capabilities."""
import asyncio
import platform
import shutil
from pathlib import Path
from typing import Optional


# ── Model definitions ────────────────────────────────────────────────────────

MODEL_DEFS = [
    {
        "id": "flux-dev",
        "label": "FLUX.1-dev",
        "subdir": "flux",
        "patterns": ["flux1-dev*.gguf", "flux1-dev.safetensors"],
        "mode": "diffusion_model",
        "needs_vae": "flux/ae.safetensors",
        "needs_clip_l": "encoders/clip_l.safetensors",
        "needs_t5xxl": "encoders/t5xxl_fp16.safetensors",
        "defaults": {
            "steps": 20, "cfg": 1.0, "guidance": 3.5,
            "sampler": "euler", "scheduler": None,
            "width": 1280, "height": 720,
            "lora_support": True,
        },
    },
    {
        "id": "flux-schnell",
        "label": "FLUX.1-schnell",
        "subdir": "flux",
        "patterns": ["flux1-schnell*.gguf", "flux1-schnell.safetensors"],
        "mode": "diffusion_model",
        "needs_vae": "flux/ae.safetensors",
        "needs_clip_l": "encoders/clip_l.safetensors",
        "needs_t5xxl": "encoders/t5xxl_fp16.safetensors",
        "defaults": {
            "steps": 4, "cfg": 1.0, "guidance": 3.5,
            "sampler": "euler", "scheduler": None,
            "width": 1280, "height": 720,
            "lora_support": True,
        },
    },
    {
        "id": "chroma",
        "label": "Chroma",
        "subdir": "chroma",
        "patterns": ["chroma*.gguf"],
        "mode": "diffusion_model",
        "needs_vae": "flux/ae.safetensors",
        "needs_clip_l": "encoders/clip_l.safetensors",
        "defaults": {
            "steps": 30, "cfg": 7.0, "guidance": None,
            "sampler": "dpm++2m", "scheduler": "karras",
            "width": 1280, "height": 720,
            "lora_support": False,
        },
    },
    {
        "id": "sd35",
        "label": "SD 3.5 Large",
        "subdir": "sd3",
        "patterns": ["*.safetensors"],
        "mode": "diffusion_model",
        "needs_clip_l": "encoders/clip_l.safetensors",
        "needs_clip_g": "encoders/clip_g.safetensors",
        "needs_t5xxl": "encoders/t5xxl_fp16.safetensors",
        "defaults": {
            "steps": 28, "cfg": 4.5, "guidance": None,
            "sampler": "euler", "scheduler": None,
            "width": 1280, "height": 720,
            "lora_support": True,
        },
    },
    {
        "id": "sdxl",
        "label": "SDXL 1.0",
        "subdir": "sdxl",
        "patterns": ["sd_xl_base_1.0.safetensors"],
        "mode": "model",
        "defaults": {
            "steps": 25, "cfg": 7.5, "guidance": None,
            "sampler": "dpm++2m", "scheduler": "karras",
            "width": 1280, "height": 720,
            "lora_support": True,
        },
    },
    {
        "id": "sdxl-turbo",
        "label": "SDXL Turbo",
        "subdir": "sdxl",
        "patterns": ["sd_xl_turbo_1.0*.safetensors"],
        "mode": "model",
        "defaults": {
            "steps": 4, "cfg": 0.0, "guidance": None,
            "sampler": "euler", "scheduler": None,
            "width": 1280, "height": 720,
            "lora_support": True,
        },
    },
    {
        "id": "sd15",
        "label": "SD 1.5",
        "subdir": "sd1x",
        "patterns": ["*.safetensors", "*.ckpt"],
        "mode": "model",
        "defaults": {
            "steps": 25, "cfg": 7.5, "guidance": None,
            "sampler": "dpm++2m", "scheduler": "karras",
            "width": 1280, "height": 720,
            "lora_support": True,
        },
    },
]

SAMPLERS = [
    "euler", "euler_a", "dpm++2m", "dpm++2m_v2", "dpm++2s_a",
    "heun", "dpm2", "dpm2_a", "lcm", "ddim", "plms",
]
SCHEDULERS = ["", "karras", "exponential", "ays", "gits"]


def _find_first(base: Path, patterns: list[str]) -> Optional[Path]:
    for pat in patterns:
        hits = sorted(base.glob(pat))
        if hits:
            return hits[0]
    return None


def detect_models(models_dir: str) -> list[dict]:
    base = Path(models_dir)
    results = []

    for defn in MODEL_DEFS:
        subdir = base / defn["subdir"]
        model_path = _find_first(subdir, defn["patterns"])
        if model_path is None:
            continue

        missing = []

        def _check(key: str) -> Optional[str]:
            rel = defn.get(key)
            if rel is None:
                return None
            p = base / rel
            if not p.exists():
                missing.append(str(p))
            return str(p)

        entry = {
            "id": defn["id"],
            "label": defn["label"],
            "path": str(model_path),
            "mode": defn["mode"],
            "defaults": defn["defaults"],
            "available": True,
            "missing_files": missing,
            "vae": _check("needs_vae"),
            "clip_l": _check("needs_clip_l"),
            "clip_g": _check("needs_clip_g"),
            "t5xxl": _check("needs_t5xxl"),
        }
        entry["available"] = len(missing) == 0
        results.append(entry)

    return results


def detect_loras(lora_dir: str) -> list[dict]:
    base = Path(lora_dir)
    if not base.exists():
        return []
    exts = {".safetensors", ".pt", ".bin", ".gguf"}
    loras = []
    for f in sorted(base.rglob("*")):
        if f.suffix.lower() in exts and f.is_file():
            rel = f.relative_to(base)
            name = str(rel.with_suffix("")).replace("\\", "/")
            loras.append({"name": name, "path": str(f), "filename": f.name})
    return loras


def detect_controlnets(controlnet_dir: str) -> list[dict]:
    base = Path(controlnet_dir)
    if not base.exists():
        return []
    exts = {".safetensors", ".gguf", ".pt"}
    items = []
    for f in sorted(base.rglob("*")):
        if f.suffix.lower() in exts and f.is_file():
            items.append({"name": f.stem, "path": str(f)})
    return items


def detect_taesd(taesd_dir: str) -> list[dict]:
    base = Path(taesd_dir)
    if not base.exists():
        return []
    return [
        {"name": f.stem, "path": str(f)}
        for f in sorted(base.glob("*.safetensors"))
    ]


async def get_binary_version(sd_bin: str) -> Optional[str]:
    try:
        proc = await asyncio.create_subprocess_exec(
            sd_bin, "--version",
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        stdout, stderr = await asyncio.wait_for(proc.communicate(), timeout=5)
        out = (stdout or stderr or b"").decode(errors="replace").strip()
        return out[:120] if out else "unknown"
    except Exception:
        return None


async def get_gpu_info() -> dict:
    """Try nvidia-smi for VRAM stats."""
    try:
        proc = await asyncio.create_subprocess_exec(
            "nvidia-smi",
            "--query-gpu=name,memory.used,memory.total,utilization.gpu",
            "--format=csv,noheader,nounits",
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        stdout, _ = await asyncio.wait_for(proc.communicate(), timeout=4)
        line = stdout.decode(errors="replace").strip().split("\n")[0]
        parts = [p.strip() for p in line.split(",")]
        if len(parts) >= 4:
            return {
                "name": parts[0],
                "vram_used": int(parts[1]),
                "vram_total": int(parts[2]),
                "gpu_util": int(parts[3]),
                "available": True,
            }
    except Exception:
        pass
    return {"available": False}
