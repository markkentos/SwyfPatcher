@echo off
setlocal
title SwyfPatcher v2.7 - Qwen3 patch for Scam With Your Friends
echo SwyfPatcher v2.7 (universal, no .NET SDK required). Close the game first.
echo Usage: SwyfPatch.bat [--backend auto^|cpu^|vulkan] [--model q4^|q8] [--check ^| --restore] [game-folder]
set "SCRIPT=%~dp0src\SwyfPatch.ps1"
if not exist "%SCRIPT%" (
    echo [FAIL] src\SwyfPatch.ps1 not found next to this launcher. Keep the repository layout intact.
    pause
    exit /b 1
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" %*
set "RC=%errorlevel%"
echo.
if "%RC%"=="0" (echo Completed successfully.) else if "%RC%"=="2" (echo Done with warnings: read the output above.) else (echo FAILED: read the output above.)
pause
exit /b %RC%
