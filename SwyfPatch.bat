@echo off
setlocal
title SwyfPatcher 2.9.6 - Qwen3 patch and diagnostics
echo SwyfPatcher 2.9.6
set "SCRIPT=%~dp0src\SwyfPatch.ps1"
if not exist "%SCRIPT%" (
    echo [FAIL] src\SwyfPatch.ps1 not found next to this launcher. Keep the repository layout intact.
    pause
    exit /b 1
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" %*
set "RC=%errorlevel%"
echo.
echo SwyfPatcher [RC=%RC%]
pause
exit /b %RC%
