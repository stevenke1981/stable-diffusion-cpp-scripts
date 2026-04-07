@echo off
:: =============================================================================
:: SD.cpp Web UI launcher (Windows)
:: =============================================================================
setlocal

set SCRIPT_DIR=%~dp0
set VENV=%SCRIPT_DIR%.venv
set HOST=%HOST_OVERRIDE%
if "%HOST%"=="" set HOST=127.0.0.1
set PORT=%PORT_OVERRIDE%
if "%PORT%"=="" set PORT=7860

if not exist "%VENV%\Scripts\python.exe" (
    echo [i] Creating Python venv...
    python -m venv "%VENV%"
)

echo [i] Installing dependencies...
"%VENV%\Scripts\pip" install -q -r "%SCRIPT_DIR%requirements.txt"

echo [i] Web UI -^> http://%HOST%:%PORT%
echo [i] Press Ctrl+C to stop

cd /d "%SCRIPT_DIR%"
"%VENV%\Scripts\python" -m uvicorn webui.main:app --host %HOST% --port %PORT%
pause
