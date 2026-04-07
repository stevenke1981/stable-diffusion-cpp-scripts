"""Subprocess management for sd binary generation jobs."""
import asyncio
import json
import platform
import random
import re
import time
import uuid
from pathlib import Path
from typing import Optional

# ── Job state ─────────────────────────────────────────────────────────────────

class Job:
    def __init__(self, job_id: str, params: dict):
        self.job_id = job_id
        self.params = params
        self.status = "queued"   # queued | running | done | error | cancelled
        self.lines: list[str] = []
        self.outputs: list[str] = []
        self.progress = (0, 0)
        self.error: Optional[str] = None
        self.started_at = time.time()
        self._proc: Optional[asyncio.subprocess.Process] = None
        self._ws_queues: list[asyncio.Queue] = []

    def subscribe(self) -> asyncio.Queue:
        q: asyncio.Queue = asyncio.Queue()
        self._ws_queues.append(q)
        return q

    def unsubscribe(self, q: asyncio.Queue) -> None:
        self._ws_queues.discard(q) if hasattr(self._ws_queues, "discard") else None
        try:
            self._ws_queues.remove(q)
        except ValueError:
            pass

    def _broadcast(self, msg: dict) -> None:
        data = json.dumps(msg)
        for q in list(self._ws_queues):
            q.put_nowait(data)

    async def cancel(self) -> None:
        self.status = "cancelled"
        if self._proc and self._proc.returncode is None:
            try:
                self._proc.terminate()
                await asyncio.sleep(1)
                if self._proc.returncode is None:
                    self._proc.kill()
            except Exception:
                pass
        self._broadcast({"type": "error", "message": "Cancelled by user"})


# ── Global job registry ───────────────────────────────────────────────────────

_current_job: Optional[Job] = None


def current_job() -> Optional[Job]:
    return _current_job


def get_job(job_id: str) -> Optional[Job]:
    if _current_job and _current_job.job_id == job_id:
        return _current_job
    return None


# ── CMD builder ───────────────────────────────────────────────────────────────

