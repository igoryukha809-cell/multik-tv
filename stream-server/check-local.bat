@echo off
setlocal
cd /d "%~dp0"
echo MULTIK TV - LOCAL STREAM DIAGNOSTICS
echo.
where bash >nul 2>nul
if errorlevel 1 (
  echo Bash was not found. Install Git for Windows or use check-local.sh on macOS/Linux.
  pause
  exit /b 2
)
bash check-local.sh
echo.
pause
