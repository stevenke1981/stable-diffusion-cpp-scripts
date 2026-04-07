#!/usr/bin/env bash
# =============================================================================
# SD.cpp Web UI launcher
# Usage: ./launch-webui.sh [--host 0.0.0.0] [--port 7860]
# Remote: ssh -L 7860:localhost:7860 user@host && open http://localhost:7860
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV="$SCRIPT_DIR/.venv"
REQ="$SCRIPT_DIR/requirements.txt"

HOST="${HOST:-127.0.0.1}"
PORT="${PORT:-7860}"

# Parse CLI args
while [[ $# -gt 0 ]]; do
  case $1 in
    --host) HOST="$2"; shift 2 ;;
    --port) PORT="$2"; shift 2 ;;
    *) shift ;;
  esac
done

# Create venv if missing
if [[ ! -f "$VENV/bin/python" && ! -f "$VENV/Scripts/python.exe" ]]; then
  echo "[i] Creating Python venv…"
  python3 -m venv "$VENV"
fi

# Detect pip path (Unix vs Windows/WSL)
PIP="$VENV/bin/pip"
PY="$VENV/bin/python"
UV="$VENV/bin/uvicorn"
[[ ! -f "$PIP" ]] && PIP="$VENV/Scripts/pip"
[[ ! -f "$PY" ]]  && PY="$VENV/Scripts/python"
[[ ! -f "$UV" ]]  && UV="$VENV/Scripts/uvicorn"

# Install / update deps
echo "[i] Checking dependencies…"
"$PIP" install -q -r "$REQ"

echo "[i] Web UI → http://${HOST}:${PORT}"
echo "[i] Press Ctrl+C to stop"
echo ""

cd "$SCRIPT_DIR"
exec "$PY" -m uvicorn webui.main:app --host "$HOST" --port "$PORT"