def _snap64(v: int) -> int:
    return max(64, (v // 64) * 64)


def build_cmd(params: dict, cfg: dict, output_path: str) -> tuple[list[str], int]:
    sd_bin = cfg["sd_bin"]
    models_dir = Path(cfg["models_dir"])

    model = params["model"]          # dict from env_detect
    mode = model.get("mode", "model")

    cmd = [sd_bin]

    # ── model flags ──────────────────────────────────────────────────────────
    if mode == "diffusion_model":
        cmd += ["--diffusion-model", model["path"]]
        if model.get("vae"):
            cmd += ["--vae", model["vae"]]
        if model.get("clip_l"):
            cmd += ["--clip_l", model["clip_l"]]
        if model.get("clip_g"):
            cmd += ["--clip_g", model["clip_g"]]
        if model.get("t5xxl"):
            cmd += ["--t5xxl", model["t5xxl"]]
    else:
        cmd += ["-m", model["path"]]

    # ── img2img ──────────────────────────────────────────────────────────────
    img2img_path = params.get("img2img_path")
    if img2img_path and Path(img2img_path).exists():
        cmd += ["-i", img2img_path]
        strength = float(params.get("strength", 0.75))
        cmd += ["--strength", f"{strength:.2f}"]

    # ── prompt ───────────────────────────────────────────────────────────────
    positive = params.get("positive", "").strip()
    # inject loras into prompt
    loras = params.get("loras", [])
    for lr in loras:
        if lr.get("enabled"):
            token = f"<lora:{lr['name']}:{lr.get('weight', 1.0):.2f}>"
            if token not in positive:
                positive = f"{positive} {token}".strip()

    cmd += ["-p", positive or "a beautiful photo"]

    negative = params.get("negative", "").strip()
    if negative:
        cmd += ["-n", negative]

    # ── generation params ────────────────────────────────────────────────────
    cmd += ["--steps", str(int(params.get("steps", 20)))]
    cmd += ["--cfg-scale", str(float(params.get("cfg", 7.5)))]

    guidance = params.get("guidance")
    if guidance is not None and str(guidance) != "":
        cmd += ["--guidance", str(float(guidance))]

    w = _snap64(int(params.get("width", 1280)))
    h = _snap64(int(params.get("height", 720)))
    cmd += ["-W", str(w), "-H", str(h)]

    seed = int(params.get("seed", -1))
    if seed == -1:
        seed = random.randint(0, 2**32 - 1)
    cmd += ["-s", str(seed)]

    sampler = params.get("sampler", "euler")
    cmd += ["--sampling-method", sampler]

    scheduler = params.get("scheduler", "")
    if scheduler:
        cmd += ["--scheduler", scheduler]

    batch = max(1, int(params.get("batch", 1)))
    cmd += ["-b", str(batch)]

    # ── lora dir ─────────────────────────────────────────────────────────────
    if loras and any(lr.get("enabled") for lr in loras):
        cmd += ["--lora-model-dir", cfg["lora_dir"]]

    # ── controlnet ───────────────────────────────────────────────────────────
    cn_model = params.get("controlnet_model")
    cn_image = params.get("controlnet_image")
    if cn_model and cn_image and Path(cn_image).exists():
        cmd += ["--control-net", cn_model]
        cmd += ["--control-image", cn_image]
        cmd += ["--control-strength", str(float(params.get("controlnet_strength", 0.9)))]

    # ── TAESD ────────────────────────────────────────────────────────────────
    taesd = params.get("taesd_path")
    if taesd and Path(taesd).exists():
        cmd += ["--taesd", taesd]

    # ── VRAM options ─────────────────────────────────────────────────────────
    if cfg.get("vae_tiling"):
        cmd += ["--vae-tiling"]
    if cfg.get("vae_on_cpu"):
        cmd += ["--vae-on-cpu"]
    if cfg.get("clip_on_cpu"):
        cmd += ["--clip-on-cpu"]

    # ── Flash Attention ───────────────────────────────────────────────────────
    if cfg.get("flash_attention", True) and mode == "diffusion_model":
        cmd += ["--fa"]

    # ── threads ──────────────────────────────────────────────────────────────
    threads = int(cfg.get("threads", -1))
    if threads > 0:
        cmd += ["-t", str(threads)]

    cmd += ["-o", output_path, "-v"]
    return cmd, seed


# ── Runner ────────────────────────────────────────────────────────────────────

_STEP_RE = re.compile(r"step\s+(\d+)\s*/\s*(\d+)", re.IGNORECASE)
_DONE_RE = re.compile(r"saving image to\s+(.+)", re.IGNORECASE)


async def run_job(job: Job, cfg: dict) -> None:
    global _current_job
    _current_job = job

    params = job.params
    output_dir = Path(cfg["output_dir"])
    output_dir.mkdir(parents=True, exist_ok=True)

    model_id = params.get("model", {}).get("id", "output")
    ts = int(time.time())
    output_pattern = str(output_dir / f"{model_id}_{ts}_%03d.png")

    try:
        cmd, resolved_seed = build_cmd(params, cfg, output_pattern)
    except Exception as e:
        job.status = "error"
        job.error = str(e)
        job._broadcast({"type": "error", "message": str(e)})
        return

    # Store resolved seed back
    job.params["resolved_seed"] = resolved_seed

    job._broadcast({"type": "log", "line": f"[cmd] {' '.join(cmd)}"})
    job._broadcast({"type": "log", "line": f"[seed] {resolved_seed}"})

    job.status = "running"

    try:
        # On Windows use shell=False explicitly
        proc = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.STDOUT,
        )
        job._proc = proc

        async for raw in proc.stdout:
            line = raw.decode(errors="replace").rstrip()
            job.lines.append(line)
            job._broadcast({"type": "log", "line": line})

            m = _STEP_RE.search(line)
            if m:
                cur, total = int(m.group(1)), int(m.group(2))
                job.progress = (cur, total)
                job._broadcast({"type": "progress", "current": cur, "total": total})

            dm = _DONE_RE.search(line)
            if dm:
                saved = dm.group(1).strip()
                job.outputs.append(saved)

        await proc.wait()

        if proc.returncode != 0 and job.status != "cancelled":
            job.status = "error"
            job.error = f"Process exited with code {proc.returncode}"
            job._broadcast({"type": "error", "message": job.error})
        else:
            if job.status != "cancelled":
                job.status = "done"
                # Prefer stdout-parsed paths; fall back to mtime scan
                if job.outputs:
                    outputs = [p for p in job.outputs if Path(p).exists()]
                else:
                    outputs = _collect_outputs(output_dir, ts, model_id)
                job.outputs = outputs
                job._broadcast({
                    "type": "done",
                    "outputs": [f"/outputs/{Path(p).name}" for p in outputs],
                    "seed": resolved_seed,
                })

    except Exception as e:
        job.status = "error"
        job.error = str(e)
        job._broadcast({"type": "error", "message": str(e)})
    finally:
        if _current_job is job:
            _current_job = None


def _collect_outputs(output_dir: Path, ts: int, model_id: str) -> list[str]:
    """Find PNG files written at or after ts."""
    results = []
    for f in sorted(output_dir.glob("*.png")):
        try:
            if f.stat().st_mtime >= ts - 1:
                results.append(str(f))
        except Exception:
            pass
    return results


def new_job(params: dict) -> Job:
    job_id = uuid.uuid4().hex[:8]
    return Job(job_id, params)
