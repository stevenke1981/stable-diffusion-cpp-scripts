"""Configuration management for SD.cpp Web UI."""
import json
import os
import platform
from pathlib import Path
from typing import Optional


def _default_config_dir() -> Path:
    if platform.system() == "Windows":
        base = Path(os.environ.get("APPDATA", Path.home()))
    else:
        base = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))
    d = base / "sdcpp-webui"
    d.mkdir(parents=True, exist_ok=True)
    return d


CONFIG_DIR = _default_config_dir()
CONFIG_FILE = CONFIG_DIR / "config.json"
PRESETS_FILE = CONFIG_DIR / "presets.json"
HISTORY_FILE = CONFIG_DIR / "history.json"
FAVORITES_FILE = CONFIG_DIR / "favorites.json"

HOME = Path.home()

DEFAULTS: dict = {
    "sd_bin": str(HOME / "stable-diffusion.cpp" / "build" / "bin" / "sd"),
    "models_dir": str(HOME / "sd-models"),
    "output_dir": str(HOME / "sd-outputs"),
    "lora_dir": str(HOME / "sd-models" / "loras"),
    "controlnet_dir": str(HOME / "sd-models" / "controlnet"),
    "taesd_dir": str(HOME / "sd-models" / "taesd"),
    "host": "127.0.0.1",
    "port": 7860,
    "theme": "dark",
    "flash_attention": True,
    "vae_tiling": False,
    "vae_on_cpu": False,
    "clip_on_cpu": False,
    "threads": -1,
}


def load_config() -> dict:
    if CONFIG_FILE.exists():
        try:
            data = json.loads(CONFIG_FILE.read_text(encoding="utf-8"))
            # merge missing keys with defaults
            for k, v in DEFAULTS.items():
                data.setdefault(k, v)
            return data
        except Exception:
            pass
    return dict(DEFAULTS)


def save_config(data: dict) -> None:
    CONFIG_FILE.write_text(
        json.dumps(data, indent=2, ensure_ascii=False), encoding="utf-8"
    )


def load_presets() -> dict:
    if PRESETS_FILE.exists():
        try:
            return json.loads(PRESETS_FILE.read_text(encoding="utf-8"))
        except Exception:
            pass
    return {}


def save_presets(data: dict) -> None:
    PRESETS_FILE.write_text(
        json.dumps(data, indent=2, ensure_ascii=False), encoding="utf-8"
    )


def load_history() -> list:
    if HISTORY_FILE.exists():
        try:
            return json.loads(HISTORY_FILE.read_text(encoding="utf-8"))
        except Exception:
            pass
    return []


def append_history(entry: dict, max_items: int = 100) -> None:
    history = load_history()
    history.insert(0, entry)
    history = history[:max_items]
    HISTORY_FILE.write_text(
        json.dumps(history, indent=2, ensure_ascii=False), encoding="utf-8"
    )


def load_favorites() -> list:
    if FAVORITES_FILE.exists():
        try:
            return json.loads(FAVORITES_FILE.read_text(encoding="utf-8"))
        except Exception:
            pass
    return []


def save_favorites(data: list) -> None:
    FAVORITES_FILE.write_text(
        json.dumps(data, indent=2, ensure_ascii=False), encoding="utf-8"
    )
